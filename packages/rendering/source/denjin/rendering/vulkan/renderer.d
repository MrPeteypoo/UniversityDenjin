/**
    Contains a 3D renderer implementing the Vulkan API.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: Copyright © 2017, Simon Peter Campbell
    License: MIT
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
import denjin.rendering.vulkan.internals    : Barriers, Commands, Framebuffers, Pipelines, RenderPasses, Syncs, 
                                              Uniforms;
import denjin.rendering.vulkan.misc         : safelyDestroyVK;
import denjin.rendering.vulkan.nulls;
import denjin.rendering.vulkan.objects      : createCommandPool;
import denjin.rendering.vulkan.swapchain    : Swapchain, VSync;

// External.
import erupted.types;

/**
    A basic 3D renderer implemented using Vulkan. 
    
    A Vulkan instance must be created and loaded before using the renderer. The current implementation also requires 
    a logical device and swapchain be generated externally. The renderer currently only supports forward rendering,
    it requires further development to support more modern rendering techniques such as deferred shading and deferred
    lighting.
*/
final class RendererVulkan (Assets, Scene) : IRenderer!(Assets, Scene)
{
    private 
    {
        // Aliases.
        alias Limits        = VkPhysicalDeviceLimits;
        alias MemoryProps   = VkPhysicalDeviceMemoryProperties;

        // Global data.
        enum VkClearColorValue clearColor               = { float32: [0f, 0f, 0f, 0f] };
        enum VkClearDepthStencilValue clearDepth        = { depth: 1f, stencil: 255 };
        static immutable VkClearValue[2] clearValues    = [{ color: clearColor }, { depthStencil: clearDepth }];
        static immutable size_t virtualFrames           = 3;

        size_t          m_frameCount;   /// Counts how many frames in total have been rendered.
        Device          m_device;       /// The logical device containing device-level Functionality.
        Swapchain       m_swapchain;    /// Manages the display mode and displayable images available to the renderer.
        RenderPasses    m_passes;       /// The handles required to perform different rendering passes.
        Uniforms        m_uniforms;     /// Handles the construction of uniform buffer blocks.
        Pipelines       m_pipelines;    /// Stores the bindable pipelines used in the render loop.
        Commands        m_cmds;         /// The command pools and buffers required by the primary rendering thread.
        Framebuffers    m_fbs;          /// Contains framebuffer handles and data which can be used as render targets.
        Barriers        m_barriers;     /// Stores the barriers required to synchronise access to resources across different queues.
        Syncs           m_syncs;        /// The synchronization objects used to control the flow of generated commands.
        Limits          m_limits;       /// The hardware limits of the physical device that the renderer must adhere to.
        MemoryProps     m_memProps;     /// The properties of the physical devices memory, necessary to allocate resources.
    }

