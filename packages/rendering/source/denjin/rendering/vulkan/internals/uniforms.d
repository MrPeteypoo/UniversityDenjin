/**
    Manages uniform buffer objects, giving shaders access to frame-specific rendering data.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: Copyright © 2017, Simon Peter Campbell
    License: MIT
*/
module denjin.rendering.vulkan.internals.uniforms;

// Phobos.
import std.array    : array;
import std.range    : repeat, takeExactly;
import std.traits   : isPointer;

// Engine.
import denjin.rendering.vulkan.device   : Device;
import denjin.rendering.vulkan.misc     : enforceSuccess, safelyDestroyVK;
import denjin.rendering.vulkan.nulls    : nullBuffer, nullCMDBuffer, nullDescLayout, nullDescPool, nullDevice, nullMemory, nullSet;
import denjin.rendering.vulkan.objects  : createBuffer;

import denjin.rendering.vulkan.internals.types;

// External.
import erupted.types : uint32_t, VkAllocationCallbacks, VkBuffer, VkBufferCreateInfo, VkDescriptorBufferInfo, 
                       VkDescriptorPool, VkDescriptorPoolCreateInfo, VkDescriptorPoolSize, VkDescriptorSet,
                       VkDescriptorSetAllocateInfo, VkDescriptorSetLayout,  VkDescriptorSetLayoutBinding, 
                       VkDescriptorSetLayoutCreateInfo, VkDeviceMemory, VkDeviceSize, VkMemoryAllocateInfo, 
                       VkMemoryRequirements, VkPhysicalDeviceLimits, VkPhysicalDeviceMemoryProperties, 
                       VkWriteDescriptorSet,
                       VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, 
                       VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT, 
                       VK_SHADER_STAGE_ALL_GRAPHICS, VK_SHARING_MODE_EXCLUSIVE, VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO, 
                       VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO, VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO, 
                       VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO, VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, 
                       VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, VK_WHOLE_SIZE;

/// Creates, stores and destroys uniform buffer data which shaders can access.
struct Uniforms
{
    private
    {
        /// A template for specifying binding parameters quickly.
        enum VkDescriptorSetLayoutBinding binding (uint32_t index, uint32_t count = 1) =
        {
            binding:            index,
            descriptorType:     VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            descriptorCount:    count,
            stageFlags:         VK_SHADER_STAGE_ALL_GRAPHICS,
            pImmutableSamplers: null
        };

        enum sceneBinding   = binding!(0);  /// The binding information for scene data.
        enum dLightBinding  = binding!(1);  /// The binding information for directional light data.
        enum pLightBinding  = binding!(2);  /// The binding information for point light data.
        enum sLightBinding  = binding!(3);  /// The binding information for spotlight data.

        /// The uniform block bindings available to shaders.
        static immutable VkDescriptorSetLayoutBinding[4] bindings = 
        [
            sceneBinding, dLightBinding, pLightBinding, sLightBinding
        ];
    }

    SceneBlock*             sceneBlock      = null;             /// A mapping of the scene block for the current virtual frame.
    DLightBlock*            dLightBlock     = null;             /// A mapping of the directional light block for the current virtual frame.
    PLightBlock*            pLightBlock     = null;             /// A mapping of the point light block for the current virtual frame.
    SLightBlock*            sLightBlock     = null;             /// A mapping of the spotlight block for the current virtual frame.

    VkBuffer                buffer          = nullBuffer;       /// The handle for the uniform buffer.
    VkDeviceMemory          memory          = nullMemory;       /// The allocated memory for the uniform buffer.
    VkDescriptorSetLayout   layout          = nullDescLayout;   /// The descriptor set layout, as used in pipeline creation.
    VkDescriptorPool        pool            = nullDescPool;     /// The descriptor pool from which descriptor sets are created.
    void*                   mapping         = null;             /// A persistent mapping of the uniform buffer contents.
    VkDescriptorSet[]       sets;                               /// A collection of resources required for each virtual frame.

    VkDeviceSize            sceneOffset     = 0;                /// The offset into the uniform buffer where the scene data is stored.
    VkDeviceSize            dLightOffset    = 0;                /// The offset into the uniform buffer where the directional light data is stored.
    VkDeviceSize            pLightOffset    = 0;                /// The offset into the uniform buffer where the point light data is stored.
    VkDeviceSize            sLightOffset    = 0;                /// The offset into the uniform buffer where the spotlight data is stored.
    VkDeviceSize            bufferSize      = 0;                /// How large the uniform buffer is (excluding virtual frames).

