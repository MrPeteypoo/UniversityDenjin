/**
    Contains functionality required to load Vulkan functions and create instances/devices for use by the Vulkan API.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: MIT
*/
module denjin.rendering.vulkan.loader;

// Phobos.
import core.stdc.string         : strcmp;
import std.container.array      : Array;
import std.container.util       : make;
import std.conv                 : to;
import std.exception            : enforce;
import std.meta                 : AliasSeq, aliasSeqOf;
import std.range                : repeat, takeExactly;
import std.stdio                : writeln;
import std.string               : fromStringz, toStringz;

// Engine.
import denjin.rendering.vulkan.misc     : enforceSuccess, extensionOrLayerExists, nullHandle, safelyDestroyVK;
import denjin.rendering.vulkan.device   : VulkanDevice;

// External.
import erupted;

// Debug.
debug import denjin.rendering.vulkan.logging : logExtensionProperties, logLayerProperties, logPhysicalDeviceProperties, 
                                               logQueueFamilyProperties;

/// A basic structure, allowing for the creation and management of Vulkan instances and devices.
struct VulkanLoader
{
    private:

        // Gotta use selective importing to access a required private struct of erupted, I've reported it as an issue.
        import erupted.functions : DispatchDevice;

        alias Extensions        = Array!(const(char)*);
        alias Layers            = Array!(const(char)*);
        alias DebugCallback     = VkDebugReportCallbackEXT;

        VulkanDevice    m_device;       /// Contains the handle and device-level functions of the current device.
        size_t          m_gpuIndex;     /// The index of the selected physical device.
        Extensions      m_instanceExts; /// The extensions enabled for the instance.
        Extensions      m_deviceExts;   /// The extensions enabled for the device.
        Layers          m_layers;       /// The layers enabled for the instance.
        VulkanInfo      m_info;         /// Contains descriptive information regarding how the Vulkan instance is configured.

        VkInstance          m_instance      = nullHandle!VkInstance;        /// A handle to a created vulkan instance.
        VkSurfaceKHR        m_surface       = nullHandle!VkSurfaceKHR;      /// A handle to a renderable surface.
        VkPhysicalDevice    m_gpu           = nullHandle!VkPhysicalDevice;  /// A handle to the chosen physical device.
        debug DebugCallback m_debugCallback = nullHandle!DebugCallback;     /// A handle to a debug reporting object.

    public:

        alias InstanceProcAddress = typeof (vkGetInstanceProcAddr);

        /// Destroys any stored instances/devices.
        nothrow @nogc
        ~this()
        {
            clear();
        }

        /// Destroys stored instances, devices, surfaces, etc.
        nothrow @nogc
        clear()
        {
            m_layers.clear();
            m_device.clear();

            // The instance must be destroyed last.
            debug m_debugCallback.safelyDestroyVK (vkDestroyDebugReportCallbackEXT, m_instance, m_debugCallback, null);
            m_surface.safelyDestroyVK (vkDestroySurfaceKHR, m_instance, m_surface, null);
            m_instance.safelyDestroyVK (vkDestroyInstance, m_instance, null);
        }

        /// Creates instances, devices and queues which can be used by a Vulkan-based renderer.
        /// Params:
        ///     proc            = The pointer to a function used to load global-level Vulkan functions.
        ///     extensionCount  = How many extensions will be loaded.
        ///     extensions      = A collection extension names to be loaded.
        void load (in InstanceProcAddress proc, in uint32_t extensionCount, in char** extensions)
        {
            // Pre-conditions.
            enforce (proc != null);
            enforce (extensionCount > 0 || extensions == null);

            // First we must ensure that global-level Vulkan functions are loaded.
            loadGlobalLevelFunctions (proc);

            clear();
            createInstance (extensionCount, extensions);
            createDevice();
        }

        /// Gets a const-representation of the loaded instance.
        @property pure nothrow @safe @nogc
        ref const(VkInstance) instance() const { return m_instance; };

        /// Gets a modifiable representation of the loaded instance.
        @property pure nothrow @safe @nogc
        ref VkInstance instance() { return m_instance; };

        /// Gets a const-representation of the renderable surface.
        @property pure nothrow @safe @nogc
        ref const(VkSurfaceKHR) surface() const { return m_surface; }

        /// Gets a modifiable representation of the renderable surface.
        @property pure nothrow @safe @nogc
        ref VkSurfaceKHR surface() { return m_surface; }

        /// Sets the ID of the renderable surface.
        @property pure nothrow @safe @nogc
        void surface (VkSurfaceKHR surface) { m_surface = surface; }

    private:

