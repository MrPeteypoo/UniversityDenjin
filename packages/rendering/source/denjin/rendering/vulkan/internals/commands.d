/**
    Manages the construction, containment and destruction of command pools.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: MIT
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
import erupted.types : uint32_t, VkCommandBuffer, VkCommandPool, VK_SUCCESS;

/// Maintains the command pools available to the primary renderer thread.
struct CommandPools
{
    alias CommandBuffers = Array!VkCommandBuffer;

    CommandBuffers  presentCommands;            /// A command buffer for each swapchain image.

    VkCommandPool   renderPool      = nullPool; /// Used for rendering work.
    VkCommandPool   computePool     = nullPool; /// Used for dedicated compute task.
    VkCommandPool   transferPool    = nullPool; /// Used for transferring data to the GPU.
    VkCommandPool   presentPool     = nullPool; /// Used for presenting swapchain images to the display.

    /// Creates, if possible, and assigns each category of command pool variable.
    public void createCommandPools (ref Device device, in uint32_t swapchainImageCount)
    in
    {
        assert (renderPool == nullPool);
        assert (computePool == nullPool);
        assert (transferPool == nullPool);
        assert (presentPool == nullPool);
    }
    out
    {
        assert (renderPool != nullPool);
        assert (computePool != nullPool);
        assert (transferPool != nullPool);
        assert (presentPool != nullPool);
    }
    body
    {
        // Create the pools.
        if (renderPool.createCommandPool (device, device.renderQueueFamily) != VK_SUCCESS)
        {
            assert (false, "Uh oh, the renderer isn't flexible enough for this yet!");
        }

        computePool     = createCommandPoolIfPossible (device, device.hasDedicatedComputeFamily, device.computeQueueFamily);
        transferPool    = createCommandPoolIfPossible (device, device.hasDedicatedTransferFamily, device.transferQueueFamily);
        presentPool     = createCommandPoolIfPossible (device, device.hasDedicatedPresentFamily, device.presentQueueFamily);

        // Allocate the command buffers.
        presentCommands.length = swapchainImageCount;
        allocateCommandBuffers (presentCommands[], device, presentPool).enforceSuccess;
    }

    /// Destroys all unique command pools, ensuring duplicates aren't deleted.
    public void destroyCommandPools (ref Device device) nothrow @nogc
    {
        VkCommandPool[4] pools = [renderPool, computePool, transferPool, presentPool];
        pools[0..$].sort()
            .uniq()
            .filter!(a => a != nullPool)
            .each!(p => device.vkDestroyCommandPool (p, null));

        renderPool = computePool = transferPool = presentPool = nullPool;
    }
    
    /// If the device doesn't have a dedicated queue family as specified by the given parameter, then the render family
    /// is assumed to be general purpose and that command pool will be used as a fallback.
    private VkCommandPool createCommandPoolIfPossible (ref Device device, in bool hasDedicatedQueueFamily, 
                                                       in uint32_t queueFamily) nothrow @nogc
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