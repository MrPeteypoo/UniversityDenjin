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

class Renderer : IRenderer
{
    private 
    {
        Device      m_device;       /// The logical device containing device-level Functionality.
        Swapchain   m_swapchain;    /// Manages the display mode and displayable images available to the renderer.
    }

    invariant
    {
        assert (m_device != nullHandle!VkDevice);
        assert (m_swapchain != nullHandle!VkSwapchainKHR);
    }

    this (Device device, Swapchain swapchain)
    {
        // Take ownership of the resources.
        m_device    = move (device);
        m_swapchain = move (swapchain);

        // We need a swapchain to start rendering.
        m_swapchain.create (m_device, null, VSync.TripleBuffering);
    }
}