        /// Performs the first stage of Vulkan loading, retrieving global-level Vulkan functions and creating an 
        /// instance.
        void createInstance (in uint32_t extensionCount, in char** extensions)
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
            debug createDebugCallback;
        }

        /// Performs the second stage of Vulkan loading, retrieving instance-level Vulkan functions and checking the 
        /// available devices, creating a logical device for use with rendering.
        void createDevice()
        {
            // Now we can check the hardware on the machine, for now we'll just use the first device.
            m_gpuIndex  = enumerateDevices();
            m_gpu       = m_info.physicalDevices[m_gpuIndex];

            // Next we need to obtain information about the available queues.
            const auto  queueFamilyIndex    = enumerateQueueFamilies();
            auto        queuePriorities     = new float[m_info.queueFamilyProperties[queueFamilyIndex].queueCount];
            queuePriorities[] = 1f;

            m_info.queue.queueFamilyIndex               = cast (uint32_t) queueFamilyIndex;
            m_info.queue.queueCount                     = cast (uint32_t) queuePriorities.length;
            m_info.queue.pQueuePriorities               = queuePriorities.ptr;
            m_info.device.pQueueCreateInfos             = &m_info.queue;
            m_info.device.enabledExtensionCount         = cast (uint32_t) m_deviceExts.length;
            m_info.device.ppEnabledExtensionNames       = &m_deviceExts.front();
            scope (exit) m_info.queue.pQueuePriorities  = null;

            // Finally create the logical device.
            m_device.create (m_gpu, m_info.device, null);
            printExtensionsAndLayers;
        }

        /// Checks the extensions available to the instance and attempts to load any necessary for rendering.
        void enumerateInstanceExtensions (in uint32_t externalExtCount, in char** externalExt)
        {
            // Retrieve the number of extensions available.
            uint32_t count = void;
            vkEnumerateInstanceExtensionProperties (null, &count, null).enforceSuccess;

            // Now retrieve them.
            m_info.instanceExtProperties.length = count;
            vkEnumerateInstanceExtensionProperties (null, &count, &m_info.instanceExtProperties.front()).enforceSuccess;
            debug logExtensionProperties ("Instance", m_info.instanceExtProperties);

            // Reserve memory to speed up the process.
            enum requiredExtensions = VulkanInfo.requiredInstanceExtensions!();
            m_instanceExts.reserve (requiredExtensions.length + externalExtCount);

            // First check the externally required extensions exist.
            foreach (i; 0..externalExtCount)
            {
                auto name = externalExt[i];
                enforce (extensionOrLayerExists (name, m_info.instanceExtProperties), 
                         "Required Vulkan extension is not supported: " ~ name.fromStringz);

                // We need to duplicate the string to ensure ownership.
                m_instanceExts.insertBack (name.fromStringz.toStringz);
            }

            // Now check internally required extensions. None may be required.
            static if (requiredExtensions.length > 0 && requiredExtensions[0] != "")
            {
                bool alreadyAdded (const(char)* name)
                {
                    foreach (added; m_instanceExts) { if (name.strcmp (added) == 0) return true; }
                    return false;
                }
                foreach (name; requiredExtensions)
                {
                    auto cName = name.toStringz;
                    enforce (extensionOrLayerExists (cName, m_info.instanceExtProperties), 
                             "Required Vulkan extension is not supported: " ~ name);

                    if (!alreadyAdded (cName))
                    {
                        m_instanceExts.insertBack (cName);
                    }
                }
            }
        }

        /// Checks the layers available to the instance and attempts to load any necessary debug layers.
        void enumerateLayers()
        {
            // First we must retrieve the number of layers.
            uint32_t count = void;
            vkEnumerateInstanceLayerProperties (&count, null).enforceSuccess;

            // Now we can retrieve them.
            m_info.layerProperties.length = count;
            vkEnumerateInstanceLayerProperties (&count, &m_info.layerProperties.front()).enforceSuccess;
            debug logLayerProperties (m_info.layerProperties);
            
            // Next we must check for layers required by the loader based on the debug level. Also compile-time foreach ftw!
            enum requiredLayers = VulkanInfo.requiredLayers!();
            
            // Handle the case where no layers are to be loaded.
            static if (requiredLayers.length > 0 && requiredLayers[0] != "")
            {
                m_layers.reserve (requiredLayers.length);
                foreach (name; requiredLayers)
                {
                    // Ensure the layer is accessible.
                    auto cName = name.toStringz;
                    enforce (extensionOrLayerExists (cName, m_info.layerProperties), 
                             "Required Vulkan layer is not supported: " ~ name);

                    // The C-string can be added to the collection of names.
                    m_layers.insertBack (cName);
                }
            }
        }

        /// Retrieves the number of available devices and their associated properties.
        /// Returns: The index of the device that features the required capabilities.
        size_t enumerateDevices()
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
            enum requiredExtensions = VulkanInfo.requiredDeviceExtensions!();
            m_deviceExts.reserve (requiredExtensions.length);
            foreach (ext; requiredExtensions)
            {
                enforce (extensionOrLayerExists (ext, m_info.deviceExtProperties.front));
                m_deviceExts.insertBack (ext.toStringz);
            }

            return 0;
        }

        /// Populates the queue family properties
        /// Returns: The index of the most appropriate family to use for rendering.
        size_t enumerateQueueFamilies()
        {
            // Retrieve the queue family properties.
            uint32_t count = void;
            vkGetPhysicalDeviceQueueFamilyProperties (m_gpu, &count, null);
            
            m_info.queueFamilyProperties.length = count;
            vkGetPhysicalDeviceQueueFamilyProperties (m_gpu, &count, &m_info.queueFamilyProperties.front());
            debug logQueueFamilyProperties (m_info.queueFamilyProperties);

            foreach (i; 0..m_info.queueFamilyProperties.length)
            {
                if ((m_info.queueFamilyProperties[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) > 0)
                {
                    return i;
                }
            }

            assert (false, "Vulkan loader was unable to find an appropriate queue family to use.");
        }

        /// Prints the validation layer and extension names in use by the current instance.
        void printExtensionsAndLayers() const
        {
            foreach (i; 0..m_info.instance.enabledExtensionCount)
            {
                writeln ("Vulkan instance extension activated: ", m_info.instance.ppEnabledExtensionNames[i].fromStringz);
            }
            foreach (i; 0..m_info.instance.enabledLayerCount)
            {
                writeln ("Vulkan instance layer activated: ", m_info.instance.ppEnabledLayerNames[i].fromStringz);
            }
            foreach (i; 0..m_info.device.enabledExtensionCount)
            {
                writeln ("Vulkan instance extension activated: ", m_info.device.ppEnabledExtensionNames[i].fromStringz);
            }
            writeln;
        }

    debug private
    {
        /// Creates the debug callback object which will different debugging information.
        void createDebugCallback()
        in
        {
            assert (m_instance != nullHandle!VkInstance);
            //assert (vkCreateDebugReportCallbackEXT);
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
}

debug private extern (System) nothrow @nogc
VkBool32 logVulkanError (VkDebugReportFlagsEXT flags, VkDebugReportObjectTypeEXT objectType, uint64_t object, 
                         size_t location, int32_t messageCode, const(char)* pLayerPrefix, const(char)* pMessage, 
                         void* pUserData)
{
    import core.stdc.stdio  : printf;
    import std.traits       : EnumMembers;

    // This is unnecessarily templatey because of the unnecessary @nogc requirement. It also has to use if statements
    // because enums can contain duplicate numeric values. Slow but it is a debugging function after all.
    template printfEnum (Enum, string name, string variable)
    {
        // Gotta avoid duplicates by tracking how far down we are.
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
struct VulkanInfo
{
    Array!VkExtensionProperties         instanceExtProperties;      /// The details of what extensions are available to the instance.
    Array!VkLayerProperties             layerProperties;            /// The details of what layers are available to the instance.
    Array!VkPhysicalDevice              physicalDevices;            /// The available physical devices.
    Array!VkPhysicalDeviceProperties    physicalDeviceProperties;   /// The description and capabilities of each device.
    Array!(Array!VkExtensionProperties) deviceExtProperties;        /// A collection of extension properties for every device.
    Array!VkQueueFamilyProperties       queueFamilyProperties;      /// The capabilities of each available queue family.

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

    /// Contains information required to create queues for a logical device.
    VkDeviceQueueCreateInfo queue = 
    {
        sType:              VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        pNext:              null,
        flags:              0,
        queueFamilyIndex:   0,
        queueCount:         1,
        pQueuePriorities:   null
    };

    /// Contains information required to create a logical device.
    VkDeviceCreateInfo device = 
    {
        sType:                      VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        pNext:                      null,
        flags:                      0,
        queueCreateInfoCount:       1,
        pQueueCreateInfos:          null,
        enabledLayerCount:          0,
        ppEnabledLayerNames:        null,
        enabledExtensionCount:      0,
        ppEnabledExtensionNames:    null,
        pEnabledFeatures:           null
    };

    /// Contains information regarding the creation of a debug callback.
    VkDebugReportCallbackCreateInfoEXT debugCallback = 
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
}
