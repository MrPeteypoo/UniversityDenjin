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
import denjin.rendering.vulkan.misc         : enforceSuccess, memoryTypeIndex, safelyDestroyVK;
import denjin.rendering.vulkan.nulls        : nullCMDBuffer, nullDescLayout, nullDescPool, nullDescSet, nullDevice, 
                                              nullImage, nullImageView, nullMemory, nullSampler;
import denjin.rendering.vulkan.objects      : allocateImageMemory, createDescLayout, createDescPool, createFence,
                                              createStagingBuffer;

// External.
import erupted.types;

/// Currently only RGBA channels are supported.
private immutable size_t[1] supportedTextureComponentCounts = [4];

/// Currently only 1x1 and 1024x1024 textures are supported.
private immutable size_t[2] supportedTextureSizes = [1, 1024];

/**
    Loads textures and materials contained within the given asset management systems.
    
    2D sampler arrays are creates which store texture of different formats. This texture data can then be used by 
    binding the stored image samplers and mapping MaterialID values to MaterialIndices values and then used in shaders.

    Params:     Assets = The asset management system used to retrieve assets.
    See_Also:   isAssets, MaterialID, MaterialIndices.
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

    Indices[MaterialID]     indices;                    /// Stores the indices required to render an object with the given MaterialID.
    ImageArray[]            imageArrays;                /// Handles to 2D image arrays containing textures and their associated image view.
    VkDescriptorSet         set         = nullDescSet;      /// The descriptor sets containing information required to bind each array.
    VkDescriptorPool        pool        = nullDescPool;     /// The descriptor pool from which the image array descriptor sets are allocated.
    VkDescriptorSetLayout   layout      = nullDescLayout;   /// Describes how the samplers are bound in shaders.

    /**
        Retrieves material data from the given assets package and loads it.
    */
    public void create (ref Device device, ref VkCommandBuffer render, in ref Assets assets, 
                        in ref VkPhysicalDeviceMemoryProperties memProps, in VkAllocationCallbacks* callbacks = null)
    in
    {
        assert (device != nullDevice);
        assert (indices.length == 0);
        assert (imageArrays.length == 0);
        assert (set == nullDescSet);
        assert (pool == nullDescPool);
        assert (layout == nullDescLayout);
    }
    body
    {
        scope (failure) clear (device, callbacks);

        // Load the textures into a texture map, this will also update the material indices for each material.
        const textureMap = indices.loadTextures (assets);
        
        // Next we need to transfer the memory to the GPU.
        createImageArrays (device, render, textureMap, memProps, callbacks);

        // Finally create the descriptor sets.
        createDescriptors (device, callbacks);
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
        layout.safelyDestroyVK (device.vkDestroyDescriptorSetLayout, device, layout, callbacks);
        indices.clear;
        set = nullDescSet;
    }

    /// Creates each 2D image array, filling them with the data from the texture map.
    private void createImageArrays (ref Device device, ref VkCommandBuffer render, in ref TextureMap textureMap, 
                                    in ref VkPhysicalDeviceMemoryProperties memProps, 
                                    in VkAllocationCallbacks* callbacks)
    {
        // Create a fence we can use for memory transfer operations.
        VkFence transferFence = void;
        transferFence.createFence (device, 0, callbacks).enforceSuccess;
        scope (exit) device.vkDestroyFence (transferFence, callbacks);

        // Now we can create each image array.
        imageArrays.length = supportedTextureComponentCounts.length * supportedTextureSizes.length;
        foreach (ref componentMap; textureMap.byKeyValue)
        {
            foreach (ref sizeMap; componentMap.value.byKeyValue)
            {
                // Find out which array we should be working on and create it.
                immutable components    = componentMap.key;
                immutable dimensions    = sizeMap.key;
                immutable layers        = sizeMap.value.length;
                immutable index         = samplerIndex (components, dimensions);
                auto imageInfo          = createImageArray (imageArrays[index], device, components, dimensions, layers, 
                                                            memProps, callbacks);

                // We need to create a staging buffer to transfer the textures to the GPU.
                VkDeviceSize memorySize     = cast (VkDeviceSize) (ubyte.sizeof * components * dimensions * dimensions * layers);
                VkBuffer hostBuffer         = void;
                VkDeviceMemory hostMemory   = void;
                hostBuffer.createStagingBuffer (hostMemory, device, memProps, memorySize, callbacks).enforceSuccess;
                scope (exit)
                {
                    device.vkWaitForFences (1, &transferFence, VK_FALSE, 1_000_000_000).enforceSuccess;
                    device.vkFreeMemory (hostMemory, callbacks);
                    device.vkDestroyBuffer (hostBuffer, callbacks);
                }

                // Now we can transfer the textures to the GPU.
                device.vkResetFences (1, &transferFence).enforceSuccess;
                transferToArray (device, render, transferFence, imageArrays[index], hostBuffer, hostMemory, memorySize, 
                                 sizeMap.value, imageInfo);
            }
        }
    }

    /// Creates an image array of the given dimensions and returns the total mip levels of the array.
    private auto createImageArray (out ImageArray imageArray, ref Device device, in size_t components, 
                                   in size_t dimensions, in size_t layers, 
                                   in ref VkPhysicalDeviceMemoryProperties memProps, 
                                   in VkAllocationCallbacks* callbacks)
    {
        // Retrieve the values needed to configure this image array.
        immutable width     = cast (uint32_t) dimensions;
        immutable format    = vulkanFormat (components);
        immutable extent    = VkExtent3D (width, width, 1);

        // Create the image.
        auto imageInfo          = commonImageInfo;
        imageInfo.format        = format;
        imageInfo.extent        = extent;
        imageInfo.arrayLayers   = cast (uint32_t) layers;
        imageInfo.mipLevels     = width > 128 ? 5 : 1;
        imageInfo.usage         |= imageInfo.mipLevels > 1 ? VK_IMAGE_USAGE_TRANSFER_SRC_BIT : 0;
        device.vkCreateImage (&imageInfo, callbacks, &imageArray.image).enforceSuccess;

        // Allocate the memory and create the view.
        imageArray.memory.allocateImageMemory (device, imageArray.image, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, 
                                               memProps, callbacks).enforceSuccess;

        auto viewInfo                           = commonViewInfo;
        viewInfo.image                          = imageArray.image;
        viewInfo.format                         = imageInfo.format;
        viewInfo.subresourceRange.levelCount    = imageInfo.mipLevels;
        viewInfo.subresourceRange.layerCount    = imageInfo.arrayLayers;
        device.vkCreateImageView (&viewInfo, callbacks, &imageArray.view).enforceSuccess;

        // Finally create the sampler.
        immutable samplerInfo = commonSamplerInfo;
        device.vkCreateSampler (&samplerInfo, callbacks, &imageArray.sampler).enforceSuccess;
        return imageInfo;
    }

    /**
        Iterates through the given texture map and transfers all data to the given image array using the given command
        buffer, fence and staging buffer.
    */
    private void transferToArray (ref Device device, ref VkCommandBuffer render, ref VkFence fence, 
                                  ref ImageArray imageArray, ref VkBuffer hostBuffer, ref VkDeviceMemory hostMemory, 
                                  in VkDeviceSize memorySize, in ref Texture[Texture.Name] textures, 
                                  in ref VkImageCreateInfo imageInfo)
    {
        import core.stdc.string : memcpy;

        // Map the memory.
        void* mapping = void;
        device.vkMapMemory (hostMemory, 0, VK_WHOLE_SIZE, 0, &mapping).enforceSuccess;
        
        // Copy each texture whilst obeying their index value.
        foreach (ref texture; textures.byValue)
        {
            assert (texture.bytes.length == memorySize / imageInfo.arrayLayers);

            auto stagingMemory = mapping + texture.index * texture.bytes.length;
            stagingMemory.memcpy (texture.bytes.ptr, texture.bytes.length);
        }

        // Flush the memory. 
        const VkMappedMemoryRange flush = 
        {
            sType:      VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE,
            pNext:      null,
            memory:     hostMemory,
            offset:     0,
            size:       memorySize
        };
        immutable flushResult = device.vkFlushMappedMemoryRanges (1, &flush);
        device.vkUnmapMemory (hostMemory);
        flushResult.enforceSuccess;

        // Transfer each mip level to the GPU. We first need to transition the blank array to the transfer layout.
        VkImageMemoryBarrier imageBarrier = 
        {   
            sType:                  VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
            pNext:                  null,
            srcAccessMask:          0,
            dstAccessMask:          VK_ACCESS_TRANSFER_WRITE_BIT,
            oldLayout:              VK_IMAGE_LAYOUT_UNDEFINED,
            newLayout:              VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            srcQueueFamilyIndex:    device.renderQueueFamily,
            dstQueueFamilyIndex:    device.renderQueueFamily,
            image:                  imageArray.image,
            subresourceRange:
            {
                aspectMask:     VK_IMAGE_ASPECT_COLOR_BIT,
                baseMipLevel:   0,
                levelCount:     imageInfo.mipLevels,
                baseArrayLayer: 0,
                layerCount:     imageInfo.arrayLayers
            }
        };

        // We also need to prepare for copying.
        immutable VkBufferImageCopy copyToImage =
        {
            bufferOffset:       0,
            bufferRowLength:    0,
            bufferImageHeight:  0,
            imageSubresource:
            {
                aspectMask:     VK_IMAGE_ASPECT_COLOR_BIT,
                mipLevel:       0,
                baseArrayLayer: 0,
                layerCount:     imageInfo.arrayLayers
            },
            imageOffset:        VkOffset3D (0, 0, 0),
            imageExtent:        imageInfo.extent
        };

        // We can start recording commands now.
        immutable VkCommandBufferBeginInfo beginInfo = 
        {
            sType:              VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            pNext:              null,
            flags:              VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
            pInheritanceInfo:   null
        };
        device.vkBeginCommandBuffer (render, &beginInfo);
        device.vkCmdPipelineBarrier (render, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 
                                     0, 0, null, 0, null, 1, &imageBarrier);
        device.vkCmdCopyBufferToImage (render, hostBuffer, imageArray.image, 
                                       VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &copyToImage);

        // Update each mip level.
        if (imageInfo.mipLevels > 1)
        {
            immutable extent        = imageInfo.extent;
            VkImageBlit imageBlit   =
            {
                srcSubresource: copyToImage.imageSubresource,
                dstSubresource: copyToImage.imageSubresource,
                srcOffsets:     [ VkOffset3D (0, 0, 0), VkOffset3D (extent.width, extent.height, 1)],
                dstOffsets:     [ VkOffset3D (0, 0, 0), VkOffset3D (extent.width, extent.height, 1)]
            };
            foreach (i; 1..imageInfo.mipLevels)
            {
                imageBlit.dstSubresource.mipLevel   = i;
                imageBlit.dstOffsets[1].x           /= 2;
                imageBlit.dstOffsets[1].y           /= 2;
                device.vkCmdBlitImage (render, 
                                       imageArray.image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                                       imageArray.image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 
                                       1, &imageBlit, VK_FILTER_LINEAR);
            }
        }
        // Almost done, transition the image ready for usage by shaders.
        imageBarrier.srcAccessMask          = VK_ACCESS_TRANSFER_WRITE_BIT;
        imageBarrier.dstAccessMask          = VK_ACCESS_SHADER_READ_BIT;
        imageBarrier.oldLayout              = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
        imageBarrier.newLayout              = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        imageBarrier.srcQueueFamilyIndex    = device.renderQueueFamily;
        imageBarrier.dstQueueFamilyIndex    = device.renderQueueFamily;
        device.vkCmdPipelineBarrier (render, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT, 
                                     0, 0, null, 0, null, 1, &imageBarrier);
        device.vkEndCommandBuffer (render);

        // Finally submit the queue.
        const VkSubmitInfo submitInfo = 
        {
            sType:                  VK_STRUCTURE_TYPE_SUBMIT_INFO,
            pNext:                  null,
            waitSemaphoreCount:     0,
            pWaitSemaphores:        null,
            pWaitDstStageMask:      null,
            commandBufferCount:     1,
            pCommandBuffers:        &render,
            signalSemaphoreCount:   0,
            pSignalSemaphores:      null
        };
        device.vkQueueSubmit (device.renderQueue, 1, &submitInfo, fence).enforceSuccess;
    }

    /// Creates the descriptor layout, pool and set for the samplers.
    private void createDescriptors (ref Device device, in VkAllocationCallbacks* callbacks)
    {
        // Collect the samplers together.
        auto samplers = new VkSampler[imageArrays.length];
        foreach (i, ref imageArray; imageArrays)
        {
            samplers[i] = imageArray.sampler;
        }

        // Create the layout.
        immutable samplersLength    = cast (uint32_t) samplers.length;
        enum descriptorType         = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
        const VkDescriptorSetLayoutBinding[1] binding = 
        {
            binding:            0,
            descriptorType:     descriptorType,
            descriptorCount:    samplersLength,
            stageFlags:         VK_SHADER_STAGE_FRAGMENT_BIT,
            pImmutableSamplers: samplers.ptr
        };
        layout.createDescLayout (device, binding, callbacks).enforceSuccess;

        // The pool.
        pool.createDescPool (device, descriptorType, samplersLength, callbacks).enforceSuccess;

        // And finally the descriptor set.
        VkDescriptorSetAllocateInfo alloc = 
        {
            sType:              VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
            pNext:              null,
            descriptorPool:     pool,
            descriptorSetCount: 1,
            pSetLayouts:        &layout
        };
        device.vkAllocateDescriptorSets (&alloc, &set).enforceSuccess;

        // Bug on the validation layer means we have to update the descriptor set even though it'll ignore it anyway.
        foreach (i, ref imageArray; imageArrays)
        {
            const VkDescriptorImageInfo imageInfo = 
            {
                sampler:        imageArray.sampler,
                imageView:      imageArray.view,
                imageLayout:    VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL
            };
            const VkWriteDescriptorSet write = 
            {
                sType:              VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                pNext:              null,
                dstSet:             set,
                dstBinding:         0,
                dstArrayElement:    cast (uint32_t) i,
                descriptorCount:    1,
                descriptorType:     descriptorType,
                pImageInfo:         &imageInfo,
                pBufferInfo:        null,
                pTexelBufferView:   null
            };
            device.vkUpdateDescriptorSets (1, &write, 0, null);
        }
    }

    /// Contains attributes common to every image array, format, extent and arrayLayers must be changed.
    enum VkImageCreateInfo commonImageInfo =
    {
        sType:                  VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        pNext:                  null,
        flags:                  0,
        imageType:              VK_IMAGE_TYPE_2D,
        format:                 VK_FORMAT_R8G8B8A8_UNORM,   // Must be changed.
        extent:                 VkExtent3D (1, 1, 1),       // Must be changed.
        mipLevels:              1,                          // Must be changed.
        arrayLayers:            1,                          // Must be changed.
        samples:                VK_SAMPLE_COUNT_1_BIT,
        tiling:                 VK_IMAGE_TILING_OPTIMAL,    // Must be changed.
        usage:                  VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT,
        sharingMode:            VK_SHARING_MODE_EXCLUSIVE,
        queueFamilyIndexCount:  0,
        pQueueFamilyIndices:    null,
        initialLayout:          VK_IMAGE_LAYOUT_UNDEFINED
    };

    /// Contains attributes common to every image array, image, format and layer count must be changed.
    enum VkImageViewCreateInfo commonViewInfo =
    {
        sType:          VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        pNext:          null,
        flags:          0,
        image:          nullImage,                      // Must be changed.
        viewType:       VK_IMAGE_VIEW_TYPE_2D_ARRAY,
        format:         VK_FORMAT_R8G8B8A8_UNORM,       // Must be changed.
        components:
        {
            r: VK_COMPONENT_SWIZZLE_IDENTITY, g: VK_COMPONENT_SWIZZLE_IDENTITY, 
            b: VK_COMPONENT_SWIZZLE_IDENTITY, a: VK_COMPONENT_SWIZZLE_IDENTITY
        },
        subresourceRange:
        {
            aspectMask:     VK_IMAGE_ASPECT_COLOR_BIT,
            baseMipLevel:   0,
            levelCount:     1,  // Must be changed.
            baseArrayLayer: 0,
            layerCount:     1   // Must be changed.
        }
    };

    /// Contains the creation information required for every sampler.
    enum VkSamplerCreateInfo commonSamplerInfo =
    {
        sType:                      VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
        pNext:                      null,
        flags:                      0,
        magFilter:                  VK_FILTER_LINEAR,
        minFilter:                  VK_FILTER_LINEAR,
        mipmapMode:                 VK_SAMPLER_MIPMAP_MODE_NEAREST,
        addressModeU:               VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
        addressModeV:               VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
        addressModeW:               VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
        mipLodBias:                 0f,
        anisotropyEnable:           VK_TRUE,
        maxAnisotropy:              16f,
        compareEnable:              VK_FALSE,
        compareOp:                  VK_COMPARE_OP_ALWAYS,
        minLod:                     0f,
        maxLod:                     0.25f,
        borderColor:                VK_BORDER_COLOR_FLOAT_TRANSPARENT_BLACK,
        unnormalizedCoordinates:    VK_FALSE
    };
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
        return cast (int32_t) (sampler | (texture << (ubyte.sizeof * 8)));
    }
}

