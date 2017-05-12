/**
    Handles the storage of vertex buffers and the loading of geometry data.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: Copyright © 2017, Simon Peter Campbell
    License: MIT
*/
module denjin.rendering.vulkan.internals.geometry;

// Phobos.
import std.algorithm    : max;
import std.range        : ElementType, isInputRange;
import std.traits       : isArray;

// Engine.
import denjin.misc.ids                          : MeshID;
import denjin.rendering.vulkan.device           : Device;
import denjin.rendering.vulkan.misc             : enforceSuccess, safelyDestroyVK;
import denjin.rendering.vulkan.nulls            : nullBuffer, nullCMDBuffer, nullDevice, nullFence, nullMemory;
import denjin.rendering.vulkan.objects          : createBuffer, createFence, createStagingBuffer;
import denjin.rendering.traits                  : isAssets, isMesh, isScene;
import denjin.rendering.vulkan.internals.types  : Mat4x3, Vec2, Vec3;

// External.
import erupted.types :  int32_t, uint32_t, uint64_t, VkAllocationCallbacks, VkBuffer, VkBufferCopy, 
                        VkBufferMemoryBarrier, VkCommandBuffer, VkCommandBufferBeginInfo, VkDeviceMemory, VkDeviceSize, 
                        VkFence, VkMappedMemoryRange, VkPhysicalDeviceMemoryProperties, VkSubmitInfo, 
                        VkVertexInputAttributeDescription, VkVertexInputBindingDescription, 
                        VK_ACCESS_MEMORY_WRITE_BIT, VK_ACCESS_VERTEX_ATTRIBUTE_READ_BIT, 
                        VK_BUFFER_USAGE_INDEX_BUFFER_BIT, VK_BUFFER_USAGE_TRANSFER_DST_BIT, 
                        VK_BUFFER_USAGE_VERTEX_BUFFER_BIT, VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT, VK_FALSE, 
                        VK_FORMAT_R32G32_SFLOAT, VK_FORMAT_R32G32B32_SFLOAT, VK_FORMAT_R32G32B32_SINT, 
                        VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT, 
                        VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT, 
                        VK_PIPELINE_STAGE_TRANSFER_BIT, VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER, 
                        VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO, VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE, 
                        VK_STRUCTURE_TYPE_SUBMIT_INFO, VK_VERTEX_INPUT_RATE_VERTEX, VK_VERTEX_INPUT_RATE_INSTANCE, 
                        VK_WHOLE_SIZE;