    /// Creates the uniform buffer, and the descriptor sets required for each block.
    public void create (ref Device device, in ref VkPhysicalDeviceLimits limits, 
                        in ref VkPhysicalDeviceMemoryProperties memProps, 
                        in uint32_t virtualFrames, in VkAllocationCallbacks* callbacks = null)
    in
    {
        assert (device != nullDevice);
        assert (virtualFrames > 0);
        assert (buffer == nullBuffer);
        assert (memory == nullMemory);
        assert (layout == nullDescLayout);
        assert (pool == nullDescPool);
    }
    body
    {
        // Ensure we don't leak upon an error.
        scope (failure) clear (device, callbacks);
        createBuffer (device, limits, memProps, virtualFrames, callbacks);
        createLayout (device, callbacks);
        createPool (device, virtualFrames, callbacks);
        createSets (device, virtualFrames, limits);
    }

    /// Clears resources, freeing all objects and resetting to an uninitialised state.
    public void clear (ref Device device, in VkAllocationCallbacks* callbacks = null) nothrow
    in
    {
        assert (device != nullDevice);
    }
    body
    {
        if (mapping !is null && memory != nullMemory)
        {
            device.vkUnmapMemory (memory);
            mapping     = null;
            sceneBlock  = null;
            dLightBlock = null;
            pLightBlock = null;
            sLightBlock = null;
        }

        memory.safelyDestroyVK (device.vkFreeMemory, device, memory, callbacks);
        buffer.safelyDestroyVK (device.vkDestroyBuffer, device, buffer, callbacks);
        layout.safelyDestroyVK (device.vkDestroyDescriptorSetLayout, device, layout, callbacks);
        pool.safelyDestroyVK (device.vkDestroyDescriptorPool, device, pool, callbacks);

        sets.length = sceneOffset = dLightOffset = pLightOffset = sLightOffset = bufferSize = 0;
    }

    /// Updates the uniform block mappings based on the current frame index.
    public void updateMappings (in size_t frameIndex) pure nothrow @nogc
    {
        // Calculate the initial offset for the frame.
        immutable frameOffset = frameIndex * bufferSize;

        // Set the mappings accordingly.
        sceneBlock  = cast (SceneBlock*) (mapping + frameOffset + sceneOffset);
        dLightBlock = cast (DLightBlock*) (mapping + frameOffset + dLightOffset);
        pLightBlock = cast (PLightBlock*) (mapping + frameOffset + pLightOffset);
        sLightBlock = cast (SLightBlock*) (mapping + frameOffset + sLightOffset);
    }

    /// Creates and allocates memory for the buffer object itself.
    private void createBuffer (ref Device device, in ref VkPhysicalDeviceLimits limits, 
                               in ref VkPhysicalDeviceMemoryProperties memProps, 
                               in uint32_t virtualFrames, in VkAllocationCallbacks* callbacks)
    {
        bufferSize          = limits.bufferSize;
        immutable size      = bufferSize * virtualFrames;
        enum bufferUsage    = VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT;
        enum memoryUsage    = VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;

        buffer.createBuffer (memory, device, memProps, size, bufferUsage, memoryUsage, callbacks).enforceSuccess;
        device.vkMapMemory (memory, 0, VK_WHOLE_SIZE, 0, &mapping).enforceSuccess;
    }

    /// Creates the descriptor set layout so that the uniform buffer can be used by pipelines.
    private void createLayout (ref Device device, in VkAllocationCallbacks* callbacks)
    {
        immutable VkDescriptorSetLayoutCreateInfo info = 
        {
            sType:          VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
            pNext:          null,
            flags:          0,
            bindingCount:   cast (uint32_t) bindings.length,
            pBindings:      bindings.ptr
        };
        device.vkCreateDescriptorSetLayout (&info, callbacks, &layout).enforceSuccess;
    }

    /// Creates the descriptor pool, allowing for the necessary descriptor sets to be allocated.
    private void createPool (ref Device device, in uint32_t virtualFrames, in VkAllocationCallbacks* callbacks)
    {
        immutable VkDescriptorPoolSize poolSize =
        {
            type:               VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            descriptorCount:    cast (uint32_t) (bindings.length * virtualFrames)
        };

        immutable VkDescriptorPoolCreateInfo poolInfo = 
        {
            sType:          VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
            pNext:          null,
            flags:          0,
            maxSets:        poolSize.descriptorCount,
            poolSizeCount:  1,
            pPoolSizes:     &poolSize
        };
        device.vkCreateDescriptorPool (&poolInfo, callbacks, &pool).enforceSuccess;
    }

