/**
    Contains functionality required to load Vulkan functions and create instances/devices for use by the Vulkan API.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: MIT
*/
module denjin.rendering.vulkan.loader;

// Phobos.
import core.stdc.string         : strcmp;
import std.algorithm.iteration  : each;
import std.algorithm.mutation   : move;
import std.algorithm.searching  : all, canFind;
import std.container.array      : Array;
import std.container.util       : make;
import std.conv                 : to;
import std.exception            : enforce;
import std.meta                 : AliasSeq, aliasSeqOf;
import std.range                : repeat, takeExactly;
import std.stdio                : writeln;
import std.string               : fromStringz, toStringz;
import std.typecons             : No, Yes;

// Engine.
import denjin.rendering.vulkan.device       : Device;
import denjin.rendering.vulkan.misc         : enforceSuccess, safelyDestroyVK;
import denjin.rendering.vulkan.nulls;
import denjin.rendering.vulkan.renderer     : RendererVulkan;
import denjin.rendering.vulkan.swapchain    : Swapchain;

// External.
import erupted;

// Debug.
debug import denjin.rendering.vulkan.logging : logExtensionProperties, logLayerProperties, logPhysicalDeviceProperties, 
                                               logQueueFamilyProperties;

/// A basic structure, allowing for the creation and management of Vulkan instances and devices.
struct Instance
{
    private
    {
        alias DebugCallback = VkDebugReportCallbackEXT;
        alias Extensions    = Array!(const(char)*);
        alias Layers        = Array!(const(char)*);
        alias Surfaces      = Array!VkSurfaceKHR;

        // Core members.
        VkInstance          m_instance      = nullInstance; /// A handle to a created vulkan instance.
        debug DebugCallback m_debugCallback = nullDebug;    /// A handle to a debug reporting object.
        Extensions          m_instanceExts;                 /// The extensions enabled for the instance.
        Layers              m_layers;                       /// The layers enabled for the instance.
        Surfaces            m_surfaces;                     /// The surfaces that have been used to create devices from this loader.

        // Device creation cache.
        Extensions  m_deviceExts;   /// The extensions enabled for the device.
        Info        m_info;         /// Contains descriptive information regarding how the Vulkan instance is configured.
    }

    /// Subtype VkInstance to allow for implicit retrieval of the managed handle.
    alias handle this;
    
    /// A function pointer to the vkGetInstanceProcAddr function is required to create instances.
    alias InstanceProcAddress = typeof (vkGetInstanceProcAddr);

    /// The object is not copyable.
    @disable this(this);

    /// Performs the first and second stage of Vulkan loading. Loading the global-level functions required by Vulkan, 
    /// creating an instance and loading instance-level functions. The next stage would be to create devices/renderers. 
    /// In debug builds this will also register a debug callback which will prints information to the console.
    /// Params:
    ///     proc            = The pointer to a function used to load global-level Vulkan functions.
    ///     extensionCount  = How many extensions will be loaded.
    ///     extensions      = A collection extension names to be loaded.
    public this (in InstanceProcAddress proc, in uint32_t extensionCount, in char** extensions)
    {
        // Pre-conditions.
        enforce (proc != null);
        enforce (extensionCount == 0 || extensions != null);

        // We must ensure that global-level Vulkan functions are loaded before trying to create an instance.
        loadGlobalLevelFunctions (proc);
        createInstance (extensionCount, extensions);
    }

    /// Destroys any stored instances/surfaces.
    nothrow
    public ~this()
    {
        clear();
    }