    /// Initialises the renderer, creating Vulkan objects that are required for loading and rendering a scene.
    /// Params:
    ///     device              = The device which the renderer should take ownership of and use to render with.
    ///     swapchain           = The swapchain where the renderer should acquire and present images to.
    ///     limits              = The limits of the physical device associated with the given logical device.
    ///     memoryProperties    = The properties of the memory heaps available to the physical device.
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
        scope (failure) clear();
        m_swapchain.create (m_device);
        m_passes.create (m_device, m_swapchain.info.imageFormat);
        m_uniforms.create (m_device, m_limits, m_memProps, virtualFrames);
        m_pipelines.create (m_device, m_swapchain.info.imageExtent, m_passes);
        m_cmds.create (m_device, m_swapchain.imageCount);
        m_fbs.create (m_device, m_swapchain, m_passes, m_memProps);
        m_barriers.reset (m_device);
        m_syncs.create (m_device, virtualFrames);
    }

    /// If necessary it will destroy and free any resources the renderer owns.
    ~this() nothrow
    {
        clear();
    }

    /**
        Destroys all contained data in a safe order. 
        
        This may take a while as it will wait for any pending GPU tasks to complete before returning. This will leave 
        the renderer in an uninitialised state and it should not be used again.
    */
    public override void clear() nothrow
    {
        if (m_device != nullDevice)
        {
            m_device.vkDeviceWaitIdle();
            m_syncs.clear (m_device);
            m_fbs.clear (m_device);
            m_cmds.clear (m_device);
            m_pipelines.clear (m_device);
            m_uniforms.clear (m_device);
            m_passes.clear (m_device);
            m_swapchain.clear (m_device);
            m_device.clear();
        }
    }

    public override void load (in ref Assets assets, in ref Scene scene)
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
        scope (failure) clear();
        m_syncs.waitForFences (m_device);
        m_swapchain.create (m_device);
        
        m_fbs.clear (m_device);
        m_fbs.create (m_device, m_swapchain, m_passes, m_memProps);
        
        m_pipelines.clear (m_device);
        m_pipelines.create (m_device, m_swapchain.info.imageExtent, m_passes);
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
    public override void render (in ref Scene scene) nothrow
    in
    {
        assert (m_device != nullDevice);
        assert (m_swapchain != nullSwapchain);
    }
    body
    {
        // Update the frame index for the internals.
        immutable frameIndex    = m_frameCount++ % virtualFrames;
        m_syncs.frameIndex      = frameIndex;

        // Firstly we must request an image from the presentation engine to start working on the next frame.
        validateNextSwapchainImage();
        m_barriers.update (m_swapchain.image);

        // Record the actual rendering work.
        recordRender();

        // Submit the commands for execution.
        submitRender();

        // We're finished and can inform the presentation engine to display the image.
        presentImage();
    }

    /**
        Informs the swapchain to acquire the next image from the presentation engine and halts the application if it's
        unable to do this.
    */
    private void validateNextSwapchainImage() nothrow
    {
        const auto result = m_swapchain.acquireNextImage (m_device, m_syncs.imageAvailable);
        if (result != VK_SUCCESS && result != VK_SUBOPTIMAL_KHR)
        {
            assert (false, "Not handling this case yet.");
        }
    }

    /// Performs that actual rendering aspect of the frame.
    private void recordRender() nothrow
    {
        // Firstly we must ensure we aren't writing to a buffer which is pending.
        const auto fence = m_syncs.renderComplete;
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
        scope (exit) m_device.vkEndCommandBuffer (cmdBuffer);

        // Next we must ensure that we only restrict access to the current swapchain image when it needs to be used.
        m_barriers.displayToDrawBarrier (m_device, cmdBuffer);
        scope (exit) m_barriers.drawToDisplayBarrier (m_device, cmdBuffer);

        // Now we can begin the render pass.
        const VkRenderPassBeginInfo passInfo = 
        {
            sType:              VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
            pNext:              null,
            renderPass:         m_passes.forward,
            framebuffer:        m_fbs.framebuffer (m_swapchain.imageIndex),
            clearValueCount:    cast (uint32_t) clearValues.length,
            pClearValues:       clearValues.ptr,
            renderArea:     
            { 
                offset: { x: 0, y: 0 },
                extent: m_swapchain.info.imageExtent
            }
        };
        m_device.vkCmdBeginRenderPass (cmdBuffer, &passInfo, VK_SUBPASS_CONTENTS_INLINE);
        scope (exit) m_device.vkCmdEndRenderPass (cmdBuffer);
        
        // Finally we can draw objects.
        renderObjects (cmdBuffer);
    }

    /**
        Assuming a command buffer record operation has begun, this will record draw commands required to render the 
        scene.
    */
    private void renderObjects (VkCommandBuffer primaryBuffer) nothrow
    in
    {
        assert (primaryBuffer != nullCMDBuffer);
    }
    body
    {
        m_device.vkCmdBindPipeline (primaryBuffer, VK_PIPELINE_BIND_POINT_GRAPHICS, m_pipelines.forward);
        m_device.vkCmdDraw (primaryBuffer, 3, 1, 0, 0);
    }

    /// Submits the command buffer used for the current frame to the render queue.
    private void submitRender() nothrow
   { 
        const auto waitFlags            = cast (uint32_t) VK_PIPELINE_STAGE_TRANSFER_BIT;
        const auto buffer               = m_cmds.render[m_swapchain.imageIndex];
        const VkSubmitInfo submitInfo   =
        {
            sType:                  VK_STRUCTURE_TYPE_SUBMIT_INFO,
            pNext:                  null,
            waitSemaphoreCount:     1,
            pWaitSemaphores:        &m_syncs.imageAvailable(),
            pWaitDstStageMask:      &waitFlags,
            commandBufferCount:     1,
            pCommandBuffers:        &buffer,
            signalSemaphoreCount:   1,
            pSignalSemaphores:      &m_syncs.frameComplete()
        };

        m_device.vkQueueSubmit (m_device.renderQueue, 1, &submitInfo, m_syncs.renderComplete);
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
            pWaitSemaphores:    &m_syncs.frameComplete(),
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
}