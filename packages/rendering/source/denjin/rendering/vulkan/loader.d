/**
    Contains functionality required to load Vulkan functions and create instances/devices for use by the Vulkan API.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: MIT
*/
module denjin.rendering.vulkan.loader;

// Phobos.
import std.exception    : enforce;
import std.typecons     : Unique;

// Engine.
import denjin.rendering.vulkan.misc : enforceSuccess, nullHandle, safelyDestroyVK;

// External.
import erupted;

/// A basic structure, allowing for the creation and management of Vulkan instances and devices.
struct VulkanLoader
{
    private:

        VkInstance      m_instance  = nullHandle!VkInstance;    /// A handle to a created vulkan instance.
        VkSurfaceKHR    m_surface   = nullHandle!VkSurfaceKHR;  /// A handle to a renderable surface.
        VulkanInfo      m_info;                                 /// Contains descriptive information regarding how the Vulkan instance is configured.

    public:

        alias InstanceProcAddress = typeof (vkGetInstanceProcAddr);

        /// Destroys any stored instances/devices.
        nothrow @nogc
        ~this()
        {
            clean();
        }

        /// Destroys stored instances, devices, surfaces, etc.
        nothrow @nogc
        clean()
        {
            m_instance.safelyDestroyVK (vkDestroyInstance, m_instance, null);
            m_surface.safelyDestroyVK (vkDestroySurfaceKHR, m_instance, m_surface, null);
        }

        /// Creates instances, devices and queues which can be used by a Vulkan-based renderer.
        /// Params:
        ///     proc            = The pointer to a function used to load global-level Vulkan functions.
        ///     extensionCount  = How many extensions will be loaded.
        ///     extensions      = A collection extension IDs to be loaded.
        void load (in InstanceProcAddress proc, in uint32_t extensionCount, in char** extensions)
        in
        {
            enforce (proc != null);
            enforce (extensionCount > 0 || extensions == null);
        }
        body 
        {
            clean();
            createInstance (proc, extensionCount, extensions);
        }

        /// Gets a const-representation of the loaded instance.
        @property pure nothrow @safe @nogc
        ref const(VkInstance) instance() const { return m_instance; };

        /// Gets a modifiable representation of the loaded instance.
        @property pure nothrow @safe @nogc
        ref VkInstance instance() { return m_instance; };

        /// Gets a const-representation of the renderable surface.
        @property pure nothrow @safe @nogc
        VkSurfaceKHR surface() const { return m_surface; }

        /// Gets a modifiable representation of the renderable surface.
        @property pure nothrow @safe @nogc
        ref VkSurfaceKHR surface() { return m_surface; }

        /// Sets the ID of the renderable surface.
        @property pure nothrow @safe @nogc
        void surface (VkSurfaceKHR surface) { m_surface = surface; }

    private:

        /// Performs the first stage of vulkan loading, retrieving global-level Vulkan functions and creating an 
        /// instance.
        void createInstance (in InstanceProcAddress proc, in uint32_t extensionCount, in char** extensions)
        {
            // First we must ensure that global-level Vulkan functions are loaded.
            loadGlobalLevelFunctions (proc);

            // Second we must describe how the instance should be created.
            m_info.instance.pApplicationInfo        = &m_info.app;
            m_info.instance.enabledExtensionCount   = extensionCount;
            m_info.instance.ppEnabledExtensionNames = extensions;

            vkCreateInstance (&m_info.instance, null, &m_instance).enforceSuccess;
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
}