    /// Allocates and configures the descriptor sets for each uniform block.
    private void createSets (ref Device device, in uint32_t virtualFrames, in ref VkPhysicalDeviceLimits limits)
    {
        // We need to describe how the sets will be allocated.
        auto layouts = layout.repeat.takeExactly (virtualFrames).array;
        VkDescriptorSetAllocateInfo info =
        {
            sType:              VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
            pNext:              null,
            descriptorPool:     pool,
            descriptorSetCount: virtualFrames,
            pSetLayouts:        layouts.ptr
        };

        // Allocate the sets.
        sets.length = virtualFrames;
        device.vkAllocateDescriptorSets (&info, sets.ptr).enforceSuccess;

        // Each uniform block will have each set configured here.
        enum updateSet = (ref VkDescriptorSet set, in uint32_t binding, 
                          in VkDeviceSize offset, in VkDeviceSize range)
        {
            // Now we can update the binding of the buffer to the desired offset.
            const VkDescriptorBufferInfo bufferInfo = 
            {
                buffer: buffer,
                offset: offset,
                range:  range
            };
            const VkWriteDescriptorSet write =
            {
                sType:              VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                pNext:              null,
                dstSet:             set,
                dstBinding:         binding,
                dstArrayElement:    0,
                descriptorCount:    1,
                descriptorType:     VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                pImageInfo:         null,
                pBufferInfo:        &bufferInfo,       
                pTexelBufferView:   null
            };
            device.vkUpdateDescriptorSets (1, &write, 0, null);
        };

        // Now we can configure each set.
        immutable sceneSize     = limits.alignSize!SceneBlock;
        immutable dLightSize    = limits.alignSize!DLightBlock;
        immutable pLightSize    = limits.alignSize!PLightBlock;
        immutable sLightSize    = limits.alignSize!SLightBlock;

        sceneOffset     = VkDeviceSize (0);
        dLightOffset    = sceneSize;
        pLightOffset    = dLightOffset + dLightSize;
        sLightOffset    = pLightOffset + pLightSize;

        sets.length = virtualFrames;
        foreach (i, ref set; sets)
        {
            // Set each binding point for every set.
            immutable bufferOffset = cast (VkDeviceSize) (i * bufferSize);
            updateSet (set, sceneBinding.binding, bufferOffset + sceneOffset, sceneSize);
            updateSet (set, dLightBinding.binding, bufferOffset + dLightOffset, dLightSize);
            updateSet (set, pLightBinding.binding, bufferOffset + pLightOffset, pLightSize);
            updateSet (set, sLightBinding.binding, bufferOffset + sLightOffset, sLightSize);
        }
    }
}

/// The uniform block for general scene data.
struct SceneBlock
{
    align (4)   Mat4    projection;     /// The projection matrix used for the rendering of a frame.
    align (4)   Mat4    view;           /// The view matrix from the cameras perspective.
    align (16)  Vec3    cameraPosition; /// The position of the camera in world-space.
    align (16)  Vec3    ambientLight;   /// The ambient light intensity of the scene.
}

/// The uniform block for directional light data.
alias DLightBlock = UniformArray!(DirectionalLight, 50);

/// The uniform block for point light data.
alias PLightBlock = UniformArray!(PointLight, 50);

/// The uniform block for spotlight data.
alias SLightBlock = UniformArray!(Spotlight, 50);

/// Calculates the aligned size of a type based on the given device limits.
private VkDeviceSize alignSize(T)(in ref VkPhysicalDeviceLimits limits)
    if (!isPointer!T)
{
    // First we must know how large the type is.
    enum size = T.sizeof;

    // Now we must find out how many bytes of alignment are required.
    immutable alignment = limits.minUniformBufferOffsetAlignment;
    immutable required  = size % alignment;
    
    // Finally we must add remaining bytes.
    immutable aligned = required ? size + alignment - required : size;
    return cast (VkDeviceSize) aligned;
}

/// Calculates the total size needed for storing every uniform block whilst maintaining alignment requirements.
private static VkDeviceSize bufferSize (in ref VkPhysicalDeviceLimits limits) pure nothrow @safe @nogc
{
    return limits.alignSize!SceneBlock + 
           limits.alignSize!DLightBlock + 
           limits.alignSize!PLightBlock + 
           limits.alignSize!SLightBlock;
}