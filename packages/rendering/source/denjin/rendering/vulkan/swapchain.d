/**
    Manages a swapchain for displaying images using Vulkan.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: MIT
*/
module denjin.rendering.vulkan.swapchain;

// Phobos.
import std.algorithm.comparison : clamp;
import std.algorithm.searching  : canFind, find;
import std.container.array      : Array;
import std.exception            : enforce;

// Engine.
import denjin.rendering.vulkan.device   : Device;
import denjin.rendering.vulkan.misc     : enforceSuccess, nullHandle;

// External.
import erupted.functions    : vkGetPhysicalDeviceSurfaceCapabilitiesKHR, vkGetPhysicalDeviceSurfaceFormatsKHR, vkGetPhysicalDeviceSurfacePresentModesKHR;
import erupted.types        : uint32_t, VkAllocationCallbacks, VkColorSpaceKHR, VkDevice, VkFormat, VkPhysicalDevice, 
                              VkPresentModeKHR, VkSurfaceKHR, VkSurfaceCapabilitiesKHR, VkSurfaceFormatKHR, 
                              VkSwapchainKHR, VkSwapchainCreateInfoKHR, VK_COLOR_SPACE_SRGB_NONLINEAR_KHR, 
                              VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR, VK_FORMAT_UNDEFINED, VK_FORMAT_R8G8B8A8_UNORM, 
                              VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT, VK_SHARING_MODE_EXCLUSIVE, 
                              VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR, VK_TRUE;

/// Facilitates the creation, management and destruction of Vulkan swapchains, these control what is displayed to the
/// user, and how. Note: Swapchains cannot destroy themselves, they must be destroyed externally by a device.
struct Swapchain
{
    private
    {
        alias SurfaceFormats    = Array!VkSurfaceFormatKHR;
        alias PresentModes      = Array!VkPresentModeKHR;

        VkSwapchainKHR      m_swapchain = nullHandle!VkSwapchainKHR;    /// The handle of the created swapchain.
        VkSurfaceKHR        m_surface   = nullHandle!VkSurfaceKHR;      /// The handle to the surface which will display images.
        VkPhysicalDevice    m_gpu       = nullHandle!VkPhysicalDevice;  /// The handle of the GPU interfacing with the presentation engine.

        VkSurfaceCapabilitiesKHR    m_capabilities; /// The capabilities of the physical device + surface combination.
        SurfaceFormats              m_formats;      /// Available colour formats for the current surface.
        PresentModes                m_modes;        /// Single, double, triple buffering capabilities.
    }

    // Subtype VkSwapchainKHR to allow for implicit usage.
    alias swapchain this;

    /// Retrieve the capabilities of the given device/surface combination to allow for the creation of a swapchain.
    public this (VkPhysicalDevice physicalDevice, VkSurfaceKHR surface)
    {
        // Pre-conditions.
        enforce (physicalDevice != nullHandle!VkPhysicalDevice);
        enforce (surface != nullHandle!VkSurfaceKHR);
        m_surface   = surface;
        m_gpu       = physicalDevice;
        
        // Avoid run-time allocation by retrieving the support formats and presentation modes now.
        uint32_t count = void;
        vkGetPhysicalDeviceSurfaceFormatsKHR (m_gpu, m_surface, &count, null).enforceSuccess;

        m_formats.length = count;
        vkGetPhysicalDeviceSurfaceFormatsKHR (m_gpu, m_surface, &count, &m_formats.front()).enforceSuccess;

        // These function names just keep getting longer!
        vkGetPhysicalDeviceSurfacePresentModesKHR (m_gpu, m_surface, &count, null).enforceSuccess;

        m_modes.length = count;
        vkGetPhysicalDeviceSurfacePresentModesKHR (m_gpu, m_surface, &count, &m_modes.front()).enforceSuccess;
    }

    /// Destroys the currently managed swapchain. This will leave the object in an unusable/unitialised state and 
    /// should not be used any further.
    /// Params:
    ///     device      = The logical device used to create the swapchain in the first place.
    ///     callbacks   = Any allocation callbacks used to initialise the swapchain with.
    public void clear (ref Device device, in VkAllocationCallbacks* callbacks = null) nothrow
    in
    {
        assert (device != nullHandle!VkDevice);
    }
    body
    {
        if (m_swapchain != nullHandle!VkSwapchainKHR)
        {
            device.vkDestroySwapchainKHR (m_swapchain, callbacks);
            m_swapchain = nullHandle!VkSwapchainKHR;
        }

        m_surface       = nullHandle!VkSurfaceKHR;
        m_gpu           = nullHandle!VkPhysicalDevice;
        m_capabilities  = m_capabilities.init;
        m_formats.clear();
        m_modes.clear();
    }
    /// Gets the handle to the managed swapchain.
    public @property inout (VkSwapchainKHR) swapchain() inout pure nothrow @safe @nogc { return m_swapchain; }