    /// Constructs a renderer which is derived from the current instance. This will evaluate physical devices available
    /// to the system, check their capabilities and create a logical device which will be given to the constructed
    /// renderer. The given surface will also be used to initialise a swapchain which will also be given to the 
    /// constructed renderer.
    ///
    /// Params: surface = The surface to display images to. The instance will take ownership of this.
    /// Returns: A renderer which will need to be initialised before being used for rendering.
    public RendererVulkan createRenderer (VkSurfaceKHR surface = nullSurface)
    in
    {
        assert (m_instance != nullInstance);
        assert (surface != nullSurface);
    }
    body
    {
        // Take ownership of the surface.
        if (surface != nullSurface && !(canFind (m_surfaces[0..$], surface)))
        {
            m_surfaces.insertBack (surface);
        }

        // Now we can check the hardware on the machine to chose a physical device to use.
        const auto gpuIndex = enumerateDevices();
        auto       gpu      = m_info.physicalDevices[gpuIndex];

        // Ensure we enable any necessary extensions.
        m_info.device.enabledExtensionCount     = cast (uint32_t) m_deviceExts.length;
        m_info.device.ppEnabledExtensionNames   = &m_deviceExts.front();

        // Construct the renderer!
        auto device     = Device (gpu, m_info.device, surface, null);
        auto swapchain  = Swapchain (gpu, surface);
        return new RendererVulkan (move (device), move (swapchain));
    }

    /// Gets the handle being managed by the Instance struct.
    public @property inout(VkInstance) handle() inout pure nothrow @safe @nogc { return m_instance; }

    /// Checks if the vulkan instance has been initialised and is ready for use.
    public @property bool isInitialised() const pure nothrow @safe @nogc { return m_instance != nullInstance; }

    /// Destroys stored instance and surfaces, etc.
    public void clear() nothrow
    {
        // The instance must be destroyed last.
        debug m_debugCallback.safelyDestroyVK (vkDestroyDebugReportCallbackEXT, m_instance, m_debugCallback, null);
        m_surfaces.each!(s => s.safelyDestroyVK (vkDestroySurfaceKHR, m_instance, s, null));
        m_instance.safelyDestroyVK (vkDestroyInstance, m_instance, null);

        m_instanceExts.clear();
        m_layers.clear();
        m_surfaces.clear();
        m_deviceExts.clear();
        m_info.clear();
    }

    /// Performs the second stage of Vulkan loading, creating an instance for the application and loading 
    /// the instance-level functions associated with it. 
    private void createInstance (in uint32_t extensionCount, in char** extensions)
    {
        // We must describe how the instance should be created.
        enumerateInstanceExtensions (extensionCount, extensions);
        enumerateLayers();
        const auto extCount     = cast (uint32_t) m_instanceExts.length;
        const auto extNames     = extCount == 0 ? null : &m_instanceExts.front();
        const auto layerCount   = cast (uint32_t) m_layers.length;
        const auto layerNames   = layerCount == 0 ? null : &m_layers.front();

        m_info.instance.pApplicationInfo        = &m_info.app;
        m_info.instance.enabledLayerCount       = layerCount;
        m_info.instance.ppEnabledLayerNames     = layerNames;
        m_info.instance.enabledExtensionCount   = extCount;
        m_info.instance.ppEnabledExtensionNames = extNames;

        // Finally the instance can be created.
        vkCreateInstance (&m_info.instance, null, &m_instance).enforceSuccess;

        // Ensure we load the function pointers required to create a device and a debug callback.
        loadInstanceLevelFunctions (m_instance);
        printExtensionsAndLayers();
        debug createDebugCallback();
    }

