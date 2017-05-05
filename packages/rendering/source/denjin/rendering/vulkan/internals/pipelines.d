/**
    Constructs the pipelines required by the renderer.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: Copyright © 2017, Simon Peter Campbell
    License: MIT
*/
module denjin.rendering.vulkan.internals.pipelines;

// Phobos.
import std.exception : enforce;

// Engine.
import denjin.rendering.vulkan.device                   : Device;
import denjin.rendering.vulkan.internals.renderpasses   : RenderPasses;
import denjin.rendering.vulkan.misc                     : enforceSuccess, safelyDestroyVK;
import denjin.rendering.vulkan.nulls                    : nullDevice, nullLayout, nullPass, nullPipeline, 
                                                          nullPipelineCache, nullShader;
import denjin.rendering.vulkan.objects                  : createShaderModule;

// Externals.
import erupted.types;

/**
    Contains the pipelines required to perform different render passes that are currently supported.

    Pipelines contain the state which the driver should configure itself in to perform tasks we require of it. These
    allow the driver to optimise its configuration and is the way Vulkan requires us to configure state.
*/
struct Pipelines
{
    VkPipeline forward = nullPipeline; /// A dedicated forward render pipeline.

    /// For now this just creates a forward rendering pipeline for basic rendering support.
    public void create (ref Device device, in VkExtent2D resolution, ref RenderPasses renderPasses,
                        in VkAllocationCallbacks* callbacks = null)
    in
    {
        assert (device != nullDevice);
        assert (forward == nullPipeline);
    }
    body
    {
        // If anything goes wrong we should avoid leaking objects.
        scope (failure) clear (device, callbacks);

        // We'll need shaders before we can construct any pipelines.
        auto shaders = Shaders();
        scope (exit) shaders.clear (device, callbacks);
        shaders.create (device, callbacks);
        
        // Now we can construct the required pipelines.
        forward = ForwardRenderPipeline.create (device, resolution, renderPasses, shaders, callbacks);
        enforce (forward != nullPipeline);
    }

    /// Destroys any stored handles the object may have.
    public void clear (ref Device device, in VkAllocationCallbacks* callbacks = null) nothrow @nogc
    {
        forward.safelyDestroyVK (device.vkDestroyPipeline, device, forward, callbacks);
    }
}

/// A basic pipeline which allows for a dedicated forward rendering pass.
struct ForwardRenderPipeline
{   
    /// Sets the default values used for the create info structs.
    enum VkGraphicsPipelineCreateInfo infoTemplate = 
    {
        sType:                  VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
        pNext:                  null,
        flags:                  0,
        stageCount:             2,
        pStages:                null,           // Must be changed.
        pVertexInputState:      null,           // Must be changed.
        pInputAssemblyState:    null,           // Must be changed.
        pTessellationState:     null,
        pViewportState:         null,           // Must be changed.
        pRasterizationState:    null,           // Must be changed.
        pMultisampleState:      null,           // Must be changed.
        pDepthStencilState:     null,           // Must be changed.
        pColorBlendState:       null,           // Must be changed.
        pDynamicState:          null,
        layout:                 nullLayout,     // Must be changed.
        renderPass:             nullPass,       // Must be changed.
        subpass:                0,
        basePipelineHandle:     nullPipeline,
        basePipelineIndex:      0
    };

