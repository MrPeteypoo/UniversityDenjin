/**
    Manages a swapchain for displaying images using Vulkan.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: MIT
*/
module denjin.rendering.vulkan.swapchain;

// Phobos.
import std.algorithm.comparison : clamp;
import std.algorithm.iteration  : each;
import std.algorithm.searching  : canFind, find;
import std.container.array      : Array;
import std.exception            : enforce;

// Engine.
import denjin.rendering.vulkan.device   : Device;
import denjin.rendering.vulkan.misc     : enforceSuccess, safelyDestroyVK;
import denjin.rendering.vulkan.nulls;
import denjin.rendering.vulkan.objects  : createSemaphore;

// External.
import erupted.functions : vkGetPhysicalDeviceSurfaceCapabilitiesKHR, vkGetPhysicalDeviceSurfaceFormatsKHR, 
                           vkGetPhysicalDeviceSurfacePresentModesKHR;
import erupted.types;

/// Facilitates the creation, management and destruction of Vulkan swapchains, these control what is displayed to the
/// user, and how. Note: Swapchains cannot destroy themselves, they must be destroyed externally by a device.
struct Swapchain
{
    private
    {
        alias Images            = Array!VkImage;
        alias ImageViews        = Array!VkImageView;
        alias SurfaceFormats    = Array!VkSurfaceFormatKHR;
        alias PresentModes      = Array!VkPresentModeKHR;

        // Constantly accessed data.
        VkSwapchainKHR      m_swapchain         = nullSwapchain;    /// The handle of the created swapchain.
        VkSemaphore         m_imageAvailability = nullSemaphore;    /// The handle to the semaphore used to indicate that the current image is available for writing.
        VkImageView         m_currentView       = nullImageView;    /// Contains the handle to the image view of the current swapchain image.
        uint32_t            m_currentImage;                         /// Contains the index of the current swapchain image to use for displaying.
        ImageViews          m_imageViews;                           /// Contains writing image views for each image in the swapchain.

        // Rarely accessed data.
        VkSurfaceKHR                m_surface   = nullSurface;      /// The handle to the surface which will display images.
        VkPhysicalDevice            m_gpu       = nullPhysDevice;   /// The handle of the GPU interfacing with the presentation engine.
        VkSurfaceCapabilitiesKHR    m_capabilities;                 /// The capabilities of the physical device + surface combination.
        SurfaceFormats              m_formats;                      /// Available colour formats for the current surface.
        PresentModes                m_modes;                        /// Single, double, triple buffering capabilities.
        Images                      m_images;                       /// Contains handles to each swapchain image.
    }

    // Subtype VkSwapchainKHR to allow for implicit usage.
    alias swapchain this;

    /// Retrieve the capabilities of the given device/surface combination to allow for the creation of a swapchain.
    public this (VkPhysicalDevice physicalDevice, VkSurfaceKHR surface)
    {
        // Pre-conditions.
        enforce (physicalDevice != nullPhysDevice);
        enforce (surface != nullSurface);
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

    /// Gets the handle to the managed swapchain.
    public @property inout (VkSwapchainKHR) swapchain() inout pure nothrow @safe @nogc { return m_swapchain; }

    /// Creates/recreates the swapchain with the given display mode. This will invalidate handles to current swapchain
    /// images.
    public void create (ref Device device, in VSync desiredMode = VSync.TripleBuffering, 
                        in VkAllocationCallbacks* callbacks = null)
    in
    {
        assert (device != nullDevice);
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
        info.oldSwapchain.safelyDestroyVK (device.vkDestroySwapchainKHR, device, info.oldSwapchain, callbacks);

        // Create the semaphore if necessary.
        if (m_imageAvailability == nullSemaphore)
        {
            m_imageAvailability.createSemaphore (device, callbacks).enforceSuccess;
        }
        
        // Finally retrieve the swapchain images.
        createImageViews (device, info.imageFormat, callbacks);
    }

    /// Destroys the currently managed swapchain. This will leave the object in an unusable/unitialised state and 
    /// should not be used any further.
    /// Params:
    ///     device      = The logical device used to create the swapchain in the first place.
    ///     callbacks   = Any allocation callbacks used to initialise the swapchain with.
    public void clear (ref Device device, in VkAllocationCallbacks* callbacks = null) nothrow
    in
    {
        assert (device != nullDevice);
    }
    body
    {
        m_swapchain.safelyDestroyVK (device.vkDestroySwapchainKHR, device, m_swapchain, callbacks);
        m_imageAvailability.safelyDestroyVK (device.vkDestroySemaphore, device, m_imageAvailability, callbacks);
        m_imageViews.each!(v => v.safelyDestroyVK (device.vkDestroyImageView, device, v, callbacks));
        
        m_currentView   = nullImageView;
        m_surface       = nullSurface;
        m_gpu           = nullPhysDevice;
        m_imageViews.clear();
        m_formats.clear();
        m_modes.clear();
        m_images.clear();
    }

    /// Attempts to set the image count and presentation mode to be the same as the desired VSync mode. If the device
    /// supports the feature then it will be configured, otherwise the closest approximation will be chosen.
    private void setPresentMode (ref uint32_t minImageCount, ref VkPresentModeKHR presentMode, in VSync desiredMode) const
    {
        const auto vsyncMode    = cast (VkPresentModeKHR) desiredMode;
        const auto imageCount   = desiredMode.requiredBuffers;
        if (!m_modes[0..$].canFind (vsyncMode) || m_capabilities.maxImageCount < imageCount)
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

    /// Gets all images associated with the current swapchain and creates image views for each of them.
    private void createImageViews (ref Device device, in VkFormat format, in VkAllocationCallbacks* callbacks)
    {
        // Firstly ensure we don't leak data.
        m_imageViews.each!(v => v.safelyDestroyVK (device.vkDestroyImageView, device, v, callbacks));

        // Firstly retrieve the images for the swapchain.
        uint32_t count = void;
        device.vkGetSwapchainImagesKHR (m_swapchain, &count, null).enforceSuccess;

        m_images.length     = cast (size_t) count;
        m_imageViews.length = m_images.length;
        device.vkGetSwapchainImagesKHR (m_swapchain, &count, &m_images.front()).enforceSuccess;

        // Now create the image views for each image.
        enum VkComponentMapping componentMapping = 
        {
            r: VK_COMPONENT_SWIZZLE_IDENTITY, g: VK_COMPONENT_SWIZZLE_IDENTITY, 
            b: VK_COMPONENT_SWIZZLE_IDENTITY, a: VK_COMPONENT_SWIZZLE_IDENTITY,
        };

        enum VkImageSubresourceRange subresourceRange = 
        {
            aspectMask:     VK_IMAGE_ASPECT_COLOR_BIT,
            baseMipLevel:   0,
            levelCount:     1,
            baseArrayLayer: 0,
            layerCount:     1
        };

        VkImageViewCreateInfo info = 
        {
            sType:              VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            pNext:              null,
            flags:              0,
            viewType:           VK_IMAGE_VIEW_TYPE_2D,
            format:             format,
            components:         componentMapping,
            subresourceRange:   subresourceRange
        };
        
        foreach (i; 0..m_images.length)
        {
            info.image = m_images[i];
            device.vkCreateImageView (&info, callbacks, &m_imageViews[i]);
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
uint32_t requiredBuffers (in VSync mode) pure nothrow @safe @nogc
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
VSync fallback (in VSync mode) pure nothrow @safe @nogc
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