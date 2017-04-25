/**
    Utility functions for the creation/use of different basic Vulkan objects.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: MIT
*/
module denjin.rendering.vulkan.objects;

// Phobos.
import std.range.primitives : isRandomAccessRange;
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
    immutable VkCommandBufferAllocateInfo info = 
    {
        sType:              VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        pNext:              null,
        commandPool:        pool,
        level:              arePrimaryBuffers ? VK_COMMAND_BUFFER_LEVEL_PRIMARY : VK_COMMAND_BUFFER_LEVEL_SECONDARY,
        commandBufferCount: cast (uint32_t) output.length
    };
    return device.vkAllocateCommandBuffers (&info, &output.front());
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