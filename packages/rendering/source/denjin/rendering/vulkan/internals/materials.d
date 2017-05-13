/**
    Stores and manages image buffers containing material data.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: Copyright © 2017, Simon Peter Campbell
    License: MIT
*/
module denjin.rendering.vulkan.internals.materials;

// Phobos.
import std.algorithm    : canFind, countUntil;
import std.traits       : ReturnType;

// Engine
import denjin.misc.ids                      : MaterialID;
import denjin.rendering.traits              : isAssets;
import denjin.rendering.vulkan.device       : Device;
import denjin.rendering.vulkan.misc         : safelyDestroyVK;
import denjin.rendering.vulkan.nulls        : nullDescPool, nullDevice, nullImage, nullImageView, nullMemory, nullSampler;

// External.
import erupted.types : int32_t, VkAllocationCallbacks, VkDescriptorPool, VkDescriptorSet, VkDeviceMemory, VkImage, 
                       VkImageView, VkSampler;

/// Currently only RGB and RGBA channels are supported.
private immutable size_t[2] supportedTextureComponentCounts = [3, 4];

/// Currently only 1x1 and 1024x1024 textures are supported.
private immutable size_t[2] supportedTextureSizes = [1, 1024];

/**
    Loads textures and materials contained within the given asset management systems.
    
    2D sampler arrays are creates which store texture of different formats. This texture data can then be used by 
    binding the stored image samplers and mapping MaterialID values to MaterialIndices values and then used in shaders.

    Params:
        Assets = The asset management system used to retrieve assets.

    See_Also:
        isAssets, MaterialID, MaterialIndices.
*/
struct MaterialsT (Assets)
    if (isAssets!Assets)
{
    /// Stores image, view and memory handles for 2D image arrays.
    struct ImageArray
    {
        VkImage         image   = nullImage;        /// A handle to a 2D image array.
        VkDeviceMemory  memory  = nullMemory;       /// A handle to the memory allocated for the array.
        VkImageView     view    = nullImageView;    /// A handle to the associated image view of the array.
        VkSampler       sampler = nullSampler;      /// A handle to the sampler which gives shaders access to the image array.
    }
    alias Indices = MaterialIndices;

    Indices[MaterialID] indices;                /// Stores the indices required to render an object with the given MaterialID.
    VkDescriptorSet[]   sets;                   /// The descriptor sets containing information required to bind each array.
    ImageArray[]        imageArrays;            /// Handles to 2D image arrays containing textures and their associated image view.
    VkDescriptorPool    pool = nullDescPool;    /// The descriptor pool from which the image array descriptor sets are allocated.

    /**
        Retrieves material data from the given assets package and loads it.
    */
    public void create (ref Device device, in ref Assets assets, in VkAllocationCallbacks* callbacks = null)
    in
    {
        assert (device != nullDevice);
        assert (indices.length == 0);
        assert (sets.length == 0);
        assert (imageArrays.length == 0);
        assert (pool == nullDescPool);
    }
    body
    {
        scope (failure) clear (device, callbacks);
        const textureMap = loadTextures (indices, assets);
    }

    /// Destroys stored resources and unitialises the object.
    public void clear (ref Device device, in VkAllocationCallbacks* callbacks = null) nothrow
    in
    {
        assert (device != nullDevice);
    }
    body
    {
        foreach (ref array; imageArrays) with (array)
        {
            memory.safelyDestroyVK (device.vkFreeMemory, device, memory, callbacks);
            sampler.safelyDestroyVK (device.vkDestroySampler, device, sampler, callbacks);
            view.safelyDestroyVK (device.vkDestroyImageView, device, view, callbacks);
            image.safelyDestroyVK (device.vkDestroyImage, device, image, callbacks);
        }
        pool.safelyDestroyVK (device.vkDestroyDescriptorPool, device, pool, callbacks);
        indices.clear;
        sets.length = 0;
    }
}

/// A group of texture indices as they are stored inside a vertex buffer.
align (1) struct MaterialIndices
{
    enum    none    = -1;   /// Indicates that no index exists.
    int32_t physics = none; /// The index of a physics map to use.
    int32_t albedo  = none; /// The index of an albedo map to use.
    int32_t normal  = none; /// The index of a normal map to use.

    /// Returns an index value for the given sampler/texture index pair.
    public static int32_t index (in size_t sampler, in size_t texture)
    {
        if (sampler < 0 || sampler > ubyte.max) return -1;
        if (texture < 0 || texture > ushort.max) return -1;
        return cast (int32_t) (sampler || (texture << ubyte.sizeof));
    }
}

/// The engines representation of perfectly square texture data.
private struct Texture
{
    alias Index = typeof (MaterialIndices.albedo);  /// Contains the sampler/texture index for use in shaders.
    alias Name  = string;                           /// Textures may be mapped by their file name.
    alias Size  = size_t;                           /// Textures may be mapped by their dimensions (e.g. 1024).
    alias Comps = size_t;                           /// Textures may be mapped by their component count.

    Index   index;      /// The index of the texture as it should appear in shaders.
    Name    name;       /// Either a name ID for the texture or the file location.
    Size    dimensions; /// How many pixels wide/tall the texture is.
    Comps   components; /// How many components make up each pixel.
    ubyte[] bytes;      /// The raw bytes of the texture data.
}

/// Textures are mapped by their component count, size and finally their name.
private alias TextureMap = Texture[Texture.Name][Texture.Size][Texture.Comps];

/// We need to keep track of how many textures of each type have been loaded.
private alias TextureCounts = size_t[Texture.Size][Texture.Comps];

