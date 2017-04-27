/**
    Contains functionality related to framebuffers used by the renderer. Consider merging this module with
    denjin.rendering.vulkan.internals.renderpasses as they seem to be tightly coupled.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: MIT
*/
module denjin.rendering.vulkan.internals.framebuffers;

// Phobos.
import std.exception : enforce;

// Engine.
import denjin.rendering.vulkan.device       : Device;
import denjin.rendering.vulkan.misc         : enforceSuccess, memoryTypeIndex, safelyDestroyVK;
import denjin.rendering.vulkan.nulls        : nullDevice, nullFramebuffer, nullImage, nullImageView, nullMemory, 
                                              nullSwapchain;
import denjin.rendering.vulkan.swapchain    : Swapchain;

// External.
import erupted.types : uint32_t, VkAllocationCallbacks, VkDeviceMemory, VkExtent3D, VkImage, VkImageCreateInfo, 
                       VkImageView, VkImageViewCreateInfo, VkMemoryAllocateInfo, VkMemoryRequirements, 
                       VkPhysicalDeviceMemoryProperties, VK_COMPONENT_SWIZZLE_IDENTITY, VK_FORMAT_D24_UNORM_S8_UINT, 
                       VK_IMAGE_ASPECT_DEPTH_BIT, VK_IMAGE_ASPECT_STENCIL_BIT, VK_IMAGE_LAYOUT_UNDEFINED, 
                       VK_IMAGE_TILING_OPTIMAL, VK_IMAGE_TYPE_2D, VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT, 
                       VK_IMAGE_VIEW_TYPE_2D, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, VK_SAMPLE_COUNT_1_BIT, 
                       VK_SHARING_MODE_EXCLUSIVE, VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO, 
                       VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO, VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;

/// Contains images, image views and framebuffers which are used for different render passes by the renderer. Swapchain
/// images are excluded from this as they are managed by the Swapchain. 
struct Framebuffers
{
    VkImageView     depthView   = nullImageView;    /// An attachable "view" of the actual depth buffer image.
    VkImage         depthImage  = nullImage;        /// A handle to the image being used as a depth buffer.
    VkDeviceMemory  depthMemory = nullMemory;       /// A handle to the memory allocated to the depth buffer image.

    /// The extents need to be changed at run-time but
    enum VkImageCreateInfo depthImageInfo =
    {
        sType:                  VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        pNext:                  null,
        flags:                  0,
        imageType:              VK_IMAGE_TYPE_2D,
        format:                 VK_FORMAT_D24_UNORM_S8_UINT,
        extent:                 VkExtent3D (1, 1, 1),
        mipLevels:              1,
        arrayLayers:            1,
        samples:                VK_SAMPLE_COUNT_1_BIT,
        tiling:                 VK_IMAGE_TILING_OPTIMAL,
        usage:                  VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
        sharingMode:            VK_SHARING_MODE_EXCLUSIVE,
        queueFamilyIndexCount:  0,
        pQueueFamilyIndices:    null,
        initialLayout:          VK_IMAGE_LAYOUT_UNDEFINED
    };

    /// Creates the required framebuffers and images to provide the renderer with render targets.
    public void create (ref Device device, in ref Swapchain swapchain, 
                        in ref VkPhysicalDeviceMemoryProperties memProps, in VkAllocationCallbacks* callbacks = null)
    in
    {
        assert (device != nullDevice);
        assert (swapchain != nullSwapchain);
        assert (depthImage == nullImage);
        assert (depthView == nullImageView);
        assert (depthMemory == nullMemory);
    }
    out
    {
        assert (depthImage != nullImage);
        assert (depthView != nullImageView);
        assert (depthMemory != nullMemory);
    }
    body
    {
        createDepthBuffer (device, swapchain, memProps, callbacks);
    }

    /// Deletes stored resources and returns the object to an uninitialised state.
    public void clear (ref Device device, in VkAllocationCallbacks* callbacks = null) nothrow @nogc
    in
    {
        assert (depthView != nullImageView);
        assert (depthImage != nullImage);
        assert (depthMemory != nullMemory);
    }
    body
    {
        depthView.safelyDestroyVK (device.vkDestroyImageView, device, depthView, callbacks);
        depthImage.safelyDestroyVK (device.vkDestroyImage, device, depthImage, callbacks);
        depthMemory.safelyDestroyVK (device.vkFreeMemory, device, depthMemory, callbacks);
    }

    private void createDepthBuffer (ref Device device, in ref Swapchain swapchain, 
                                    in ref VkPhysicalDeviceMemoryProperties memProps,
                                    in VkAllocationCallbacks* callbacks = null)
    {
        // We need to update the size of the depth buffer.
        immutable displaySize   = swapchain.info.imageExtent;
        auto imageInfo          = depthImageInfo;
        imageInfo.extent        = VkExtent3D (displaySize.width, displaySize.height, 1);

        device.vkCreateImage (&imageInfo, callbacks, &depthImage).enforceSuccess;
        scope (failure) device.vkDestroyImage (depthImage, callbacks);
        
        // Allocate memory for the depth buffer.
        VkMemoryRequirements memory = void;
        device.vkGetImageMemoryRequirements (depthImage, &memory);
        
        VkMemoryAllocateInfo allocInfo = 
        {
            sType:              VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
            pNext:              null,
            allocationSize:     memory.size,
            memoryTypeIndex:    memProps.memoryTypeIndex (memory.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)
        };

        enforce (allocInfo.memoryTypeIndex != uint32_t.max);
        device.vkAllocateMemory (&allocInfo, callbacks, &depthMemory).enforceSuccess;
        scope (failure) device.vkFreeMemory (depthMemory, callbacks);

        // Bind the memory to the image.
        device.vkBindImageMemory (depthImage, depthMemory, 0).enforceSuccess;

        // Finally create the image view.
        VkImageViewCreateInfo viewInfo =
        {
            sType:          VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            pNext:          null,
            flags:          0,
            image:          depthImage,
            viewType:       VK_IMAGE_VIEW_TYPE_2D,
            format:         imageInfo.format,
            components:
            {
                r: VK_COMPONENT_SWIZZLE_IDENTITY, g: VK_COMPONENT_SWIZZLE_IDENTITY, 
                b: VK_COMPONENT_SWIZZLE_IDENTITY, a: VK_COMPONENT_SWIZZLE_IDENTITY
            },
            subresourceRange:
            {
                aspectMask:     VK_IMAGE_ASPECT_DEPTH_BIT | VK_IMAGE_ASPECT_STENCIL_BIT,
                baseMipLevel:   0,
                levelCount:     1,
                baseArrayLayer: 0,
                layerCount:     1
            }
        };
        device.vkCreateImageView (&viewInfo, callbacks, &depthView).enforceSuccess;
        scope (failure) device.vkDestroyImageView (depthView, callbacks);
    }
}