/**
    Allows the creation and storage of shaders required by the renderer.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: MIT
*/
module denjin.rendering.vulkan.internals.shaders;

// Engine.
import denjin.rendering.vulkan.device   : Device;
import denjin.rendering.vulkan.misc     : enforceSuccess, safelyDestroyVK;
import denjin.rendering.vulkan.nulls    : nullDevice, nullShader;
import denjin.rendering.vulkan.objects  : createShaderModule;

// Externals.
import erupted.types : VkAllocationCallbacks, VkPipelineShaderStageCreateInfo, VkShaderModule,
                       VK_SHADER_STAGE_ALL, VK_SHADER_STAGE_FRAGMENT_BIT, VK_SHADER_STAGE_VERTEX_BIT, 
                       VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;

/// Loads and creates the vertex and fragment shader stages required by the rendering pipelines.
struct Shaders
{
    alias ShaderInfo = VkPipelineShaderStageCreateInfo;

    ShaderInfo      vertexInfo;     /// Allows the usage of the vertex shader as part of a pipeline.
    ShaderInfo      fragmentInfo;   /// Allows the usage of the fragment shader as part of a pipeline.

    VkShaderModule  vertexShader    = nullShader;   /// Currently we only use a single vertex shader.
    VkShaderModule  fragmentShader  = nullShader;   /// Currently we only use a single fragment shader.

    private enum ShaderInfo infoTemplate = 
    {
        sType:                  VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        pNext:                  null,
        flags:                  0,
        stage:                  VK_SHADER_STAGE_ALL,    // Must be changed.
        _module:                null,                   // Must be changed.
        pName:                  "main",
        pSpecializationInfo:    null
    };

    public void create (ref Device device, in VkAllocationCallbacks* callbacks = null)
    in
    {
        assert (device != nullDevice);
        assert (vertexShader == nullShader);
        assert (fragmentShader == nullShader);
    }
    out
    {
        assert (vertexShader != nullShader);
        assert (fragmentShader != nullShader);
    }
    body
    {
        immutable destroy = delegate (ref VkShaderModule sh) => 
            sh.safelyDestroyVK (device.vkDestroyShaderModule, device, sh, callbacks);

        // Start by compiling the modules.
        vertexShader.createShaderModule (device, "shaders/testVert.spv", callbacks).enforceSuccess;
        scope (failure) vertexShader.destroy;

        fragmentShader.createShaderModule (device, "shaders/testFrag.spv", callbacks).enforceSuccess;
        scope (failure) fragmentShader.destroy;

        // Now compile the creation information required for using the shaders in pipelines.
        vertexInfo          = infoTemplate;
        vertexInfo.stage    = VK_SHADER_STAGE_VERTEX_BIT;
        vertexInfo._module  = vertexShader;

        fragmentInfo            = infoTemplate;
        fragmentInfo.stage      = VK_SHADER_STAGE_FRAGMENT_BIT;
        fragmentInfo._module    = fragmentShader;
    }

    public void clear (ref Device device, in VkAllocationCallbacks* callbacks = null) nothrow @nogc
    {
        vertexShader.safelyDestroyVK (device.vkDestroyShaderModule, device, vertexShader, callbacks);
        fragmentShader.safelyDestroyVK (device.vkDestroyShaderModule, device, fragmentShader, callbacks);
    }
}