    /// Initially creates the swapchain with the given display mode. Calling this not recreate the swapchain properly,
    /// use recreate() for that.
    public void create (ref Device device, in VSync desiredMode = VSync.TripleBuffering, 
                        in VkAllocationCallbacks* callbacks = null)
    in
    {
        assert (device != nullHandle!VkDevice);
    }
    body
    {
        // Firstly ensure we know the capabilities of the surface.
        vkGetPhysicalDeviceSurfaceCapabilitiesKHR (m_gpu, m_surface, &m_capabilities).enforceSuccess;

        // Compile the creation information.
        VkSwapchainCreateInfoKHR info = 
        {
            sType:                  VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
            pNext:                  null,
            flags:                  0,
            surface:                m_surface,
            imageExtent:            m_capabilities.currentExtent,
            imageArrayLayers:       1,
            imageUsage:             VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
            imageSharingMode:       VK_SHARING_MODE_EXCLUSIVE,
            queueFamilyIndexCount:  0,
            pQueueFamilyIndices:    null,
            preTransform:           m_capabilities.currentTransform,
            compositeAlpha:         VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
            clipped:                VK_TRUE,
            oldSwapchain:           m_swapchain
        };

        setPresentMode (info.minImageCount, info.presentMode, desiredMode);
        setFormat (info.imageFormat, info.imageColorSpace);

        // Create the swapchain and destroy the old one!
        device.vkCreateSwapchainKHR (&info, callbacks, &m_swapchain).enforceSuccess;
        
        if (info.oldSwapchain != nullHandle!VkSwapchainKHR)
        {
            device.vkDestroySwapchainKHR (info.oldSwapchain, callbacks);
        }
    }

    /// Recreates the swapchain by discarding any stored images, discarding the current swapchain and creating a new
    /// one.
    public void recreate (ref Device device, in VSync desiredMode = VSync.TripleBuffering, 
                          in VkAllocationCallbacks* callbacks = null)
    {
        
    }

    /// Attempts to set the image count and presentation mode to be the same as the desired VSync mode. If the device
    /// supports the feature then it will be configured, otherwise the closest approximation will be chosen.
    private void setPresentMode (ref uint32_t minImageCount, ref VkPresentModeKHR presentMode, in VSync desiredMode) const
    {
        const auto vsyncMode    = cast (VkPresentModeKHR) desiredMode;
        const auto imageCount   = desiredMode.requiredBuffers;
        if (!m_modes[0..$].canFind!()(vsyncMode) || m_capabilities.maxImageCount < imageCount)
        {
            setPresentMode (minImageCount, presentMode, desiredMode.fallback);
        }
        else
        {
            presentMode     = vsyncMode;
            minImageCount   = imageCount.clamp (m_capabilities.minImageCount, m_capabilities.maxImageCount);
        }
    }

    /// Sets the given format variables to the most appropriate values.
    private void setFormat (ref VkFormat imageFormat, ref VkColorSpaceKHR imageColorSpace) const
    {
        // There may be no preferred format.
        if (m_formats.length == 1 && m_formats.front().format == VK_FORMAT_UNDEFINED)
        {
            imageFormat     = VK_FORMAT_R8G8B8A8_UNORM;
            imageColorSpace = VK_COLOR_SPACE_SRGB_NONLINEAR_KHR;
        }
        else
        {
            // Attempt to use the common 8bpc RGBA format if possible.
            const auto result = find!"a.format == b"(m_formats[0..$], VK_FORMAT_R8G8B8A8_UNORM);
            if (result.empty)
            {
                imageFormat     = m_formats.front.format;
                imageColorSpace = m_formats.front.colorSpace;
            }
            else
            {
                imageFormat     = result.front.format;
                imageColorSpace = result.front.colorSpace;
            }
        }
    }
}

/// Determines how the present mode will function. Triple buffering will use the most memory.
enum VSync : VkPresentModeKHR
{
    Off             = VkPresentModeKHR.VK_PRESENT_MODE_IMMEDIATE_KHR,
    On              = VkPresentModeKHR.VK_PRESENT_MODE_FIFO_KHR,
    Relaxed         = VkPresentModeKHR.VK_PRESENT_MODE_FIFO_RELAXED_KHR,
    TripleBuffering = VkPresentModeKHR.VK_PRESENT_MODE_MAILBOX_KHR
}

/// Gets the number of buffers required for the given VSync mode.
pure nothrow @safe @nogc
uint32_t requiredBuffers (in VSync mode)
{
    switch (mode)
    {
        case VSync.Off:
        case VSync.On:
        case VSync.Relaxed:
            return 2;
        case VSync.TripleBuffering:
            return 3;
        default:
            assert (false, "Someone forgot a case!");
    }
}

/// Gets the mode which should be used as a fallback if the given mode isn't supported.
pure nothrow @safe @nogc
VSync fallback (in VSync mode)
{
    switch (mode)
    {
        case VSync.TripleBuffering:
            return VSync.Relaxed;
        case VSync.Relaxed:
            return VSync.On;
        case VSync.On:
            return VSync.Off;
        default:
            assert (false, "VSync.Off should always be supported!");
    }
}