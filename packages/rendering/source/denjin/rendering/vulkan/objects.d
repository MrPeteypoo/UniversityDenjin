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
import denjin.rendering.vulkan.device   : Device;
import denjin.rendering.vulkan.misc     : memoryTypeIndex, safelyDestroyVK;
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

/**
    Creates a buffer with the given characteristics.

    Params:
        buffer          = Where to write the created buffer handle.
        memory          = Where to write the allocated memory handle.
        device          = The device to use to create the buffer with.
        properties      = The properties of the physical device containing the allocated memory.
        size            = The desired size of the buffer, extra memory may be allocated due to alignment requirements.
        bufferUsage     = Describes how the buffer will be used.
        memoryUsage     = Describes how the memory will be used.
        callbacks       = Callback functions which should be used when allocating memory.
        sharingMode     = How the buffer will be shared by queue families.
        queueIndices    = If the sharing mode isn't exclusive the queue families that will access the resource must be specified here.

    Returns: 
        The result of the buffer creation and memory allocation. VK_ERROR_FORMAT_NOT_SUPPORTED if the desired memory 
        usage isn't supported.
*/
nothrow
VkResult createBuffer (out VkBuffer buffer, out VkDeviceMemory memory, ref Device device, 
                       in VkPhysicalDeviceMemoryProperties properties, in VkDeviceSize size, 
                       in VkBufferUsageFlags bufferUsage, in VkMemoryPropertyFlags memoryUsage, 
                       in VkAllocationCallbacks* callbacks = null, 
                       in VkSharingMode sharingMode = VK_SHARING_MODE_EXCLUSIVE, in uint32_t[] queueIndices = [])
in
{
    assert (device != nullDevice);
}
body
{
    // Firstly prepare how we'll destroy the objects if something goes wrong.
    enum destroyBuffer = "buffer.safelyDestroyVK (device.vkDestroyBuffer, device, buffer, callbacks);";
    enum destroyMemory = "memory.safelyDestroyVK (device.vkFreeMemory, device, memory, callbacks);";

    // Create the buffer.
    const VkBufferCreateInfo bufferInfo =
    {
        sType:                  VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        pNext:                  null,
        flags:                  0,
        size:                   size,
        usage:                  bufferUsage,
        sharingMode:            sharingMode,
        queueFamilyIndexCount:  cast (uint32_t) queueIndices.length,
        pQueueFamilyIndices:    queueIndices.ptr
    };

    immutable bufferResult = device.vkCreateBuffer (&bufferInfo, callbacks, &buffer);
    if (bufferResult != VK_SUCCESS) return bufferResult;

    // Next we allocate memory for the buffer.
    VkMemoryRequirements requirements = void;
    device.vkGetBufferMemoryRequirements (buffer, &requirements);

    immutable VkMemoryAllocateInfo memoryInfo =
    {
        sType:              VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        pNext:              null,
        allocationSize:     requirements.size,
        memoryTypeIndex:    properties.memoryTypeIndex (requirements.memoryTypeBits, memoryUsage)
    };
    if (memoryInfo.memoryTypeIndex == uint32_t.max)
    {
        mixin (destroyBuffer);
        return VK_ERROR_FORMAT_NOT_SUPPORTED;
    }

    immutable allocateResult = device.vkAllocateMemory (&memoryInfo, callbacks, &memory);
    if (allocateResult != VK_SUCCESS)
    {
        mixin (destroyBuffer);
        return allocateResult;
    }

    // Finally bind the memory to the buffer.
    immutable bindResult = device.vkBindBufferMemory (buffer, memory, 0);
    if (bindResult != VK_SUCCESS)
    {
        mixin (destroyBuffer);
        mixin (destroyMemory);
    }
    return bindResult;
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

/// Creates a descriptor set layout with the given flags.
nothrow @nogc
VkResult createDescLayout (out VkDescriptorSetLayout layout, ref Device device, 
                           in VkDescriptorSetLayoutBinding[] bindings, in VkAllocationCallbacks* callbacks = null)
in
{
    assert (device != nullDevice);
}
body
{
    const VkDescriptorSetLayoutCreateInfo info = 
    {
        sType:          VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        pNext:          null,
        flags:          0,
        bindingCount:   cast (uint32_t) bindings.length,
        pBindings:      bindings.ptr
    };
    return device.vkCreateDescriptorSetLayout (&info, callbacks, &layout);
}

/// Creates a descriptor pool, allowing for the necessary descriptor sets to be allocated.
nothrow @nogc
VkResult createDescPool (out VkDescriptorPool pool, ref Device device, in VkDescriptorType type, 
                         in uint32_t descriptorCount, in VkAllocationCallbacks* callbacks = null)
in
{
    assert (device != nullDevice);
}
body
{
    immutable VkDescriptorPoolSize size =
    {
        type:               type,
        descriptorCount:    descriptorCount
    };

    immutable VkDescriptorPoolCreateInfo info = 
    {
        sType:          VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        pNext:          null,
        flags:          0,
        maxSets:        descriptorCount,
        poolSizeCount:  1,
        pPoolSizes:     &size
    };
    return device.vkCreateDescriptorPool (&info, callbacks, &pool);
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

/**
    Similar to createBuffer. This creates a buffer dedicated to transferring data from the CPU to the GPU. The 
    resulting memory can be mapped and used as a transfer source into device-local memory.
*/
VkResult createStagingBuffer (out VkBuffer buffer, out VkDeviceMemory memory, ref Device device, 
                              in ref VkPhysicalDeviceMemoryProperties properties, in VkDeviceSize size,
                              in VkAllocationCallbacks* callbacks = null) nothrow
{
    enum bufferUsage = VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
    enum memoryUsage = VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT;
    return createBuffer (buffer, memory, device, properties, size, bufferUsage, memoryUsage, callbacks);
}