#version 450

//!< The uniform buffer scene specific information.
layout (std140, set = 0, binding = 0) uniform Scene
{
    mat4    projection;     //!< The projection transform which establishes the perspective of the vertex.
    mat4    view;           //!< The view transform representing where the camera is looking.

    vec3    camera;         //!< Contains the position of the camera in world space.
    vec3    ambience;       //!< The ambient lighting in the scene.
} scene;

layout (location = 0)   in      vec3    position;       //!< The world position of the fragment.
layout (location = 1)   in      vec3    lerpedNormal;   //!< The lerped world normal of the fragment, needs normalising.
layout (location = 2)   in      vec3    lerpedTangent;  //!< The lerped world tangent of the fragment, needs normalising
layout (location = 3)   in      vec2    uv;             //!< The texture co-ordinate for the fragment to use for texture mapping.
layout (location = 4)   flat in ivec3   material;       //!< The index of the physics map, albedo map and normal map.

layout (location = 0)   out     vec4    colour;         //!< The shaded colour of the fragment.

/**
    Shades the fragment with the normals.
*/
void main()
{
    const vec3 normal = normalize (lerpedNormal);
    colour = vec4 (0.5 + 0.5 * normal, 1.0);
}