    /// Checks the extensions available to the instance and attempts to load any necessary for rendering.
    private void enumerateInstanceExtensions (in uint32_t externalExtCount, in char** externalExt)
    {
        // Retrieve the number of extensions available.
        uint32_t count = void;
        vkEnumerateInstanceExtensionProperties (null, &count, null).enforceSuccess;

        // Now retrieve them.
        m_info.instanceExtProperties.length = count;
        vkEnumerateInstanceExtensionProperties (null, &count, &m_info.instanceExtProperties.front()).enforceSuccess;
        debug logExtensionProperties ("Instance", m_info.instanceExtProperties);

        // Reserve memory to speed up the process.
        enum requiredExtensions = Info.requiredInstanceExtensions!();
        m_instanceExts.clear;
        m_instanceExts.reserve (requiredExtensions.length + externalExtCount);

        // First check the externally required extensions exist.
        alias cmpExt    = (a, b) => strcmp (a.extensionName.ptr, b) == 0;
        alias cmpCopy   = (a, b) => strcmp (a, b) == 0;
        foreach (i; 0..externalExtCount)
        {
            auto name = externalExt[i];
            enforce (canFind!(cmpExt) (m_info.instanceExtProperties[0..$], name), 
                     "Required Vulkan extension is not supported: " ~ name.fromStringz);

            // We need to duplicate the string to ensure ownership.
            m_instanceExts.insertBack (name.fromStringz.toStringz);
        }

        // Now check internally required extensions. None may be required.
        static if (requiredExtensions.length > 0 && requiredExtensions[0] != "")
        {
            foreach (name; requiredExtensions)
            {
                auto cName = name.toStringz;
                enforce (canFind!(cmpExt) (m_info.instanceExtProperties[0..$], cName), 
                            "Required Vulkan extension is not supported: " ~ name);

                if (!canFind!(cmpCopy)(m_instanceExts[0..$], cName))
                {
                    m_instanceExts.insertBack (cName);
                }
            }
        }
    }

    /// Checks the layers available to the instance and attempts to load any necessary debug layers.
    private void enumerateLayers()
    {
        // First we must retrieve the number of layers.
        uint32_t count = void;
        vkEnumerateInstanceLayerProperties (&count, null).enforceSuccess;

        // Now we can retrieve them.
        m_info.layerProperties.length = count;
        vkEnumerateInstanceLayerProperties (&count, &m_info.layerProperties.front()).enforceSuccess;
        debug logLayerProperties (m_info.layerProperties);
            
        // Next we must check for layers required by the loader based on the debug level. Also compile-time foreach ftw!
        enum requiredLayers = Info.requiredLayers!();
        m_layers.clear();
            
        // Handle the case where no layers are to be loaded.
        static if (requiredLayers.length > 0 && requiredLayers[0] != "")
        {
            m_layers.reserve (requiredLayers.length);
            alias cmpLayer = (a, b) => strcmp (a.layerName.ptr, b) == 0;
            foreach (name; requiredLayers)
            {
                // Ensure the layer is accessible.
                auto cName = name.toStringz;
                enforce (canFind!(cmpLayer) (m_info.layerProperties[0..$], cName), 
                         "Required Vulkan layer is not supported: " ~ name);

                // The C-string can be added to the collection of names.
                m_layers.insertBack (cName);
            }
        }
    }

    /// Retrieves the number of available devices and their associated properties.
    /// Returns: The index of the device that features the required capabilities.
    private size_t enumerateDevices()
    {
        // Get the number of devices.
        uint32_t count = void;
        vkEnumeratePhysicalDevices (m_instance, &count, null).enforceSuccess;

        // Retrieve the handles and properties of each device.
        m_info.physicalDevices.length           = count;
        m_info.physicalDeviceProperties.length  = count;
        m_info.deviceExtProperties.length       = count;
        vkEnumeratePhysicalDevices (m_instance, &count, &m_info.physicalDevices.front()).enforceSuccess;

        foreach (i; 0..count)
        {
            auto device = m_info.physicalDevices[i];
            vkGetPhysicalDeviceProperties (device, &m_info.physicalDeviceProperties[i]);

            uint32_t extCount = void;
            vkEnumerateDeviceExtensionProperties (device, null, &extCount, null).enforceSuccess;

            m_info.deviceExtProperties[i].length = extCount;
            vkEnumerateDeviceExtensionProperties (device, null, &extCount, 
                                                    &m_info.deviceExtProperties[i].front()).enforceSuccess;
        }
            
        debug logPhysicalDeviceProperties (m_info.physicalDeviceProperties, m_info.deviceExtProperties);
        enforce (!m_info.physicalDevices.empty);

        // Only check the first device atm.
        enum requiredExtensions = Info.requiredDeviceExtensions!();
        m_deviceExts.clear();
        m_deviceExts.reserve (requiredExtensions.length);

        alias cmpExtension = (a, b) => strcmp (a.extensionName.ptr, b) == 0;
        foreach (ext; requiredExtensions)
        {
            auto cName = ext.toStringz;
            enforce (canFind!(cmpExtension)(m_info.deviceExtProperties.front[0..$], cName));
            m_deviceExts.insertBack (cName);
        }

        return 0;
    }

