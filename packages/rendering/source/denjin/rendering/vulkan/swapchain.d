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
        VkSwapchainKHR      m_handle        = nullSwapchain;    /// The handle of the created swapchain.
        VkImage             m_currentImage  = nullImage;        /// The handle to the image acquired from the swapchain.
        VkImageView         m_currentView   = nullImageView;    /// The handle to the image view of the current swapchain image.
        uint32_t            m_currentIndex;                     /// The index of the current swapchain image to use for displaying.
        Images              m_images;                           /// Contains handles to each swapchain image.
        ImageViews          m_views;                            /// Contains writing image views for each image in the swapchain.

        // Rarely accessed data.
        VkSurfaceKHR                m_surface   = nullSurface;      /// The handle to the surface which will display images.
        VkPhysicalDevice            m_gpu       = nullPhysDevice;   /// The handle of the GPU interfacing with the presentation engine.
        VkSwapchainCreateInfoKHR    m_info;                         /// The creation information used to initialise the swapchain images.
        VkSurfaceCapabilitiesKHR    m_capabilities;                 /// The capabilities of the physical device + surface combination.
        SurfaceFormats              m_formats;                      /// Available colour formats for the current surface.
        PresentModes                m_modes;                        /// Single, double, triple buffering capabilities.
    }

    // Subtype VkSwapchainKHR to allow for implicit usage.
    alias handle this;

    /// The default timeout when acquiring the next image will halt the application until an image is ready in debug
    /// and will wait a second in release modes. This is to make debugging easier 
    debug { enum acquireImageTimeout = uint64_t.max; }
    else {  enum acquireImageTimeout = 1_000_000_000; }

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

        // Set the initial values for the creation information.
        m_info.sType                    = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR;
        m_info.pNext                    = null;
        m_info.flags                    = 0;
        m_info.surface                  = m_surface;
        m_info.imageArrayLayers         = 1;
        m_info.imageUsage               = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
        m_info.imageSharingMode         = VK_SHARING_MODE_EXCLUSIVE;
        m_info.queueFamilyIndexCount    = 0;
        m_info.pQueueFamilyIndices      = null;
        m_info.compositeAlpha           = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
        m_info.clipped                  = VK_TRUE;
    }

    /// Gets the handle to the managed swapchain.
    public @property inout(VkSwapchainKHR) handle() inout pure nothrow @safe @nogc { return m_handle; }

    /// Gets the handle to the currently acquired image.
    public @property inout(VkImage) image() inout pure nothrow @safe @nogc { return m_currentImage; }

    /// Gets the handle to the image view for the currently acquired image.
    public @property inout(VkImageView) imageView() inout pure nothrow @safe @nogc { return m_currentView; }

    /// Gets the handle to the image view for the given image index.
    public inout(VkImageView) getImageView (in size_t index) inout pure nothrow @safe
    in
    {
        assert (index < m_views.length);
    }
    body
    {
        return m_views[index];
    }

    /// Gets the index of the currently acquired swapchain image.
    public @property uint32_t imageIndex() inout pure nothrow @safe @nogc { return m_currentIndex; }

    /// Gets the number of images managed by the current swapchain.
    public @property uint32_t imageCount() const pure nothrow @safe @nogc { return cast (uint32_t) m_images.length; }

    /// Gets the information used to create the current swapchain.
    public @property ref const(VkSwapchainCreateInfoKHR) info() const pure nothrow @safe @nogc { return m_info; }

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
        // Firstly ensure we know the capabilities of the surface and that the surface is a suitable transfer
        // destination as this is necessary for clearing the data and makes using framebuffers easier.
        vkGetPhysicalDeviceSurfaceCapabilitiesKHR (m_gpu, m_surface, &m_capabilities).enforceSuccess;
        enforce ((m_capabilities.supportedUsageFlags & VK_IMAGE_USAGE_TRANSFER_DST_BIT) > 0);

        // Compile the creation information.
        m_info.imageExtent  = m_capabilities.currentExtent;
        m_info.preTransform = m_capabilities.currentTransform;
        m_info.oldSwapchain = m_handle;
        setPresentMode (desiredMode);
        setFormat();

        // Create the swapchain and destroy the old one!
        device.vkCreateSwapchainKHR (&m_info, callbacks, &m_handle).enforceSuccess;
        m_info.oldSwapchain.safelyDestroyVK (device.vkDestroySwapchainKHR, device, m_info.oldSwapchain, callbacks);
        
        // Finally retrieve the swapchain images.
        createImageViews (device, callbacks);
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
        m_handle.safelyDestroyVK (device.vkDestroySwapchainKHR, device, m_handle, callbacks);
        m_views.each!(v => v.safelyDestroyVK (device.vkDestroyImageView, device, v, callbacks));
        
        m_currentView   = nullImageView;
        m_surface       = nullSurface;
        m_gpu           = nullPhysDevice;
        m_views.clear();
        m_formats.clear();
        m_modes.clear();
        m_images.clear();
    }

    /// Attempts to acquire the next available image from the presentaton engine.
    nothrow
    public VkResult acquireNextImage (ref Device device, VkSemaphore signalA = nullSemaphore, 
                                      VkFence signalB = nullFence, in uint64_t timeout = acquireImageTimeout) 
    {
        // Acquire the image and track the result.
        immutable result = device.vkAcquireNextImageKHR (m_handle, timeout, signalA, signalB, &m_currentIndex);

        // If the acquisition is successful then we should cache the current image and image view.
        if (result == VK_SUCCESS || result == VK_SUBOPTIMAL_KHR)
        {
            assert (m_currentIndex < m_images.length);
            assert (m_currentIndex < m_views.length);
            m_currentImage  = m_images[m_currentIndex];
            m_currentView   = m_views[m_currentIndex];
        }

        return result;
    }

    /// Attempts to set the image count and presentation mode to be the same as the desired VSync mode. If the device
    /// supports the feature then it will be configured, otherwise the closest approximation will be chosen.
    private void setPresentMode (in VSync desiredMode)
    {
        const auto vsyncMode    = cast (VkPresentModeKHR) desiredMode;
        const auto imageCount   = desiredMode.requiredBuffers;
        if (!m_modes[0..$].canFind (vsyncMode) || m_capabilities.maxImageCount < imageCount)
        {
            setPresentMode (desiredMode.fallback);
        }
        else
        {
            m_info.presentMode      = vsyncMode;
            m_info.minImageCount    = imageCount.clamp (m_capabilities.minImageCount, m_capabilities.maxImageCount);
        }
    }

    /// Sets the given format variables to the most appropriate values.
    private void setFormat()
    {
        // There may be no preferred format.
        if (m_formats.length == 1 && m_formats.front().format == VK_FORMAT_UNDEFINED)
        {
            m_info.imageFormat      = VK_FORMAT_R8G8B8A8_UNORM;
            m_info.imageColorSpace  = VK_COLOR_SPACE_SRGB_NONLINEAR_KHR;
        }
        else
        {
            // Attempt to use the common 8bpc RGBA format if possible.
            const auto result = find!"a.format == b"(m_formats[0..$], VK_FORMAT_R8G8B8A8_UNORM);
            if (result.empty)
            {
                m_info.imageFormat      = m_formats.front.format;
                m_info.imageColorSpace  = m_formats.front.colorSpace;
            }
            else
            {
                m_info.imageFormat      = result.front.format;
                m_info.imageColorSpace  = result.front.colorSpace;
            }
        }
    }

    /// Gets all images associated with the current swapchain and creates image views for each of them.
    private void createImageViews (ref Device device, in VkAllocationCallbacks* callbacks)
    {
        // Firstly ensure we don't leak data.
        m_views.each!(v => v.safelyDestroyVK (device.vkDestroyImageView, device, v, callbacks));

        // Firstly retrieve the images for the swapchain.
        uint32_t count = void;
        device.vkGetSwapchainImagesKHR (m_handle, &count, null).enforceSuccess;

        m_images.length = cast (size_t) count;
        m_views.length  = m_images.length;
        device.vkGetSwapchainImagesKHR (m_handle, &count, &m_images.front()).enforceSuccess;

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
            format:             m_info.imageFormat,
            components:         componentMapping,
            subresourceRange:   subresourceRange
        };
        
        foreach (i; 0..m_images.length)
        {
            info.image = m_images[i];
            device.vkCreateImageView (&info, callbacks, &m_views[i]);
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