/// Loads, stores and manages geometry data. This includes vertex, index, material and transform data.
/// See_Also: isAssets, isScene.
struct GeometryT (Assets, Scene)
    if (isAssets!Assets && isScene!Scene)
{
    Mesh[]              meshes;                             /// Every loaded mesh in the scene.
    VkBuffer            staticBuffer        = nullBuffer;   /// The vertex buffer containing static data such as vertices and indices.
    VkBuffer            dynamicBuffer       = nullBuffer;   /// The vertex buffer containing dynamic data such as instancing attributes.
    VkDeviceSize        vertexOffset        = 0;            /// The offset into the static buffer for mesh vertices.
    VkDeviceSize        indexOffset         = 0;            /// The offset into the static buffer for mesh indices.
    VkDeviceSize        dynamicOffset       = 0;            /// The offset into the dynamic buffer for instance data on the current frame.
    VkDeviceSize        staticSize          = 0;            /// The size of the static data buffer.
    VkDeviceSize        dynamicSize         = 0;            /// The size of the dynamic data buffer (excluding virtual frames).
    void*               dynamicMapping      = null;         /// A persistent mapping of the dynamic buffer.
    InstanceAttributes* instanceAttributes  = null;         /// A mapping of the instance attibutes for the current virtual frame.
    VkDeviceMemory      staticMemory        = nullMemory;   /// The device memory bound to the static buffer.
    VkDeviceMemory      dynamicMemory       = nullMemory;   /// The device memory bound to the dynamic buffer.

    /**
        Loads all meshes contained in the given assets object. Upon doing so, the given scene object will be analysed
        and vertex buffers will be prepared for rendering the entire scene. No static instance optimisation will be 
        performed, the total instances will just be used to ensure that enough data is stored to draw every object in
        the scene.
    */
    public void create (ref Device device, in ref VkPhysicalDeviceMemoryProperties memProps, VkCommandBuffer transfer, 
                        in ref Assets assets, in ref Scene scene, in uint32_t virtualFrames, 
                        in VkAllocationCallbacks* callbacks = null)
    in
    {
        assert (device != nullDevice);
        assert (transfer != nullCMDBuffer);
        assert (virtualFrames > 0);
        assert (staticBuffer == nullBuffer);
        assert (dynamicBuffer == nullBuffer);
        assert (staticMemory == nullMemory);
        assert (dynamicMemory == nullMemory);
    }
    body
    {
        scope (failure) clear (device, callbacks);
        allocateStaticBuffers (device, memProps, assets, callbacks);
        fillStaticBuffer (device, memProps, transfer, assets, callbacks);
        allocateDynamicBuffers (device, memProps, scene, virtualFrames, callbacks);
    }

    /// Deallocates resources, deleting all stored buffers and meshes.
    public void clear (ref Device device, in VkAllocationCallbacks* callbacks = null) nothrow
    in
    {
        assert (device != nullDevice);
    }
    body
    {
        if (dynamicMapping !is null && dynamicMemory != nullMemory)
        {
            device.vkUnmapMemory (dynamicMemory);
            dynamicMapping = null;
        }
        meshes.length = 0;
        staticMemory.safelyDestroyVK (device.vkFreeMemory, device, staticMemory, callbacks);
        dynamicMemory.safelyDestroyVK (device.vkFreeMemory, device, dynamicMemory, callbacks);
        staticBuffer.safelyDestroyVK (device.vkDestroyBuffer, device, staticBuffer, callbacks);
        dynamicBuffer.safelyDestroyVK (device.vkDestroyBuffer, device, dynamicBuffer, callbacks);

        vertexOffset = indexOffset = dynamicOffset = staticSize = dynamicSize = 0;
    }

    /// Updates the dynamic buffer mapping and offsets to those required for the given frame index.
    public void updateMappings (size_t frameIndex) pure nothrow @nogc 
    in
    {
        assert (dynamicMapping !is null);
    }
    body
    {
        dynamicOffset       = cast (VkDeviceSize) (frameIndex * dynamicSize);
        instanceAttributes  = cast (InstanceAttributes*) (dynamicMapping + dynamicSize * frameIndex);
    }

    /// Analyses the given assets, determining how much memory is required to store meshes and creates the buffer. 
    private void allocateStaticBuffers (ref Device device, in ref VkPhysicalDeviceMemoryProperties memProps, 
                                        in ref Assets assets, in VkAllocationCallbacks* callbacks)
    {
        // Start by finding out how much memory will need to be allocated.
        size_t vertexCount = void, indexCount = void;
        assets.meshes.countVerticesAndIndices (vertexCount, indexCount);

        vertexOffset    = 0;
        indexOffset     = cast (VkDeviceSize) (vertexCount * Vertex.sizeof);
        staticSize      = cast (VkDeviceSize) (indexOffset + indexCount * uint32_t.sizeof);

        // Now we can create the buffer and memory.
        enum bufferUse  = VK_BUFFER_USAGE_VERTEX_BUFFER_BIT | VK_BUFFER_USAGE_INDEX_BUFFER_BIT | 
                          VK_BUFFER_USAGE_TRANSFER_DST_BIT;
        enum memoryUse  = VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT;
        staticBuffer.createBuffer (staticMemory, device, memProps, staticSize, bufferUse, memoryUse, callbacks).enforceSuccess;
    }

    /// Generates GPU-storable meshes and transfers them to the GPU, ready for usage by a scene.
    private void fillStaticBuffer (ref Device device, in ref VkPhysicalDeviceMemoryProperties memProps, 
                                   VkCommandBuffer transfer, in ref Assets assets, in VkAllocationCallbacks* callbacks)
    {
        // We'll need a staging buffer to transfer the mesh data from.
        VkBuffer hostBuffer         = void;
        VkDeviceMemory hostMemory   = void;
        hostBuffer.createStagingBuffer (hostMemory, device, memProps, staticSize, callbacks).enforceSuccess;

        // Ensure we clean up after ourselves.
        scope (exit) device.vkFreeMemory (hostMemory, callbacks);
        scope (exit) device.vkDestroyBuffer (hostBuffer, callbacks);

        // Map the buffer, ready for writing.
        void* mapping = void;
        device.vkMapMemory (hostMemory, 0, VK_WHOLE_SIZE, 0, &mapping).enforceSuccess;
        scope (failure) device.vkUnmapMemory (hostMemory);

        // Now we can write the mesh data to the host-visible memory.
        meshes.fillMeshData (cast (Vertex*) (mapping + vertexOffset), 
                             cast (uint32_t*) (mapping + indexOffset), 
                             assets.meshes);

        const VkMappedMemoryRange flush =
        {
            sType:      VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE,
            pNext:      null,
            memory:     hostMemory,
            offset:     0,
            size:       VK_WHOLE_SIZE
        };
        device.vkFlushMappedMemoryRanges (1, &flush).enforceSuccess;
        device.vkUnmapMemory (hostMemory);

        // Finally we can transfer the data from the staging buffer to the static buffer.
        immutable VkCommandBufferBeginInfo beginInfo = 
        {
            sType:              VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            pNext:              null,
            flags:              VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
            pInheritanceInfo:   null
        };
        immutable VkBufferCopy copyInfo =
        {
            srcOffset:  0,
            dstOffset:  0,
            size:       staticSize
        };
        const VkBufferMemoryBarrier barrier = 
        {
            sType:                  VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER,
            pNext:                  null,
            srcAccessMask:          VK_ACCESS_MEMORY_WRITE_BIT,
            dstAccessMask:          VK_ACCESS_VERTEX_ATTRIBUTE_READ_BIT,
            srcQueueFamilyIndex:    device.transferQueueFamily,
            dstQueueFamilyIndex:    device.renderQueueFamily,
            buffer:                 staticBuffer,
            offset:                 0,
            size:                   VK_WHOLE_SIZE
        };

        device.vkBeginCommandBuffer (transfer, &beginInfo);
        device.vkCmdCopyBuffer (transfer, hostBuffer, staticBuffer, 1, &copyInfo);
        device.vkCmdPipelineBarrier (transfer, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT,
                                     0, 0, null, 1, &barrier, 0, null);
        device.vkEndCommandBuffer (transfer);

        // Now submit the commands and wait for the device to finish transferring data.
        const VkSubmitInfo submitInfo = 
        {
            sType:                  VK_STRUCTURE_TYPE_SUBMIT_INFO,
            pNext:                  null,
            waitSemaphoreCount:     0,
            pWaitSemaphores:        null,
            pWaitDstStageMask:      null,
            commandBufferCount:     1,
            pCommandBuffers:        &transfer,
            signalSemaphoreCount:   0,
            pSignalSemaphores:      null
        };
        VkFence fence = void;
        fence.createFence (device, 0).enforceSuccess;
        scope (exit) device.vkDestroyFence (fence, null);
        device.vkQueueSubmit (device.transferQueue, 1, &submitInfo, fence).enforceSuccess;
        device.vkWaitForFences (1, &fence, VK_FALSE, uint64_t.max).enforceSuccess;
    }

    /// Determines how many instances are in the given scene and allocates enough memory for all instances.
    private void allocateDynamicBuffers (ref Device device, in ref VkPhysicalDeviceMemoryProperties memProps, 
                                         in ref Scene scene, in uint32_t virtualFrames, 
                                         in VkAllocationCallbacks* callbacks)
    {
        // Calculate how much memory we need.
        dynamicSize         = cast (VkDeviceSize) (scene.countInstances (meshes) * InstanceAttributes.sizeof);
        immutable totalSize = dynamicSize * virtualFrames;

        // The buffers should be mappable so we can modify the data each frame.
        enum bufferUse  = VK_BUFFER_USAGE_VERTEX_BUFFER_BIT;
        enum memoryUse  = VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;
        dynamicBuffer.createBuffer (dynamicMemory, device, memProps, totalSize, bufferUse, memoryUse, callbacks)
                     .enforceSuccess;

        // Now we can map the buffer.
        device.vkMapMemory (dynamicMemory, 0, VK_WHOLE_SIZE, 0, &dynamicMapping).enforceSuccess;
    }
}