    /// Prints the validation layer and extension names in use by the current instance.
    private void printExtensionsAndLayers() const
    {
        foreach (i; 0..m_info.instance.enabledExtensionCount)
        {
            writeln ("Vulkan instance extension activated: ", m_info.instance.ppEnabledExtensionNames[i].fromStringz);
        }
        foreach (i; 0..m_info.instance.enabledLayerCount)
        {
            writeln ("Vulkan instance layer activated: ", m_info.instance.ppEnabledLayerNames[i].fromStringz);
        }
        writeln;
    }

    /// Creates the debug callback object which will different debugging information.
    debug private void createDebugCallback()    
    in
    {
        assert (m_instance != nullInstance);
        assert (vkCreateDebugReportCallbackEXT);
    }
    body
    {
        version (optimized)
        {
            m_info.debugCallback.flags =    
                VK_DEBUG_REPORT_WARNING_BIT_EXT | 
                VK_DEBUG_REPORT_PERFORMANCE_WARNING_BIT_EXT |
                VK_DEBUG_REPORT_ERROR_BIT_EXT;
        }
        else version (assert)
        {
            m_info.debugCallback.flags =    
                VK_DEBUG_REPORT_INFORMATION_BIT_EXT |
                VK_DEBUG_REPORT_WARNING_BIT_EXT | 
                VK_DEBUG_REPORT_PERFORMANCE_WARNING_BIT_EXT |
                VK_DEBUG_REPORT_ERROR_BIT_EXT |
                VK_DEBUG_REPORT_DEBUG_BIT_EXT;
        }
        else
        {
            static assert (false, "This should not trigger in release mode!");
        }

        m_info.debugCallback.pfnCallback = &logVulkanError;
        vkCreateDebugReportCallbackEXT (m_instance, &m_info.debugCallback, null, &m_debugCallback).enforceSuccess;
    }
}

debug private extern (System) nothrow @nogc
VkBool32 logVulkanError (VkDebugReportFlagsEXT flags, VkDebugReportObjectTypeEXT objectType, uint64_t object, 
                         size_t location, int32_t messageCode, const(char)* pLayerPrefix, const(char)* pMessage, 
                         void* pUserData)
{
    import core.stdc.stdio  : printf;
    import std.traits       : EnumMembers;

    /// This is unnecessarily templatey because of the unnecessary @nogc requirement. It also has to use if statements
    /// because enums can contain duplicate numeric values in D, causing compilation errors. This will be slow but it's 
    /// a debugging function after all.
    template printfEnum (Enum, string name, string variable)
    {
        template branches (string name, string variable, alias member, Members...)
        {
            enum branch = "if("~variable~"=="~member.to!string~`)printf("\t`~name~`: `~member.to!string~`\n");`;
            static if (Members.length > 0)
            {
                enum branches = branch ~ "else " ~ branches!(name, variable, Members);
            }
            else
            {
                enum branches = branch;
            }
        }
        enum printfEnum = branches!(name, variable, EnumMembers!Enum);
    }
    try
    {
        printf ("Vulkan Log:\n");
        mixin (printfEnum!(VkDebugReportFlagBitsEXT, "Flags", flags.stringof));
        mixin (printfEnum!(VkDebugReportObjectTypeEXT, "Object Type", objectType.stringof));
        printf ("\tObject: %d\n", object);
        printf ("\tLocation: %d\n", location);
        printf ("\tMessage Code: %d\n", messageCode);
        printf ("\tLayer Prefix: %s\n", pLayerPrefix);
        printf ("\tMessage: %s\n", pMessage);
        printf ("\n");
    }
    catch (Throwable)
    {
    }
    return VK_FALSE;
}

