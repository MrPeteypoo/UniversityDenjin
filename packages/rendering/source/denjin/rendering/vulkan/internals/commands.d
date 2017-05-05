/**
    Manages the construction, containment and destruction of command pools.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: Copyright © 2017, Simon Peter Campbell
    License: MIT
*/
module denjin.rendering.vulkan.internals.commands;

// Phobos.
import std.container.array      : Array;
import std.algorithm.iteration  : each, filter, uniq;
import std.algorithm.sorting    : sort;

// Engine.
import denjin.rendering.vulkan.device   : Device;
import denjin.rendering.vulkan.misc     : enforceSuccess;
import denjin.rendering.vulkan.nulls    : nullCMDBuffer, nullPool;
import denjin.rendering.vulkan.objects  : allocateCommandBuffers, createCommandPool;

// External.
import erupted.types : uint32_t, VkCommandBuffer, VkCommandPool, VkCommandPoolCreateFlags, 
                       VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT, VK_COMMAND_POOL_CREATE_TRANSIENT_BIT, VK_SUCCESS;

/// Maintains the command pools and buffers available to the primary renderer thread.
struct Commands
{
    alias CommandBuffers = Array!VkCommandBuffer;

    VkCommandBuffer[]   render;     /// A command buffer for each swapchain image dedicated to rendering work.
    VkCommandBuffer[]   compute;    /// A command buffer for each swapchain image dedicated to compute work.
    VkCommandBuffer[]   transfer;   /// A command buffer for each swapchain image dedicated to data transfer work.

    VkCommandPool   renderPool      = nullPool; /// Used for rendering work.
    VkCommandPool   computePool     = nullPool; /// Used for dedicated compute task.
    VkCommandPool   transferPool    = nullPool; /// Used for transferring data to the GPU.

    /// Creates, if possible, and assigns each category of command pool variable.
    public void create (ref Device device, in uint32_t bufferCount)
    in
    {
        assert (renderPool == nullPool);
        assert (computePool == nullPool);
        assert (transferPool == nullPool);
    }
    out
    {
        assert (renderPool != nullPool);
        assert (computePool != nullPool);
        assert (transferPool != nullPool);
    }
    body
    {
        // Create the pools.
        enum flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT | VK_COMMAND_POOL_CREATE_TRANSIENT_BIT;
        if (renderPool.createCommandPool (device, device.renderQueueFamily, flags) != VK_SUCCESS)
        {
            assert (false, "Uh oh, the renderer isn't flexible enough for this yet!");
        }

        computePool  = createCommandPoolIfPossible (device, device.hasDedicatedComputeFamily, device.computeQueueFamily, flags);
        transferPool = createCommandPoolIfPossible (device, device.hasDedicatedTransferFamily, device.transferQueueFamily, flags);

        // Allocate the command buffers.
        render.length   = bufferCount;
        compute.length  = bufferCount;
        transfer.length = bufferCount;

        allocateCommandBuffers (render[], device, renderPool).enforceSuccess;
        allocateCommandBuffers (compute[], device, computePool).enforceSuccess;
        allocateCommandBuffers (transfer[], device, transferPool).enforceSuccess;
    }

    /// Destroys all unique command pools, ensuring duplicates aren't deleted.
    public void clear (ref Device device) nothrow
    {
        VkCommandPool[3] pools = [renderPool, computePool, transferPool];
        pools[0..$].sort()
            .uniq()
            .filter!(a => a != nullPool)
            .each!(p => device.vkDestroyCommandPool (p, null));

        renderPool = computePool = transferPool = nullPool;

        // Command buffers are automatically freed when destroying command pools.
        render.length = 0;
        compute.length = 0;
        transfer.length = 0;
    }
    
    /**
        Attempts to create a command pool from the given queue family.

        If the device doesn't have a dedicated queue family as specified by the given parameter, then the render family
        is assumed to be general purpose and that command pool will be used as a fallback.
    */
    nothrow @nogc
    private VkCommandPool createCommandPoolIfPossible (ref Device device, in bool hasDedicatedQueueFamily, 
                                                       in uint32_t queueFamily, in VkCommandPoolCreateFlags flags)
    {
        if (hasDedicatedQueueFamily)
        {
            VkCommandPool pool = nullPool;
            if (pool.createCommandPool (device, queueFamily) == VK_SUCCESS)
            {
                return pool;
            }
            else if (pool != nullPool)
            {
                device.vkDestroyCommandPool (pool, null);
            }
        }

        return renderPool;
    }
}