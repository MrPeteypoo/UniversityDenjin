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
import denjin.rendering.vulkan.nulls            : nullBuffer, nullDevice, nullMemory;
import denjin.rendering.vulkan.objects          : createBuffer, createStagingBuffer;
import denjin.rendering.traits                  : isAssets, isMesh, isScene;
import denjin.rendering.vulkan.internals.types  : Mat4x3, Vec2, Vec3;

// External.
import erupted.types :  int32_t, uint32_t, VkAllocationCallbacks, VkBuffer, VkDeviceMemory, VkDeviceSize, 
                        VkMappedMemoryRange, VkPhysicalDeviceMemoryProperties,
                        VK_BUFFER_USAGE_INDEX_BUFFER_BIT, VK_BUFFER_USAGE_TRANSFER_DST_BIT, 
                        VK_BUFFER_USAGE_VERTEX_BUFFER_BIT, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, 
                        VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE,
                        VK_WHOLE_SIZE;

/// Contains the data required to render a mesh.
struct Mesh
{
    MeshID      id;             /// The unique ID of the mesh.
    uint32_t    indexCount;     /// How many element indices construct the mesh.
    uint32_t    firstIndex;     /// An offset into the index buffer where the indices for the mesh start.
    uint32_t    vertexOffset;   /// an offset into the vertex buffer where the first vertex can be found.
}

/// Loads, stores and manages geometry data. This includes vertex, index, material and transform data.
/// See_Also: isAssets, isScene.
struct GeometryT (Assets, Scene)
    if (isAssets!Assets && isScene!Scene)
{
    Mesh[]          meshes;                         /// Every loaded mesh in the scene.
    VkBuffer        staticBuffer    = nullBuffer;   /// The vertex buffer containing static data such as vertices and indices.
    VkBuffer        dynamicBuffer   = nullBuffer;   /// The vertex buffer containing dynamic data such as instancing attributes.
    VkDeviceMemory  staticMemory    = nullMemory;   /// The device memory bound to the static buffer.
    VkDeviceMemory  dynamicMemory   = nullMemory;   /// The device memory bound to the dynamic buffer.
    VkDeviceSize    vertexOffset    = 0;            /// The offset into the static buffer for mesh vertices.
    VkDeviceSize    indexOffset     = 0;            /// The offset into the static buffer for mesh indices.
    VkDeviceSize    staticSize      = 0;            /// The size of the static data buffer.

    /**
        Loads all meshes contained in the given assets object. Upon doing so, the given scene object will be analysed
        and vertex buffers will be prepared for rendering the entire scene. No static instance optimisation will be 
        performed, the total instances will just be used to ensure that enough data is stored to draw every object in
        the scene.
    */
    public void create (ref Device device, in ref VkPhysicalDeviceMemoryProperties memProps, in ref Assets assets, 
                        in ref Scene scene, in uint32_t virtualFrames, in VkAllocationCallbacks* callbacks = null)
    in
    {
        assert (device != nullDevice);
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
        fillStaticBuffer (device, memProps, assets, callbacks);
        //allocateDynamicBuffers (device, scene, virtualFrames, callbacks);
    }

    /// Deallocates resources, deleting all stored buffers and meshes.
    public void clear (ref Device device, in VkAllocationCallbacks* callbacks = null) nothrow
    in
    {
        assert (device != nullDevice);
    }
    body
    {
        staticMemory.safelyDestroyVK (device.vkFreeMemory, device, staticMemory, callbacks);
        dynamicMemory.safelyDestroyVK (device.vkFreeMemory, device, dynamicMemory, callbacks);
        staticBuffer.safelyDestroyVK (device.vkDestroyBuffer, device, staticBuffer, callbacks);
        dynamicBuffer.safelyDestroyVK (device.vkDestroyBuffer, device, dynamicBuffer, callbacks);
        meshes.length   = 0;
        vertexOffset    = 0;
        indexOffset     = 0;
        staticSize      = 0;
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

        // Now create the primary buffers.
        enum bufferUse  = VK_BUFFER_USAGE_VERTEX_BUFFER_BIT | VK_BUFFER_USAGE_INDEX_BUFFER_BIT | 
                          VK_BUFFER_USAGE_TRANSFER_DST_BIT;
        enum memoryUse  = VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT;
        staticBuffer.createBuffer (staticMemory, device, memProps, staticSize, bufferUse, memoryUse, callbacks)
                    .enforceSuccess;
    }

    /// Generates GPU-storable meshes and transfers them to the GPU, ready for usage by a scene.
    private void fillStaticBuffer (ref Device device, in ref VkPhysicalDeviceMemoryProperties memProps, 
                                   in ref Assets assets, in VkAllocationCallbacks* callbacks)
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

    }
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
        if (meshes.length == meshes.capacity) meshes.reserve (max (meshes.capacity, 2));
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
    meshes.length = meshes.capacity;
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
}
///
pure nothrow @safe @nogc unittest
{
    static assert (ModelTransform.transform.offsetof == 0);
    static assert (ModelTransform.sizeof == 48);
}