/// Contains the data required to render a mesh.
struct Mesh
{
    MeshID      id;             /// The unique ID of the mesh.
    uint32_t    indexCount;     /// How many element indices construct the mesh.
    uint32_t    firstIndex;     /// An offset into the index buffer where the indices for the mesh start.
    uint32_t    vertexOffset;   /// an offset into the vertex buffer where the first vertex can be found.
}

/// Contains the vertex input binding and attribute descriptions.
struct VertexAttributes
{
    /// A collection of binding descriptions for geometric meshes.
    static immutable VkVertexInputBindingDescription[2] bindings = 
    [
        vertices, instances
    ];

    /// A collection of vertex input attributes.
    static immutable VkVertexInputAttributeDescription[9] attributes = 
    [
        position, normal, tangent, uv, material, transform1, transform2, transform3, transform4
    ];

    /// The binding point and description of mesh vertices.
    enum VkVertexInputBindingDescription vertices =
    {
        binding:    0,
        stride:     Vertex.sizeof,
        inputRate:  VK_VERTEX_INPUT_RATE_VERTEX
    };

    /// The binding point and description of instance materials and transforms.
    enum VkVertexInputBindingDescription instances = 
    {
        binding:    1,
        stride:     InstanceAttributes.sizeof,
        inputRate:  VK_VERTEX_INPUT_RATE_INSTANCE
    };

