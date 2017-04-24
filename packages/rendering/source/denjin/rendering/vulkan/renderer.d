/**
    Contains a 3D renderer implementing the Vulkan API.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: MIT
*/
module denjin.rendering.vulkan.renderer;

// Phobos.
import std.algorithm.iteration  : each, filter, uniq;
import std.algorithm.sorting    : sort;
import std.algorithm.mutation   : move;

// Engine.
import denjin.rendering.interfaces          : IRenderer;
import denjin.rendering.vulkan.device       : Device;
import denjin.rendering.vulkan.misc         : nullHandle, safelyDestroyVK;
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
        enum nullPool = nullHandle!VkCommandPool;

        Device      m_device;       /// The logical device containing device-level Functionality.
        Swapchain   m_swapchain;    /// Manages the display mode and displayable images available to the renderer.

        VkCommandPool   m_renderPool    = nullPool; /// Used for rendering work.
        VkCommandPool   m_computePool   = nullPool; /// Used for dedicated compute task.
        VkCommandPool   m_transferPool  = nullPool; /// Used for transferring data to the GPU.
        VkCommandPool   m_presentPool   = nullPool; /// Used for presenting swapchain images to the display.
    }

    this (Device device, Swapchain swapchain)
    out
    {
        assert (m_device != nullHandle!VkDevice);
        assert (m_swapchain != nullHandle!VkSwapchainKHR);
    }
    body
    {
        // Take ownership of the resources.
        m_device    = move (device);
        m_swapchain = move (swapchain);

        // We need a swapchain to start rendering.
        m_swapchain.create (m_device);
        createCommandPools();
    }

    ~this() nothrow
    {
        clear();
    }

    public override void clear() nothrow
    {
        if (m_device != nullHandle!VkDevice)
        {
            m_device.vkDeviceWaitIdle();
            destroyCommandPools();
            m_swapchain.clear (m_device);
            m_device.clear();
        }
    }

    public override void load()
    in
    {
        assert (m_device != nullHandle!VkDevice);
        assert (m_swapchain != nullHandle!VkSwapchainKHR);
    }
    body
    {
    }

    /// The given resolution is ignored because if it differs from the swapchain we will cause an error.
    public override void reset (in uint, in uint)
    in
    {
        assert (m_device != nullHandle!VkDevice);
        assert (m_swapchain != nullHandle!VkSwapchainKHR);
    }
    body
    {
        m_swapchain.create (m_device);
    }

    public override void update (in float deltaTime)
    in
    {
        assert (m_device != nullHandle!VkDevice);
        assert (m_swapchain != nullHandle!VkSwapchainKHR);
    }
    body
    {
    }

    public override void render() nothrow
    in
    {
        assert (m_device != nullHandle!VkDevice);
        assert (m_swapchain != nullHandle!VkSwapchainKHR);
    }
    body
    {
    }

    private void createCommandPools() nothrow @nogc
    out
    {
        assert (m_renderPool != nullPool);
        assert (m_computePool != nullPool);
        assert (m_transferPool != nullPool);
        assert (m_presentPool != nullPool);
    }
    body
    {
        if (m_renderPool.createCommandPool (m_device, m_device.renderQueueFamily) != VK_SUCCESS)
        {
            assert (false, "Uh oh, the renderer isn't flexible enough for this yet!");
        }
        m_computePool   = createCommandPoolIfPossible (m_device.hasDedicatedComputeFamily, m_device.computeQueueFamily);
        m_transferPool  = createCommandPoolIfPossible (m_device.hasDedicatedTransferFamily, m_device.transferQueueFamily);
        m_presentPool   = createCommandPoolIfPossible (m_device.hasDedicatedPresentFamily, m_device.presentQueueFamily);
    }

    /// If the device doesn't have a dedicated queue family as specified by the given parameter, then the render family
    /// is assumed to be general purpose and that command pool will be used as a fallback.
    nothrow @nogc
    private VkCommandPool createCommandPoolIfPossible (in bool hasDedicatedQueueFamily, in uint32_t queueFamily)
    {
        if (hasDedicatedQueueFamily)
        {
            VkCommandPool pool = nullPool;
            if (pool.createCommandPool (m_device, queueFamily) == VK_SUCCESS)
            {
                return pool;
            }
            else if (pool != nullPool)
            {
                m_device.vkDestroyCommandPool (pool, null);
            }
        }
        
        return m_renderPool;
    }

    /// Destroys all unique command pools, ensuring duplicates aren't deleted.
    private void destroyCommandPools() nothrow @nogc
    {
        VkCommandPool[4] pools = [m_renderPool, m_computePool, m_transferPool, m_presentPool];
        pools[0..$].sort()
                   .uniq()
                   .filter!(a => a != nullPool)
                   .each!(p => m_device.vkDestroyCommandPool (p, null));

        m_renderPool = m_computePool = m_transferPool = m_presentPool = nullPool;
    }
}