/**
    Parses the materials contained in the given assets package and loads the textures into a texture map. The indices
    of each material will be written to the indices parameters.
*/
private TextureMap loadTextures (Assets)(out MaterialIndices[MaterialID] indices, in ref Assets assets)
    if (isAssets!Assets)
{
    import std.algorithm : clamp, move;

    // We need to create and initialise a TextureMap and Counts instance.
    TextureMap      map;
    TextureCounts   counts;
    foreach (comp; supportedTextureComponentCounts)
    {
        foreach (size; supportedTextureSizes)
        {
            Texture[Texture.Name] temp;
            map[comp][size] = temp;
            counts[comp][size] = 0;
        }
    }

    foreach (ref material; assets.materials)
    {
        // Collect the material attributes.
        immutable smoothness        = (cast (float) (material.smoothness)).clamp (0f, 1f);
        immutable reflectance       = (cast (float) (material.reflectance)).clamp (0f, 1f);
        immutable conductivity      = (cast (float) (material.conductivity)).clamp (0f, 1f);
        immutable float[3] physics  = [smoothness, reflectance, conductivity];
        immutable float[4] albedo   = [material.albedo[0], material.albedo[1], material.albedo[2], material.albedo[3]];

        // Load the textures.
        immutable physicsIndex  = map.loadTexture!(3)(counts, material.physicsMap, physics);
        immutable albedoIndex   = map.loadTexture!(4)(counts, material.albedoMap, albedo);
        immutable normalIndex   = map.loadTexture!(3)(counts, material.normalMap);

        // Set the indices for the current material.
        MaterialIndices mat = 
        {
            physics:    physicsIndex,
            albedo:     albedoIndex,
            normal:     normalIndex
        };
        indices[material.id] = move (mat);
    }
    return map;
}

/**
    Attempts to load the given texture map file, if this is not possible then the fallback float array will be used.

    Params:
        components  = How many components the texture needs.
        map         = The map to place the new texture in if loaded.
        counts      = Used to set the texture index value.
        file        = Where the texture file is located on the machine.
        fallback    = Values to use if the texture map can't be found.
*/
private Texture.Index loadTexture (size_t components)(ref TextureMap map, ref TextureCounts counts, 
                                                      in string file, in float[] fallback = [])
{
    import std.conv     : to;
    import imageformats : read_image, read_image_info;

    // Modify this texture when loading.
    Texture newTexture = { components: components, index: MaterialIndices.none };

    // Load from a file.
    if (file != "")
    {   
        try
        {
            // First we must check if we can load the texture.
            int width = void, height = void, channels = void;
            read_image_info (file, width, height, channels);

            // Only square textures are supported currently.
            immutable size = cast (size_t) width;
            if (width == height && isSupportedFormat (components, size))
            {
                // Avoid loading the texture multiple times.
                if (const texture = file in map[components][size])
                {
                    return texture.index;
                }

                // We need to load the texture, ensuring it's converted to the correct image format.
                auto image              = read_image (file, format!components);
                newTexture.name         = file;
                newTexture.dimensions   = size;
                newTexture.bytes        = image.pixels;
                const sampler           = samplerIndex (components, size);
                const index             = counts[components][size]++;
                newTexture.index        = MaterialIndices.index (sampler, index);
            }
        }
        // Couldn't load the image.
        catch (Throwable)
        {
        }
    }
    // Load using the fallback if necessary.
    if (newTexture.index == MaterialIndices.none && fallback.length >= components)
    {
        // Create a string name from each fallback value. This allows a unique texture for every instance of the value.
        ubyte[components] values = void;
        foreach (i, ref value; values)
        {
            value = cast (ubyte) (ubyte.max * fallback[i]);
            newTexture.name ~= value.to!string ~ ":";
        }
        
        // Check if the texture is already mapped.
        if (const texture = newTexture.name in map[components][1])
        {
            return texture.index;
        }
        newTexture.dimensions   = 1;
        newTexture.bytes        = values.dup;
        newTexture.index        = MaterialIndices.index (samplerIndex (components, 1), counts[components][1]++);
    }
    // Add the texture.
    if (newTexture.index != MaterialIndices.none)
    {
        map[components][newTexture.dimensions][newTexture.name] = newTexture;
        return newTexture.index;
    }

    return MaterialIndices.none;
}

/// Converts the given component count to a imageformats.ColFmt value.
private template format (size_t components)
{
    import imageformats : ColFmt;

    static if (components == 1)         enum format = ColFmt.Y;
    else static if (components == 2)    enum format = ColFmt.YA;
    else static if (components == 3)    enum format = ColFmt.RGB;
    else static if (components == 4)    enum format = ColFmt.RGBA;
    else
    {
        static assert (false, "Unsupported colour format.");
    }
}

/**
    Returns the index of the sampler to use for the given image format. 
    This is currently hard-coded to only support 1x1 and 1024x1024 sizes right now.
*/
private size_t samplerIndex (in size_t components, in size_t size) pure nothrow @safe @nogc
{
    if (!isSupportedFormat (components, size)) assert (false);
    immutable compIndex = countUntil (supportedTextureComponentCounts[], components);
    immutable sizeIndex = countUntil (supportedTextureSizes[], size);

    return sizeIndex + compIndex * supportedTextureComponentCounts.length;
}

/// Checks whether the given texture format is supported.
private bool isSupportedFormat (in size_t components, in size_t size) pure nothrow @safe @nogc
{
    return canFind (supportedTextureComponentCounts[], components) &&
           canFind (supportedTextureSizes[], size);
}