    /// Describes how the position attribute is stored and located.
    enum VkVertexInputAttributeDescription position = 
    {
        location:   0,
        binding:    vertices.binding,
        format:     VK_FORMAT_R32G32B32_SFLOAT,
        offset:     Vertex.position.offsetof
    };

    /// Describes how the normal attribute is stored and located.
    enum VkVertexInputAttributeDescription normal = 
    {
        location:   1,
        binding:    vertices.binding,
        format:     VK_FORMAT_R32G32B32_SFLOAT,
        offset:     Vertex.normal.offsetof
    };

    /// Describes how the tangent attribute is stored and located.
    enum VkVertexInputAttributeDescription tangent = 
    {
        location:   2,
        binding:    vertices.binding,
        format:     VK_FORMAT_R32G32B32_SFLOAT,
        offset:     Vertex.tangent.offsetof
    };

    /// Describes how the uv attribute is stored and located.
    enum VkVertexInputAttributeDescription uv = 
    {
        location:   3,
        binding:    vertices.binding,
        format:     VK_FORMAT_R32G32_SFLOAT,
        offset:     Vertex.uv.offsetof
    };

    /// Describes how the material attribute is stored and located.
    enum VkVertexInputAttributeDescription material = 
    {
        location:   4,
        binding:    instances.binding,
        format:     VK_FORMAT_R32G32B32_SINT,
        offset:     InstanceAttributes.material.offsetof
    };

    /// Describes how the first transform attribute is stored and located.
    enum VkVertexInputAttributeDescription transform1 = 
    {
        location:   5,
        binding:    instances.binding,
        format:     VK_FORMAT_R32G32B32_SFLOAT,
        offset:     InstanceAttributes.transform.offsetof
    };

    /// Describes how the second transform attribute is stored and located.
    enum VkVertexInputAttributeDescription transform2 = 
    {
        location:   6,
        binding:    instances.binding,
        format:     VK_FORMAT_R32G32B32_SFLOAT,
        offset:     InstanceAttributes.transform.offsetof + Vec3.sizeof
    };

    /// Describes how the third transform attribute is stored and located.
    enum VkVertexInputAttributeDescription transform3 = 
    {
        location:   7,
        binding:    instances.binding,
        format:     VK_FORMAT_R32G32B32_SFLOAT,
        offset:     InstanceAttributes.transform.offsetof + Vec3.sizeof * 2
    };

    /// Describes how the fourth transform attribute is stored and located.
    enum VkVertexInputAttributeDescription transform4 = 
    {
        location:   8,
        binding:    instances.binding,
        format:     VK_FORMAT_R32G32B32_SFLOAT,
        offset:     InstanceAttributes.transform.offsetof + Vec3.sizeof * 3
    };
}

/// Dynamic vertex attributes which are required to render an instance.
align (1) struct InstanceAttributes
{
    MaterialIndices material;   /// Contains the index of texture maps for the material.
    ModelTransform  transform;  /// Contains the model transform of the instance.
}
///
pure nothrow @safe @nogc unittest
{
    static assert (InstanceAttributes.material.offsetof     == 0);
    static assert (InstanceAttributes.transform.offsetof    == 12);

    static assert (InstanceAttributes.sizeof == 60);
}

/// A vertex as it is stored inside a vertex buffer.
align (1) struct Vertex
{
    Vec3    position;   /// The position of the vertex in model-space.
    Vec3    normal;     /// The surface normal of the vertex.
    Vec3    tangent;    /// The normal tangent of the vertex.
    Vec2    uv;         /// The UV co-ordinates of the vertex.
}
///
pure nothrow @safe @nogc unittest
{
    static assert (Vertex.position.offsetof == 0);
    static assert (Vertex.normal.offsetof   == 12);
    static assert (Vertex.tangent.offsetof  == 24);
    static assert (Vertex.uv.offsetof       == 36);

    static assert (Vertex.sizeof == 44);
    static assert (Vertex.sizeof % uint32_t.sizeof == 0);
}

/// A group of texture indices as they are stored inside a vertex buffer.
align (1) struct MaterialIndices
{
    int32_t physics = -1;   /// The index of a physics map to use.
    int32_t albedo  = -1;   /// The index of an albedo map to use.
    int32_t normal  = -1;   /// The index of a normal map to use.
}
///
pure nothrow @safe @nogc unittest
{
    static assert (MaterialIndices.physics.offsetof == 0);
    static assert (MaterialIndices.albedo.offsetof  == 4);
    static assert (MaterialIndices.normal.offsetof  == 8);

    static assert (MaterialIndices.sizeof == 12);
}