    public static VkPipeline create (ref Device device, in VkExtent2D resolution, ref RenderPasses renderPasses, 
                                     in ref Shaders shaders, in VkAllocationCallbacks* callbacks = null)
    in
    {
        assert (device != nullDevice);
        assert (renderPasses.forward != nullPass);
        assert (shaders.vertexShader != nullShader);
        assert (shaders.fragmentShader != nullShader);
    }
    body
    {
        // Not sure this is possible to clean up.....
        const VkPipelineShaderStageCreateInfo[2] stages = [shaders.vertexInfo, shaders.fragmentInfo];
        immutable VkPipelineVertexInputStateCreateInfo vertexInput = 
        {
            sType:                              VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
            pNext:                              null,
            flags:                              0,
            vertexBindingDescriptionCount:      0,
            pVertexBindingDescriptions:         null,
            vertexAttributeDescriptionCount:    0,
            pVertexAttributeDescriptions:       null
        };
        immutable VkPipelineInputAssemblyStateCreateInfo assembly = 
        {
            sType:                  VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
            pNext:                  null,
            flags:                  0,
            topology:               VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
            primitiveRestartEnable: VK_FALSE
        };
        immutable VkViewport viewport = 
        {
            x:          0f,
            y:          0f,
            width:      resolution.width,
            height:     resolution.height,
            minDepth:   0f,
            maxDepth:   1f
        };
        immutable VkRect2D scissor =
        {
            offset: { x: 0, y: 0 },
            extent: resolution
        };
        immutable VkPipelineViewportStateCreateInfo view =
        {
            sType:          VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
            pNext:          null,
            flags:          0,
            viewportCount:  1,
            pViewports:     &viewport,
            scissorCount:   1,
            pScissors:      &scissor
        };
        immutable VkPipelineRasterizationStateCreateInfo rasterization =
        {
            sType:                      VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
            pNext:                      null,
            flags:                      0,
            depthClampEnable:           VK_FALSE,
            rasterizerDiscardEnable:    VK_FALSE,
            polygonMode:                VK_POLYGON_MODE_FILL,
            cullMode:                   VK_CULL_MODE_BACK_BIT,
            frontFace:                  VK_FRONT_FACE_COUNTER_CLOCKWISE,
            depthBiasEnable:            VK_FALSE,
            depthBiasConstantFactor:    0f,
            depthBiasClamp:             0f,
            depthBiasSlopeFactor:       0f,
            lineWidth:                  1f
        };
        immutable VkPipelineMultisampleStateCreateInfo multisample = 
        {
            sType:                  VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
            pNext:                  null,
            flags:                  0,
            rasterizationSamples:   VK_SAMPLE_COUNT_1_BIT,
            sampleShadingEnable:    VK_FALSE,
            minSampleShading:       1f,
            pSampleMask:            null,
            alphaToCoverageEnable:  VK_FALSE,
            alphaToOneEnable:       VK_FALSE
        };
        immutable VkPipelineDepthStencilStateCreateInfo depthStencil =
        {
            sType:                  VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
            pNext:                  null,
            flags:                  0,
            depthTestEnable:        VK_TRUE,
            depthWriteEnable:       VK_TRUE,
            depthCompareOp:         VK_COMPARE_OP_LESS,
            depthBoundsTestEnable:  VK_FALSE,
            stencilTestEnable:      VK_FALSE,
            minDepthBounds:         0f,
            maxDepthBounds:         0f
        };
        immutable VkPipelineColorBlendAttachmentState blendAttachment = 
        {
            blendEnable:            VK_FALSE,
            srcColorBlendFactor:    VK_BLEND_FACTOR_ONE,
            dstColorBlendFactor:    VK_BLEND_FACTOR_ZERO,
            colorBlendOp:           VK_BLEND_OP_ADD,
            srcAlphaBlendFactor:    VK_BLEND_FACTOR_ONE,
            dstAlphaBlendFactor:    VK_BLEND_FACTOR_ZERO,
            alphaBlendOp:           VK_BLEND_OP_ADD,
            colorWriteMask:         VK_COLOR_COMPONENT_R_BIT | VK_COLOR_COMPONENT_G_BIT | VK_COLOR_COMPONENT_B_BIT |
                                    VK_COLOR_COMPONENT_A_BIT
        };
        immutable VkPipelineColorBlendStateCreateInfo blend = 
        {
            sType:              VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
            pNext:              null,
            flags:              0,
            logicOpEnable:      VK_FALSE,
            logicOp:            VK_LOGIC_OP_COPY,
            attachmentCount:    1,
            pAttachments:       &blendAttachment,
            blendConstants:     [ 0f, 0f, 0f, 0f ]
        };

        // We need to create a layout.
        immutable VkPipelineLayoutCreateInfo layoutInfo =
        {
            sType:                  VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
            pNext:                  null,
            flags:                  0,
            setLayoutCount:         0,
            pSetLayouts:            null,
            pushConstantRangeCount: 0,
            pPushConstantRanges:    null
        };
        VkPipelineLayout layout = void;
        device.vkCreatePipelineLayout (&layoutInfo, callbacks, &layout).enforceSuccess;
        scope (exit) layout.safelyDestroyVK (device.vkDestroyPipelineLayout, device, layout, callbacks);

        // Now we can finally construct the pipeline!
        auto info                   = infoTemplate;
        info.pStages                = stages.ptr;
        info.pVertexInputState      = &vertexInput;
        info.pInputAssemblyState    = &assembly;
        info.pViewportState         = &view;
        info.pRasterizationState    = &rasterization;
        info.pMultisampleState      = &multisample;
        info.pDepthStencilState     = &depthStencil;
        info.pColorBlendState       = &blend;
        info.layout                 = layout;
        info.renderPass             = renderPasses.forward;

        VkPipeline output = nullPipeline;
        device.vkCreateGraphicsPipelines (nullPipelineCache, 1, &info, callbacks, &output);
        return output;
    }
}

/**
    Stores shaders required by the rendering pipelines.

    Loads and creates the vertex and fragment shader stages required by the rendering pipelines. In the future this
    should be expanded to load shaders from a configuration file.
*/
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
        _module:                nullShader,             // Must be changed.
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