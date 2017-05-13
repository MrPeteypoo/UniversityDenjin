#version 450

//!< We must declare which built-in shader attributes we need.
out gl_PerVertex
{
    vec4 gl_Position;
};

//!< The uniform buffer scene specific information.
layout (std140, set = 0, binding = 0) uniform Scene
{
    mat4    projection;     //!< The projection transform which establishes the perspective of the vertex.
    mat4    view;           //!< The view transform representing where the camera is looking.

    vec3    camera;         //!< Contains the position of the camera in world space.
    vec3    ambience;       //!< The ambient lighting in the scene.
} scene;

layout (location = 0)   in          vec3    position;       //!< The local position of the current vertex.
layout (location = 1)   in          vec3    normal;         //!< The local normal vector of the current vertex.
layout (location = 2)   in          vec3    tangent;        //!< The local tangent vector of the current vertex.
layout (location = 3)   in          vec2    uv;             //!< The texture co-ordinates for the vertex, used for mapping a texture to the object.
layout (location = 4)   in          ivec3   material;       //!< The indices of the texture maps for the object.
layout (location = 5)   in          mat4x3  model;          //!< The model transform representing the position and rotation of the object in world space.

layout (location = 0)   out         vec3    worldPosition;  //!< The world position to be interpolated for the fragment shader.
layout (location = 1)   out         vec3    worldNormal;    //!< The world normal to be interpolated for the fragment shader.
layout (location = 2)   out         vec3    worldTangent;   //!< The world tangent to be interpolated for the fragment shader.
layout (location = 3)   out         vec2    texturePoint;   //!< The texture co-ordinate for the fragment to use for texture mapping.
layout (location = 4)   flat out    ivec2   albedoIndex;    //!< The sampler/texture index of the albedo texture map.
layout (location = 5)   flat out    ivec2   physicsIndex;   //!< The sampler/texture index of the smoothness/reflectance/conductivity texture map.
layout (location = 6)   flat out    ivec2   normalIndex;    //!< The sampler/texture index of the normal map.

/**
    Given an int, this will create a sampler/texture index ivec2 by splitting the int using bitmasks.
*/
ivec2 decodeMaterialIndex (const in int value);

/**
    Applies transformations to the vertex position to place it in the scene and outputs data to the fragment shader. 
*/
void main()
{
    // We need the position with a homogeneous value and we need to create the PVM transform.
    const mat4 projectionViewModel  = scene.projection * scene.view * mat4 (model);
    const mat3 truncatedModel       = mat3 (model);
    const vec4 homogeneousPosition  = vec4 (position, 1.0);

    // Set the outputs first.
    worldPosition   = model * homogeneousPosition;
    worldNormal     = truncatedModel * normal;
    worldTangent    = truncatedModel * tangent;
    texturePoint    = uv;
    physicsIndex    = decodeMaterialIndex (material.x);
    albedoIndex     = decodeMaterialIndex (material.y);
    normalIndex     = decodeMaterialIndex (material.z);

    // We need to invert the up position because Vulkan draws from the top-left not bottom-left.
    gl_Position     = projectionViewModel * homogeneousPosition;
    gl_Position.y   = -gl_Position.y;
    //gl_Position.z   = (gl_Position.z + gl_Position.w) / 2.0;
}

ivec2 decodeMaterialIndex (const in int value)
{
    // The most significant bit determines whether the value is an index. The 8 least significant bits are the sampler
    // index, the other 23 are the texture index.
    const int samplerMask   = 0x800000FF;
    const int textureMask   = 0x7FFFFF00;
    const int samplerBits   = value & samplerMask;
    const int textureBits   = value & textureMask;

    return ivec2 (samplerBits, textureBits >> 8);
}