/// The engines representation of perfectly square texture data.
private struct Texture
{
    alias Index = size_t;   /// Contains the sampler/texture index for use in shaders.
    alias Name  = string;   /// Textures may be mapped by their file name.
    alias Size  = size_t;   /// Textures may be mapped by their dimensions (e.g. 1024).
    alias Comps = size_t;   /// Textures may be mapped by their component count.

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
        immutable float[4] physics  = [smoothness, reflectance, conductivity, 0f];
        immutable float[4] albedo   = [material.albedo[0], material.albedo[1], material.albedo[2], material.albedo[3]];

        // Load the textures.
        immutable physicsIndex  = map.loadTexture!(4)(counts, material.physicsMap, physics);
        immutable albedoIndex   = map.loadTexture!(4)(counts, material.albedoMap, albedo);
        immutable normalIndex   = map.loadTexture!(4)(counts, material.normalMap);

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

    Returns: The sampler/texture index value of the texture.
*/
private auto loadTexture (size_t components)(ref TextureMap map, ref TextureCounts counts, 
                                             in string file, in float[] fallback = [])
{
    import std.conv     : to;
    import imageformats : read_image, read_image_info;

    // Modify this texture when loading.
    Texture newTexture = { components: components, index: Texture.Index.max };

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
                    return MaterialIndices.index (samplerIndex (components, size), texture.index);
                }

