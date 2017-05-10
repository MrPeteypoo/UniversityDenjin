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
import denjin.rendering.vulkan.misc     : enforceSuccess, memoryTypeIndex, safelyDestroyVK;
import denjin.rendering.vulkan.nulls    : nullBuffer, nullDescLayout, nullDescPool, nullDevice, nullMemory;

import denjin.rendering.vulkan.internals.types;

// External.
import erupted.types;

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

    VkDescriptorSet[] sceneSets;    /// Descriptor sets for the scene data for each virtual frame.
    VkDescriptorSet[] dLightSets;   /// Descriptor sets for the directional light data for each virtual frame.
    VkDescriptorSet[] pLightSets;   /// Descriptor sets for the point light data for each virtual frame.
    VkDescriptorSet[] sLightSets;   /// Descriptor sets for the spotlight data for each virtual frame.

    VkBuffer                buffer  = nullBuffer;       /// The handle for the uniform buffer.
    VkDeviceMemory          memory  = nullMemory;       /// The allocated memory for the uniform buffer.
    VkDescriptorSetLayout   layout  = nullDescLayout;   /// The descriptor set layout, as used in pipeline creation.
    VkDescriptorPool        pool    = nullDescPool;     /// The descriptor pool from which descriptor sets are created.

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
        buffer.safelyDestroyVK (device.vkDestroyBuffer, device, buffer, callbacks);
        memory.safelyDestroyVK (device.vkFreeMemory, device, memory, callbacks);
        layout.safelyDestroyVK (device.vkDestroyDescriptorSetLayout, device, layout, callbacks);
        pool.safelyDestroyVK (device.vkDestroyDescriptorPool, device, pool, callbacks);
        sceneSets.length    = 0;
        dLightSets.length   = 0;
        pLightSets.length   = 0;
        sLightSets.length   = 0;
    }

    /// Creates and allocates memory for the buffer object itself.
    private void createBuffer (ref Device device, in ref VkPhysicalDeviceLimits limits, 
                               in ref VkPhysicalDeviceMemoryProperties memProps, 
                               in uint32_t virtualFrames, in VkAllocationCallbacks* callbacks)
    {
        // Firstly we must create the buffer.
        immutable VkBufferCreateInfo bufferInfo = 
        {
            sType:                  VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            pNext:                  null,
            flags:                  0,
            size:                   bufferSize (limits) * virtualFrames,
            usage:                  VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
            sharingMode:            VK_SHARING_MODE_EXCLUSIVE,
            queueFamilyIndexCount:  0,
            pQueueFamilyIndices:    null
        };
        device.vkCreateBuffer (&bufferInfo, callbacks, &buffer).enforceSuccess;

        // Next we allocate memory for the buffer.
        VkMemoryRequirements requirements = void;
        device.vkGetBufferMemoryRequirements (buffer, &requirements);

        immutable VkMemoryAllocateInfo memoryInfo =
        {
            sType:              VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
            pNext:              null,
            allocationSize:     requirements.size,
            memoryTypeIndex:    memProps.memoryTypeIndex (requirements.memoryTypeBits, 
                                                          VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT |
                                                          VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)
        };
        device.vkAllocateMemory (&memoryInfo, callbacks, &memory).enforceSuccess;

        // Finally we bind the buffer and memory together.
        device.vkBindBufferMemory (buffer, memory, 0).enforceSuccess;
    }

    /// Creates the descriptor set layout so that the uniform buffer can be used by pipelines.
    private void createLayout (ref Device device, in VkAllocationCallbacks* callbacks)
    {
        immutable VkDescriptorSetLayoutCreateInfo info = 
        {
            sType:          VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
            pNext:          null,
            flags:          0,
            bindingCount:   bindings.length,
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
        auto layouts = layout.repeat.takeExactly(virtualFrames).array;
        VkDescriptorSetAllocateInfo info =
        {
            sType:              VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
            pNext:              null,
            descriptorPool:     pool,
            descriptorSetCount: virtualFrames,
            pSetLayouts:        layouts.ptr
        };

        // Each uniform block will have each set configured here.
        enum configureSets = (ref VkDescriptorSet[] setArray, in uint32_t binding, 
                              in VkDeviceSize virtualFrameSize, in VkDeviceSize offset, in VkDeviceSize range)
        {
            // Firstly we must allocate the sets.
            setArray.length = info.descriptorSetCount;
            device.vkAllocateDescriptorSets (&info, setArray.ptr).enforceSuccess;
            
            // For each set, set each descriptor to the correct offset and binding point.
            foreach (i, set; setArray)
            {
                const VkDescriptorBufferInfo bufferInfo = 
                {
                    buffer: buffer,
                    offset: cast (VkDeviceSize) (offset + virtualFrameSize * i),
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
            }
        };

        // Now we can configure each set.
        immutable bufferSize    = bufferSize (limits);
        immutable sceneOffset   = VkDeviceSize (0);
        immutable dLightOffset  = limits.alignSize!SceneBlock;
        immutable pLightOffset  = limits.alignSize!DLightBlock + dLightOffset;
        immutable sLightOffset  = limits.alignSize!PLightBlock + pLightOffset;

        configureSets (sceneSets, sceneBinding.binding, bufferSize, sceneOffset, limits.alignSize!SceneBlock);
        configureSets (dLightSets, dLightBinding.binding, bufferSize, dLightOffset, limits.alignSize!DLightBlock);
        configureSets (pLightSets, pLightBinding.binding, bufferSize, pLightOffset, limits.alignSize!PLightBlock);
        configureSets (sLightSets, sLightBinding.binding, bufferSize, sLightOffset, limits.alignSize!SLightBlock);
    }

    /// Calculates the total size needed for storing every uniform block whilst maintaining alignment requirements.
    private static VkDeviceSize bufferSize (in ref VkPhysicalDeviceLimits limits) pure nothrow @safe @nogc
    {
        return limits.alignSize!SceneBlock + 
               limits.alignSize!DLightBlock + 
               limits.alignSize!PLightBlock + 
               limits.alignSize!SLightBlock;
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