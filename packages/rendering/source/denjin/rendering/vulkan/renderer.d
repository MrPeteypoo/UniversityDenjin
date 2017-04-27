/**
    Contains a 3D renderer implementing the Vulkan API.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: MIT
*/
module denjin.rendering.vulkan.renderer;

// Phobos.
import std.container.array      : Array;
import std.algorithm.iteration  : each, filter, uniq;
import std.algorithm.sorting    : sort;
import std.algorithm.mutation   : move;

// Engine.
import denjin.rendering.interfaces          : IRenderer;
import denjin.rendering.vulkan.device       : Device;
import denjin.rendering.vulkan.internals    : Commands, Framebuffers, RenderPasses, Syncs;
import denjin.rendering.vulkan.misc         : safelyDestroyVK;
import denjin.rendering.vulkan.nulls;
import denjin.rendering.vulkan.objects      : createCommandPool;
import denjin.rendering.vulkan.swapchain    : Swapchain, VSync;

// External.
import erupted.types;

/// A basic 3D renderer implemented using Vulkan. A Vulkan instance must be created and loaded before using the
/// renderer. The current implementation also requires a logical device and swapchain be generated externally.
final class RendererVulkan : IRenderer
{
    private 
    {
        alias Limits        = VkPhysicalDeviceLimits;
        alias MemoryProps   = VkPhysicalDeviceMemoryProperties;

        size_t          m_frameCount;   /// Counts how many frames in total have been rendered.
        Device          m_device;       /// The logical device containing device-level Functionality.
        Swapchain       m_swapchain;    /// Manages the display mode and displayable images available to the renderer.
        Commands        m_cmds;         /// The command pools and buffers required by the primary rendering thread.
        RenderPasses    m_passes;       /// The handles required to perform different rendering passes.
        Framebuffers    m_fbs;          /// Contains framebuffer handles and data which can be used as render targets.
        Syncs           m_syncs;        /// The synchronization objects used to control the flow of generated commands.
        Limits          m_limits;       /// The hardware limits of the physical device that the renderer must adhere to.
        MemoryProps     m_memProps;     /// The properties of the physical devices memory, necessary to allocate resources.
    }

    /// Initialises the renderer, creating Vulkan objects that are required for loading and rendering a scene.
    /// Params:
    ///     device      = The device which the renderer should take ownership of and use to render with.
    ///     swapchain   = The swapchain where the renderer should acquire and present images to.
    this (Device device, Swapchain swapchain, 
          VkPhysicalDeviceLimits limits, VkPhysicalDeviceMemoryProperties memoryProperties)
    out
    {
        assert (m_device != nullDevice);
        assert (m_swapchain != nullSwapchain);
    }
    body
    {
        // Take ownership of the resources.
        m_device    = move (device);
        m_swapchain = move (swapchain);
        m_limits    = move (limits);
        m_memProps  = move (memoryProperties);

        // We need to build the resources required by the rendering before loading a scene.
        m_swapchain.create (m_device);
        m_cmds.create (m_device, m_swapchain.imageCount);
        m_passes.create (m_device, m_swapchain.info.imageFormat);
        m_fbs.create (m_device, m_swapchain, m_memProps);
        m_syncs.create (m_device);
    }

    /// If necessary it will destroy and free any resources the renderer owns.
    ~this() nothrow
    {
        clear();
    }

    /// Destroys all contained data in a safe order. This may take a while as it will wait for any pending GPU tasks to
    /// complete before returning. This will leave the renderer in an uninitialised state and it should not be used 
    /// again.
    public override void clear() nothrow
    {
        if (m_device != nullDevice)
        {
            m_device.vkDeviceWaitIdle();
            m_syncs.clear (m_device);
            m_fbs.clear (m_device);
            m_passes.clear (m_device);
            m_cmds.clear (m_device);
            m_swapchain.clear (m_device);
            m_device.clear();
        }
    }

    public override void load()
    in
    {
        assert (m_device != nullDevice);
        assert (m_swapchain != nullSwapchain);
    }
    body
    {
    }

    /// The given resolution is ignored because if it differs from the swapchain we will cause an error.
    public override void reset (in uint, in uint)
    in
    {
        assert (m_device != nullDevice);
        assert (m_swapchain != nullSwapchain);
    }
    body
    {
        // We must wait for command buffers to be consumed before recreating the swapchain.
        m_syncs.waitForFences (m_device);
        m_swapchain.create (m_device);
    }

    /// Does absolutely nothing right now. Likely will be used to track and update time.
    public override void update (in float deltaTime)
    in
    {
        assert (m_device != nullDevice);
        assert (m_swapchain != nullSwapchain);
    }
    body
    {
    }