                // We need to load the texture, ensuring it's converted to the correct image format.
                auto image              = read_image (file, channels != components ? format!components : 0);
                newTexture.name         = file;
                newTexture.dimensions   = size;
                newTexture.bytes        = image.pixels;
                newTexture.index        = counts[components][size]++;
            }
        }
        // Couldn't load the image.
        catch (Throwable)
        {
        }
    }
    // Load using the fallback if necessary.
    if (newTexture.index == Texture.Index.max && fallback.length >= components)
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
            return MaterialIndices.index (samplerIndex (components, 1), texture.index);
        }
        newTexture.dimensions   = 1;
        newTexture.bytes        = values.dup;
        newTexture.index        = counts[components][1]++;
    }
    // Add the texture.
    if (newTexture.index != Texture.Index.max)
    {
        map[components][newTexture.dimensions][newTexture.name] = newTexture;
        return MaterialIndices.index (samplerIndex (components, newTexture.dimensions), newTexture.index);
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

/// Returns the VkFormat corresponding to the given component number.
private VkFormat vulkanFormat (in size_t components)
{
    final switch (components)
    {
        case 1:
            return VK_FORMAT_R8_UNORM;
        case 2:
            return VK_FORMAT_R8G8_UNORM;
        case 3:
            return VK_FORMAT_R8G8B8_UNORM;
        case 4:
            return VK_FORMAT_R8G8B8A8_UNORM;
    }

    assert (false, "Format unsupported.");
}