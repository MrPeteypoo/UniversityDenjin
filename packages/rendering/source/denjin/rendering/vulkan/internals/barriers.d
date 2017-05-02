/**
    Contains barriers used at throughout the render loop.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: MIT
*/
module denjin.rendering.vulkan.internals.barriers;

// Engine.
import denjin.rendering.vulkan.device   : Device;
import denjin.rendering.vulkan.nulls    : nullCMDBuffer, nullDevice, nullImage;

// External.
import erupted.types    : uint32_t, VkCommandBuffer, VkImage, VkImageMemoryBarrier, VkImageSubresourceRange, 
                          VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT, VK_ACCESS_MEMORY_READ_BIT, VK_IMAGE_ASPECT_COLOR_BIT, 
                          VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL, VK_IMAGE_LAYOUT_PRESENT_SRC_KHR, 
                          VK_IMAGE_LAYOUT_UNDEFINED, VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT,
                          VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT, VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;

/// Used to initialise and update commonly used barriers to control the order in which resources are accessed.
struct Barriers
{
    private
    {
        VkImageMemoryBarrier displayToDraw; /// The image barrier which transitions a swapchain image from use by the presentation engine to being usable in rendering.
        VkImageMemoryBarrier drawToDisplay; /// The iamge barrier which transitions a swapchain image for rendering usage to being displayed by the presentation engine.
    }

    /// Contains default settings common to many image barriers.
    enum VkImageMemoryBarrier imageTemplate = 
    {   
        sType:                  VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
        pNext:                  null,
        srcAccessMask:          0,                          // Must be changed.
        dstAccessMask:          0,                          // Must be changed.
        oldLayout:              VK_IMAGE_LAYOUT_UNDEFINED,  // Must be changed.
        newLayout:              VK_IMAGE_LAYOUT_UNDEFINED,  // Must be changed.
        srcQueueFamilyIndex:    -1,                         // Must be changed.
        dstQueueFamilyIndex:    -1,                         // Must be changed.
        image:                  nullImage,                  // Must be changed.
        subresourceRange:       VkImageSubresourceRange (VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1)
    };

    /// Initialises each stored barrier so that run-time modifications only change dynamic data.
    public void reset (ref Device device) pure nothrow @safe @nogc
    in
    {
        assert (device.presentQueueFamily != uint32_t.max);
        assert (device.renderQueueFamily != uint32_t.max);
    }
    body
    {
        // We can discard the contents of the image as it is no use it us and prepare the image for use as a 
        // framebuffer attachment.
        displayToDraw = imageTemplate;
        with (displayToDraw)
        {
            srcAccessMask       = 0;
            dstAccessMask       = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
            oldLayout           = VK_IMAGE_LAYOUT_UNDEFINED;
            newLayout           = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
            srcQueueFamilyIndex = device.presentQueueFamily;
            dstQueueFamilyIndex = device.renderQueueFamily;
        }

        // This assumes that the render pass where the image will be used will transition the image to the present 
        // layout. As such all it does is hands the image over to a (potentially) different queue family.
        drawToDisplay = imageTemplate;
        with (drawToDisplay)
        {
            srcAccessMask       = VK_ACCESS_MEMORY_READ_BIT;
            dstAccessMask       = VK_ACCESS_MEMORY_READ_BIT;
            oldLayout           = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
            newLayout           = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
            srcQueueFamilyIndex = device.renderQueueFamily;
            dstQueueFamilyIndex = device.presentQueueFamily;
        }
    }

    /// Updates the barriers for usage in the current frame.
    public void update (VkImage swapchainImage) pure nothrow @safe @nogc
    in
    {
        assert (swapchainImage != nullImage);
    }
    body
    {
        displayToDraw.image = swapchainImage;
        drawToDisplay.image = swapchainImage;
    }

    /// Adds the display-to-draw swapchain image barrier to the given command buffer.
    public void displayToDrawBarrier (ref Device device, VkCommandBuffer cmdBuffer) const nothrow @nogc
    in
    {
        assert (device != nullDevice);
        assert (device.vkCmdPipelineBarrier);
        assert (cmdBuffer != nullCMDBuffer);
    }
    body
    {
        enum sourceStage        = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
        enum destinationStage   = sourceStage;
        device.vkCmdPipelineBarrier (cmdBuffer, sourceStage, destinationStage, 0, 0, null, 0, null, 1, &displayToDraw);
    }

    /// Adds the draw-to-display swapchain image barrier to the given command buffer.
    public void drawToDisplayBarrier (ref Device device, VkCommandBuffer cmdBuffer) const nothrow @nogc
    in
    {
        assert (device != nullDevice);
        assert (device.vkCmdPipelineBarrier);
        assert (cmdBuffer != nullCMDBuffer);
    }
    body
    {
        enum sourceStage        = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
        enum destinationStage   = VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT;
        device.vkCmdPipelineBarrier (cmdBuffer, sourceStage, destinationStage, 0, 0, null, 0, null, 1, &drawToDisplay);
    }
}