    /// Renders and displays a frame to the display.
    public override void render() nothrow
    in
    {
        assert (m_device != nullDevice);
        assert (m_swapchain != nullSwapchain);
    }
    body
    {
        // Firstly we must request an image from the presentation engine to start working on the next frame.
        validateNextSwapchainImage();
        m_syncs.advanceFenceIndex (++m_frameCount);

        // Record the actual rendering work.
        recordRender();

        // Submit the commands for execution.
        submitRender();

        // We're finished and can inform the presentation engine to display the image.
        presentImage();
    }

    /// Informs the swapchain to acquire the next image from the presentation engine and halts the application if it's
    /// unable to do this.
    private void validateNextSwapchainImage() nothrow
    {
        const auto result = m_swapchain.acquireNextImage (m_device, m_syncs.imageAvailable);
        if (result != VK_SUCCESS && result != VK_SUBOPTIMAL_KHR)
        {
            assert (false, "Not handling this case yet.");
        }
    }

    /// Informs the presentation engine that it can read from the current swapchain image and display it on screen.
    private void presentImage() nothrow @nogc
    {
        const auto handle   = m_swapchain.handle;
        const auto index    = m_swapchain.imageIndex;
        const VkPresentInfoKHR info =
        {
            sType:              VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
            pNext:              null,
            waitSemaphoreCount: 1,
            pWaitSemaphores:    &m_syncs.frameComplete,
            swapchainCount:     1,
            pSwapchains:        &handle,
            pImageIndices:      &index,
            pResults:           null
        };

        if (m_device.vkQueuePresentKHR (m_device.presentQueue, &info) != VK_SUCCESS)
        {
            assert (false, "Not handling this case yet");
        }
    }

    /// Performs that actual rendering aspect of the frame.
    private void recordRender() nothrow
    {
        // Firstly we must ensure we aren't writing to a buffer which is pending.
        const auto fence = m_syncs.renderFence;
        m_device.vkWaitForFences (1, &fence, VK_FALSE, uint64_t.max);
        m_device.vkResetFences (1, &fence);

        // Secondly we must make the command buffer enters a "recording" state.
        auto cmdBuffer = m_cmds.render[m_swapchain.imageIndex];
        VkCommandBufferBeginInfo beginInfo = 
        {
            sType:              VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            pNext:              null,
            flags:              VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
            pInheritanceInfo:   null
        };
        m_device.vkBeginCommandBuffer (cmdBuffer, &beginInfo);

        // Prepare a clear colour value.
        VkClearColorValue colour = { float32: 0f };
        colour.float32[0] = 1f;
        
        // We need to inform the GPU where in the image we'll be clearing.
        auto subresourceRange = VkImageSubresourceRange (VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1);

        // We need to ensure configure the memory barriers properly.
        VkImageMemoryBarrier presentToClear = 
        {
            VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
            null,
            0,
            VK_ACCESS_TRANSFER_WRITE_BIT,
            VK_IMAGE_LAYOUT_UNDEFINED,
            VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            m_device.presentQueueFamily,
            m_device.renderQueueFamily,
            m_swapchain.image,
            subresourceRange
        };

        VkImageMemoryBarrier clearToPresent = 
        {
            VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
            null,
            VK_ACCESS_TRANSFER_WRITE_BIT,
            VK_ACCESS_MEMORY_READ_BIT,
            VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
            m_device.renderQueueFamily,
            m_device.presentQueueFamily,
            m_swapchain.image,
            subresourceRange
        };

        m_device.vkCmdPipelineBarrier (cmdBuffer, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, null, 0, null, 1, &presentToClear);

        m_device.vkCmdClearColorImage (cmdBuffer, m_swapchain.image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, &colour, 1, &subresourceRange);

        m_device.vkCmdPipelineBarrier (cmdBuffer, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT, 0, 0, null, 0, null, 1, &clearToPresent);

        m_device.vkEndCommandBuffer (cmdBuffer);
    }

    private void submitRender() nothrow
    {
        const VkPipelineStageFlags waitFlags = VK_PIPELINE_STAGE_TRANSFER_BIT;
        const auto buffer = m_cmds.render[m_swapchain.imageIndex];
        VkSubmitInfo submitInfo =
        {
            sType:                  VK_STRUCTURE_TYPE_SUBMIT_INFO,
            pNext:                  null,
            waitSemaphoreCount:     1,
            pWaitSemaphores:        &m_syncs.imageAvailable,
            pWaitDstStageMask:      &waitFlags,
            commandBufferCount:     1,
            pCommandBuffers:        &buffer,
            signalSemaphoreCount:   1,
            pSignalSemaphores:      &m_syncs.frameComplete
        };

        m_device.vkQueueSubmit (m_device.renderQueue, 1, &submitInfo, m_syncs.renderFence);
    }
}