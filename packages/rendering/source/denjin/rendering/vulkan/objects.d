/**
    Utility functions for the creation/use of different basic Vulkan objects.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: MIT
*/
module denjin.rendering.vulkan.objects;

// Engine.
import denjin.rendering.vulkan.device : Device;

// External.
import erupted.types;

/// Creates a command pool with the given flags for the given queue family.
nothrow @nogc
VkResult createCommandPool (out VkCommandPool pool, ref Device device, in uint32_t queueFamilyIndex,
                            in VkCommandPoolCreateFlags flags = 0, in VkAllocationCallbacks* callbacks = null)
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
nothrow @nogc
VkResult createSemaphore (out VkSemaphore semaphore, ref Device device, 
                          in VkAllocationCallbacks* callbacks = null)
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