/// Contains a model transform for objects as it appears inside a vertex buffer.
align (1) struct ModelTransform
{
    Mat4x3 transform; /// The 4x3 matrix containing an objects tranform.

    alias transform this;
}
///
pure nothrow @safe @nogc unittest
{
    static assert (ModelTransform.transform.offsetof == 0);
    static assert (ModelTransform.sizeof == 48);
}

/**
    Given an input range of meshes, this will count the total number of vertices and indices so that memory can be 
    allocated.

    See_Also:
        isMesh
*/
void countVerticesAndIndices (Meshes)(auto ref Meshes meshes, out size_t vertices, out size_t indices)
    if (isMesh!(ElementType!Meshes))
{
    import std.parallelism  : parallel, taskPool;

    // Add thread-local storage for the task pool so we avoid data races/cache misses.
    struct Counts { size_t vertex; size_t index; }
    auto counts = taskPool.workerLocalStorage!(Counts);
    
    // Parallelise the loop, evaluating how many verices and elements are required for each mesh.
    foreach (ref mesh; parallel (meshes))
    {
        with (counts.get)
        {
            vertex  += mesh.countVertices;
            index   += mesh.elements.length;
        }
    }

    // Finally put the results together.
    foreach (ref result; counts.toRange)
    {
        vertices    += result.vertex;
        indices     += result.index;
    }
}

/// Counts the vertices of the given mesh.
size_t countVertices (Mesh)(auto ref Mesh mesh)
    if (isMesh!Mesh)
{
    import std.algorithm : max;

    with (mesh)
    {
        return max (positions.length, normals.length, tangents.length, textureCoordinates.length);
    }
}

/**
    Fills the given mesh array, vertex pointer and index pointer with mesh data found in the given sceneMeshes object.
    
    This makes the assumption that the given vertex and index pointers point to contiguous memory large enough to store
    all of the generated mesh data. No bounds checking can be performed to ensure memory safety.
*/
void fillMeshData (Meshes)(out Mesh[] meshes, Vertex* vertices, uint32_t* indices, auto ref Meshes sceneMeshes)
    if (isMesh!(ElementType!Meshes))
in
{
    assert (vertices !is null);
    assert (indices !is null);
}
body
{
    import std.algorithm : max;
    
    // We also must keep track of the total indices and vertices written so we can construct the meshes.
    uint32_t firstIndex; 
    int32_t vertexOffset;
    foreach (ref sceneMesh; sceneMeshes)
    {
        // Increase capacity if necessary.
        if (meshes.length == meshes.capacity) meshes.reserve (max (meshes.capacity * 2 / 4, 2));
        with (sceneMesh)
        {
            // We must ensure we don't access data in the mesh which doesn't exist so we need the range lengths.
            immutable posCount      = positions.length;
            immutable normCount     = normals.length;
            immutable tanCount      = tangents.length;
            immutable uvCount       = textureCoordinates.length;
            immutable vertexCount   = cast (uint32_t) countVertices (sceneMesh);

            // Fill the vertex mapping.
            foreach (index; 0..vertexCount)
            {
                with (*vertices)
                {
                    position    = index < posCount ? positions[index] : Vec3.zero;
                    normal      = index < normCount ? normals[index] : Vec3.up;
                    tangent     = index < tanCount ? tangents[index] : Vec3.forward;
                    uv          = index < uvCount ? textureCoordinates[index] : Vec2.zero;
                }
                ++vertices;
            }

            // Fill the index mapping.
            immutable indexCount = cast (uint32_t) elements.length;
            foreach (element; elements)
            {
                *indices = element;
                ++indices;
            }

            // Now construct the mesh.
            immutable Mesh mesh =
            {
                id:             sceneMesh.id,
                indexCount:     indexCount,
                firstIndex:     firstIndex,
                vertexOffset:   vertexOffset
            };

            // Add the mesh and prepare for the next.
            meshes          ~= mesh;
            firstIndex      += indexCount;
            vertexOffset    += vertexCount;
        }
    }
}

/// Counts the number of instances in the given scene which contains the given meshes.
size_t countInstances (Scene)(auto ref Scene scene, Mesh[] meshes)
    if (isScene!Scene)
{
    import std.algorithm : count;

    size_t total;
    foreach (ref mesh; meshes)
    {
        total += scene.instancesByMesh (mesh.id).count;
    }
    return total;
}
