/**
    Manages uniform buffer objects, giving shaders access to frame-specific rendering data.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: Copyright © 2017, Simon Peter Campbell
    License: MIT
*/
module denjin.rendering.vulkan.internals.uniforms;

// Engine.
import denjin.rendering.vulkan.internals.types;

/// Creates, stores and destroys uniform buffer data which shaders can access.
struct Uniforms
{
    
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