/// Contains creation information and enumerated properties of the current instance. Most of the data is only useful
/// for debugging purposes.
private struct Info
{
    Array!VkExtensionProperties         instanceExtProperties;      /// The details of what extensions are available to the instance.
    Array!VkLayerProperties             layerProperties;            /// The details of what layers are available to the instance.
    Array!VkPhysicalDevice              physicalDevices;            /// The available physical devices.
    Array!VkPhysicalDeviceProperties    physicalDeviceProperties;   /// The description and capabilities of each device.
    Array!(Array!VkExtensionProperties) deviceExtProperties;        /// A collection of extension properties for every device.

    /// Contains application-specific information required to create a Vulkan instance, hard-coded for now.
    VkApplicationInfo app = 
    {
        sType:              VK_STRUCTURE_TYPE_APPLICATION_INFO,
        pNext:              null,
        pApplicationName:   "Denjin-dev", 
        applicationVersion: VK_MAKE_VERSION (0,0,1),
        pEngineName:        "Denjin", 
        engineVersion:      VK_MAKE_VERSION (0,0,1),
        apiVersion:         VK_MAKE_VERSION (1,0,0)
    };

    /// Constains instance creation information.
    VkInstanceCreateInfo instance =
    {
        sType:                      VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        pNext:                      null,
        flags:                      0,
        pApplicationInfo:           null,
        enabledLayerCount:          0,
        ppEnabledLayerNames:        null,
        enabledExtensionCount:      0,
        ppEnabledExtensionNames:    null
    };

    /// Contains information required to create a logical device.
    VkDeviceCreateInfo device = 
    {
        sType:                      VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        pNext:                      null,
        flags:                      0,
        queueCreateInfoCount:       0,
        pQueueCreateInfos:          null,
        enabledLayerCount:          0,
        ppEnabledLayerNames:        null,
        enabledExtensionCount:      0,
        ppEnabledExtensionNames:    null,
        pEnabledFeatures:           null
    };

    /// Contains information regarding the creation of a debug callback.
    debug VkDebugReportCallbackCreateInfoEXT debugCallback = 
    {
        sType: VK_STRUCTURE_TYPE_DEBUG_REPORT_CALLBACK_CREATE_INFO_EXT,
        pNext: null,
        flags: 0,
        pfnCallback: null,
        pUserData: null
    };
    
    /// Enable debug reporting in debug modes.
    template requiredInstanceExtensions()
    {
        debug
        {
            enum requiredInstanceExtensions = AliasSeq!("VK_EXT_debug_report");
        }
        else
        {
            enum requiredInstanceExtensions = AliasSeq!("");
        }
    }

    /// Swapchains are required at all times.
    template requiredDeviceExtensions()
    {
        enum requiredDeviceExtensions = AliasSeq!("VK_KHR_swapchain");
    }
    
    /// Use heavy validation in debug, core validation in optimized and nothing in release.
    template requiredLayers()
    {
        version (optimized)
        {
            // Use only core validation layers for speed.
            static enum requiredLayers = AliasSeq!("VK_LAYER_LUNARG_core_validation");
        }
        else version (assert)
        {        static enum requiredDeviceExtensions = AliasSeq!("VK_KHR_swapchain");

            // Standard validation enables threading, parameter, object, core, swapchain and unique object validation.
            static enum requiredLayers = AliasSeq!("VK_LAYER_LUNARG_standard_validation");
        }
        else
        {
            // Don't perform any validation in release mode.
            static enum requiredLayers = AliasSeq!("");
        }
    }

    nothrow
    void clear()
    {
        instanceExtProperties.clear();
        layerProperties.clear();
        physicalDevices.clear();
        physicalDeviceProperties.clear();
        deviceExtProperties.clear();
    }
}
