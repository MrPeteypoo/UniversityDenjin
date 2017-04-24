/**
    Contains a 3D renderer implementing the Vulkan API.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: MIT
*/
module denjin.rendering.vulkan.renderer;

// Phobos.
import std.algorithm.mutation : move;

// Engine.
import denjin.rendering.interfaces          : IRenderer;
import denjin.rendering.vulkan.device       : Device;
import denjin.rendering.vulkan.misc         : nullHandle;
import denjin.rendering.vulkan.swapchain    : Swapchain, VSync;

// External.
import erupted.types;

/// A basic 3D renderer implemented using Vulkan. A Vulkan instance must be created and loaded before using the
/// renderer. The current implementation also requires a logical device and swapchain be generated externally.
final class RendererVulkan : IRenderer
{
    private 
    {
        Device      m_device;       /// The logical device containing device-level Functionality.
        Swapchain   m_swapchain;    /// Manages the display mode and displayable images available to the renderer.
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
    }

    ~this() nothrow
    {
        clear();
    }

    public override void clear() nothrow
    {
        if (m_device != nullHandle!VkDevice)
        {
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
}