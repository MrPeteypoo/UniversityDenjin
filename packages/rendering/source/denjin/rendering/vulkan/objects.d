/**
    Utility functions for the creation/use of different basic Vulkan objects.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: Copyright © 2017, Simon Peter Campbell
    License: MIT
*/
module denjin.rendering.vulkan.objects;

// Phobos.
import std.file             : exists, isFile, read;
import std.range.primitives : ElementType, isRandomAccessRange;
import std.traits           : Unqual;
import std.typecons         : Flag, Yes, No;

// Engine.
import denjin.rendering.vulkan.device : Device;
import denjin.rendering.vulkan.nulls;

// External.
import erupted.types;

/// Allocates command buffers from the given memory pool.
VkResult allocateCommandBuffers(Range)(auto ref Range output, ref Device device, VkCommandPool pool, 
                                       in Flag!"arePrimaryBuffers" arePrimaryBuffers = Yes.arePrimaryBuffers)
    if (isRandomAccessRange!Range)
in
{
    assert (device != nullDevice);
    assert (pool != nullPool);
}
body
{
    VkCommandBufferAllocateInfo info = 
    {
        sType:              VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        pNext:              null,
        commandPool:        pool,
        level:              arePrimaryBuffers ? VK_COMMAND_BUFFER_LEVEL_PRIMARY : VK_COMMAND_BUFFER_LEVEL_SECONDARY,
        commandBufferCount: cast (uint32_t) output.length
    };
    return device.vkAllocateCommandBuffers (&info, &output[0]);
}

/// Creates a command pool with the given flags for the given queue family.
nothrow @nogc
VkResult createCommandPool (out VkCommandPool pool, ref Device device, in uint32_t queueFamilyIndex,
                            in VkCommandPoolCreateFlags flags = 0, in VkAllocationCallbacks* callbacks = null)
in
{
    assert (device != nullDevice);
}
body
{
    immutable VkCommandPoolCreateInfo info =
    {
        sType:              VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        pNext:              null,
        flags:              flags,
        queueFamilyIndex:   queueFamilyIndex
    };

    return device.vkCreateCommandPool (&info, callbacks, &pool);
}

/// Creates a fence with the given parameters.
VkResult createFence (out VkFence fence, ref Device device, in VkFenceCreateFlags flags = 0, 
                      in VkAllocationCallbacks* callbacks = null) nothrow @nogc
in
{
    assert (device != nullDevice);
}
body
{
    immutable VkFenceCreateInfo info =
    {
        sType:  VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        pNext:  null,
        flags:  flags
    };

    return device.vkCreateFence (&info, callbacks, &fence);
}

/// Creates a render pass with the given parameters.
VkResult createRenderPass (Range1, Range2, Range3) 
                          (out VkRenderPass renderPass, ref Device device, auto ref Range1 attachmentDescriptions,
                           auto ref Range2 subpassDescriptions, auto ref Range3 subpassDependencies,
                           in VkAllocationCallbacks* callbacks = null)
    if (isRandomAccessRange!Range1 && is (Unqual!(ElementType!Range1) == VkAttachmentDescription) &&
        isRandomAccessRange!Range2 && is (Unqual!(ElementType!Range2) == VkSubpassDescription) &&
        isRandomAccessRange!Range3 && is (Unqual!(ElementType!Range3) == VkSubpassDependency))
{
    VkRenderPassCreateInfo info =
    {
        sType:              VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
        pNext:              null,
        flags:              0,
        attachmentCount:    cast (uint32_t) attachmentDescriptions.length,
        pAttachments:       attachmentDescriptions.length > 0 ? &attachmentDescriptions[0] : null,
        subpassCount:       cast (uint32_t) subpassDescriptions.length,
        pSubpasses:         subpassDescriptions.length > 0 ? &subpassDescriptions[0] : null,
        dependencyCount:    cast (uint32_t) subpassDependencies.length,
        pDependencies:      subpassDependencies.length > 0 ? &subpassDependencies[0] : null
    };

    return device.vkCreateRenderPass (&info, callbacks, &renderPass);
}

/// Creates a semaphore with the given parameters.
VkResult createSemaphore (out VkSemaphore semaphore, ref Device device, 
                          in VkAllocationCallbacks* callbacks = null) nothrow @nogc
in
{
    assert (device != nullDevice);
}
body
{
    // Creation information for semaphores are pretty irrelevant.
    immutable VkSemaphoreCreateInfo info =
    {
        sType: VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
        pNext: null,
        flags: 0
    };

    return device.vkCreateSemaphore (&info, callbacks, &semaphore);
}

/// Creates a shader module from the file at the given location.
VkResult createShaderModule (out VkShaderModule shader, ref Device device, in string fileLocation,
                             in VkAllocationCallbacks* callbacks = null) nothrow
in
{
    assert (device != nullDevice);
    assert (fileLocation.exists);
    assert (fileLocation.isFile);
}
body
{
    try
    {
        if (fileLocation.exists && fileLocation.isFile)
        {
            // Firstly we must read the file.
            const auto spirv = read (fileLocation);
        
            // Secondly, the size of the data must be a multiple of four.
            if (spirv.length % 4 == 0)
            {
                VkShaderModuleCreateInfo info =
                {
                    sType:      VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
                    pNext:      null,
                    flags:      0,
                    codeSize:   spirv.length,
                    pCode:      cast (const(uint32_t*)) spirv.ptr
                };

                return device.vkCreateShaderModule (&info, callbacks, &shader);
            }
        }
    }
    catch (Throwable)
    {
    }

    return VK_ERROR_INITIALIZATION_FAILED;
}