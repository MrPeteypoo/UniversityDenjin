/**
    Contains functionality required to load Vulkan functions and create instances/devices for use by the Vulkan API.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: MIT
*/
module denjin.rendering.vulkan.loader;

// Phobos.
import std.container.array      : Array;
import std.container.util       : make;
import std.exception            : enforce;
import std.meta                 : AliasSeq, aliasSeqOf;
import std.stdio                : writeln;
import std.string               : fromStringz, toStringz;

// Engine.
import denjin.rendering.vulkan.misc : enforceSuccess, layerExists, nullHandle, safelyDestroyVK;

// External.
import erupted;

/// A basic structure, allowing for the creation and management of Vulkan instances and devices.
struct VulkanLoader
{
    private:

        alias Layers = Array!(const(char)*);

        VkInstance      m_instance  = nullHandle!VkInstance;    /// A handle to a created vulkan instance.
        VkSurfaceKHR    m_surface   = nullHandle!VkSurfaceKHR;  /// A handle to a renderable surface.
        Layers          m_layers;                               /// The layers enabled for the instance.
        VulkanInfo      m_info;                                 /// Contains descriptive information regarding how the Vulkan instance is configured.

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
            // Ensure the Vulkan objects are destroyed in the correct order.
            m_surface.safelyDestroyVK (vkDestroySurfaceKHR, m_instance, m_surface, null);
            m_instance.safelyDestroyVK (vkDestroyInstance, m_instance, null);

            // The GC will take care of deleting the C-strings.
            m_layers.clear();
        }

        /// Creates instances, devices and queues which can be used by a Vulkan-based renderer.
        /// Params:
        ///     proc            = The pointer to a function used to load global-level Vulkan functions.
        ///     extensionCount  = How many extensions will be loaded.
        ///     extensions      = A collection extension IDs to be loaded.
        void load (in InstanceProcAddress proc, in uint32_t extensionCount, in char** extensions)
        {
            // Pre-conditions.
            enforce (proc != null);
            enforce (extensionCount > 0 || extensions == null);

            clear();
            createInstance (proc, extensionCount, extensions);
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
        void createInstance (in InstanceProcAddress proc, in uint32_t extensionCount, in char** extensions)
        {
            // First we must ensure that global-level Vulkan functions are loaded.
            loadGlobalLevelFunctions (proc);

            // Second we must describe how the instance should be created.
            enumerateLayers();
            const auto layerCount = cast (uint32_t) m_layers.length;
            const auto layerNames = layerCount == 0 ? null : &m_layers.front();

            m_info.instance.pApplicationInfo        = &m_info.app;
            m_info.instance.enabledLayerCount       = layerCount;
            m_info.instance.ppEnabledLayerNames     = layerNames;
            m_info.instance.enabledExtensionCount   = extensionCount;
            m_info.instance.ppEnabledExtensionNames = extensions;

            vkCreateInstance (&m_info.instance, null, &m_instance).enforceSuccess;
            printLayersAndExtensions;
        }

        /// Performs the second stage of Vulkan loading, retrieving instance-level Vulkan functions and checking the 
        /// available devices, creating a logical device for use with rendering.
        void createDevice()
        {
            // Ensure we load the function pointers required to create a device.
            loadInstanceLevelFunctions (m_instance);
            
            // Now we can check the hardware on the machine, for now we'll just use the first device.
            enumerateDevices();

        }

        /// Checks the layers available to the instance and attempts to load any necessary debug layers.
        /// Returns: A pair containing the number of layers and an array of C-strings representing layer names.
        void enumerateLayers()
        {
            debug import denjin.rendering.vulkan.logging : logLayerProperties;

            // First we must retrieve the number of layers.
            uint32_t count = void;
            vkEnumerateInstanceLayerProperties (&count, null).enforceSuccess;

            // Now we can retrieve them.
            m_info.layerProperties.length = count;
            vkEnumerateInstanceLayerProperties (&count, &m_info.layerProperties.front()).enforceSuccess;
            debug logLayerProperties (m_info.layerProperties);
            
            // Next we must check for layers required by the loader based on the debug level. Also compile-time foreach ftw!
            enum requiredLayers = VulkanInfo.requiredLayers;
            
            // Handle the case where no layers are to be loaded.
            static if (requiredLayers.length > 0 && requiredLayers[0] != "")
            {
                m_layers.reserve (requiredLayers.length);
                foreach (name; requiredLayers)
                {
                    // Ensure the layer is accessible.
                    auto cName = name.toStringz;
                    enforce (layerExists (cName, m_info.layerProperties), "Required Vulkan layer is not supported: " ~ name);

                    // The C-string can be added to the collection of names.
                    m_layers.insertBack (cName);
                }
            }
        }

        void enumerateDevices()
        {
            debug import denjin.rendering.vulkan.logging : logPhysicalDeviceProperties;

            // Get the number of devices.
            uint32_t count = void;
            vkEnumeratePhysicalDevices (m_instance, &count, null).enforceSuccess;

            // Retrieve the handles and properties of each device.
            m_info.physicalDevices.length           = count;
            m_info.physicalDeviceProperties.length  = count;
            vkEnumeratePhysicalDevices (m_instance, &count, &m_info.physicalDevices.front()).enforceSuccess;

            foreach (i; 0..count)
            {
                vkGetPhysicalDeviceProperties (m_info.physicalDevices[i], &m_info.physicalDeviceProperties[i]);
            }
            
            debug logPhysicalDeviceProperties (m_info.physicalDeviceProperties);
        }

        /// Prints the validation layer and extension names in use by the current instance.
        void printLayersAndExtensions() const
        {
            foreach (i; 0..m_info.instance.enabledLayerCount)
            {
                writeln ("Vulkan instance layer activated: ", m_info.instance.ppEnabledLayerNames[i].fromStringz);
            }
            foreach (i; 0..m_info.instance.enabledExtensionCount)
            {
                writeln ("Vulkan instance extension activated: ", m_info.instance.ppEnabledExtensionNames[i].fromStringz);
            }
            writeln;
        }
}


struct VulkanInfo
{
    /// Contains application-specific information required to create a Vulkan instance, hard-coded for now.
    VkApplicationInfo app = 
    {
        sType:              VK_STRUCTURE_TYPE_APPLICATION_INFO,
        pNext:              VK_NULL_HANDLE,
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
        pNext:                      VK_NULL_HANDLE,
        flags:                      0,
        pApplicationInfo:           VK_NULL_HANDLE,
        enabledLayerCount:          0,
        ppEnabledLayerNames:        VK_NULL_HANDLE,
        enabledExtensionCount:      0,
        ppEnabledExtensionNames:    VK_NULL_HANDLE
    };

    Array!VkLayerProperties             layerProperties;            /// The details of what layers are available to the instance.
    Array!VkPhysicalDevice              physicalDevices;            /// The available physical devices.
    Array!VkPhysicalDeviceProperties    physicalDeviceProperties;   /// The description and capabilities of each device.
    VkPhysicalDevice                    physicalDevice;             /// The chosen physical device.
    VkPhysicalDeviceProperties*         deviceProps;                /// The
    
    version (optimized)
    {
        // Use only core validation layers for speed.
        static enum requiredLayers = AliasSeq!("VK_LAYER_LUNARG_core_validation");
    }
    else version (assert)
    {
        // Standard validation enables threading, parameter, object, core, swapchain and unique object validation.
        static enum requiredLayers = AliasSeq!("VK_LAYER_LUNARG_standard_validation");
    }
    else
    {
        // Don't perform any validation in release mode.
        static enum requiredLayers = AliasSeq!("");
    }
}
