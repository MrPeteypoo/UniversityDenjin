#version 450

/// Contains the properties of the material to be applied to the current fragment.
struct Material
{
    vec3    albedo;         //!< The base colour of the material.
    float   transparency;   //!< How transparent the surface is.
    float   roughness;      //!< Effects the distribution of specular light over the surface.
    float   reflectance;    //!< Effects the fresnel effect of dieletric surfaces.
    float   conductivity;   //!< Conductive surfaces absorb incoming light, causing them to be fully specular.
    vec3    normal;         //!< The normal of the material from a texture map.
} material;

/// A universal light which casts light on all objects.
struct DirectionalLight
{
    vec3 direction; //!< The direction of the light.
    vec3 intensity; //!< The colour and brightness of the light.
};

/// An area light which uniformly distributes light within a range.
struct PointLight
{
    vec3    position;   //!< The world location of the light.
    float   range;      //!< The maximum range of the light.

    vec3    intensity;  //!< The colour and brightness of the light.
    float   aConstant;  //!< The constant co-efficient for the attenuation formula.
    
    float   aLinear;    //!< The linear co-efficient for the attenuation formula.
    float   aQuadratic; //!< The quadratic co-efficient for the attenuation formula.
};

/// A constricted area light which distributes light like a cone.
struct Spotlight
{
    vec3    position;       //!< The world location of the light.
    float   coneAngle;      //!< The angle of the cone in degrees.
    
    vec3    direction;      //!< The direction of the light.
    float   range;          //!< The maximum range of the light.

    vec3    intensity;      //!< The colour and brightness of the light.
    float   concentration;  //!< Effects how focused the light is and how it distributes away from the centre.
    
    float   aConstant;      //!< The constant co-efficient for the attenuation formula.
    float   aLinear;        //!< The linear co-efficient for the attenuation formula.
    float   aQuadratic;     //!< The quadratic co-efficient for the attenuation formula.
};

//!< The uniform buffer scene specific information.
layout (std140, set = 0, binding = 0) uniform Scene
{
    mat4    projection;     //!< The projection transform which establishes the perspective of the vertex.
    mat4    view;           //!< The view transform representing where the camera is looking.

    vec3    camera;         //!< Contains the position of the camera in world space.
    vec3    ambience;       //!< The ambient lighting in the scene.
} scene;

layout (std140, set = 0, binding = 1) uniform DirectionalLights
{
    #define DirectionalLightsMax 50
    
    uint                count;                          //!< How many lights exist in the scene.
    DirectionalLight    lights[DirectionalLightsMax];   //!< A collection of light data.
} directionalLights;

layout (std140, set = 0, binding = 2) uniform PointLights
{
    #define PointLightsMax 50
    
    uint        count;                  //!< How many lights exist in the scene.
    PointLight  lights[PointLightsMax]; //!< A collection of light data.
} pointLights;

layout (std140, set = 0, binding = 3) uniform Spotlights
{
    #define SpotlightsMax 50
    
    uint        count;                  //!< How many lights exist in the scene.
    Spotlight   lights[SpotlightsMax];  //!< A collection of light data.
} spotlights;

//!< An array of samplers containing different texture formats.
layout (set = 1, binding = 0) uniform sampler2DArray textures[2];

// Globals.
const float pi              = 3.14159;
const float maxShininess    = 1024.f;

layout (location = 0)   in      vec3    worldPosition;  //!< The world position of the fragment.
layout (location = 1)   in      vec3    lerpedNormal;   //!< The lerped world normal of the fragment, needs normalising.
layout (location = 2)   in      vec3    lerpedTangent;  //!< The lerped world tangent of the fragment, needs normalising
layout (location = 3)   in      vec2    uv;             //!< The texture co-ordinate for the fragment to use for texture mapping.
layout (location = 4)   flat in ivec2   albedoIndex;    //!< The sampler/texture index of the albedo texture map.
layout (location = 5)   flat in ivec2   physicsIndex;   //!< The sampler/texture index of the smoothness/reflectance/conductivity texture map.
layout (location = 6)   flat in ivec2   normalIndex;    //!< The sampler/texture index of the normal map.

layout (location = 0)   out     vec4    fragmentColour; //!< The shaded colour of the fragment.


// Forward declarations.
void fetchMaterialProperties();
vec3 calculateNormal();
vec3 directionalLightContributions (const in vec3 normal, const in vec3 view);
vec3 pointLightContributions (const in vec3 position, const in vec3 normal, const in vec3 view);
vec3 spotlightContributions (const in vec3 position, const in vec3 normal, const in vec3 view);
vec3 calculateReflectance (const in vec3 l, const in vec3 n, const in vec3 v, const in vec3 e);
vec3 lambertDiffuse (const in float lDotN);
vec3 blinnPhongSpecular (const in vec3 l, const in vec3 n, const in vec3 v);
vec3 disneyDiffuse (const in float lDotN, const in float vDotN, const in float hDotV);
vec3 microfacetSpecular (const in vec3 l, const in vec3 n, const in vec3 h,
                         const in float lDotN, const in float vDotN, const in float hDotV);
vec3 fresnelReflectance (const in vec3 albedo, const in float lDotH);
float geometricAttenuation (const in float dotProduct);
float distribution (const in float hDotN);
vec3 halfVector (const in vec3 l, const in vec3 v);

/**
    Iterate through each light, calculating its contribution to the current fragment.
*/
void main()
{
    // Retrieve the material properties and use it for lighting calculations.
    fetchMaterialProperties();
    
    // Calculate the required lighting components.
    const vec3 q = worldPosition;
    const vec3 v = normalize (scene.camera - q);
    const vec3 n = normalIndex.x >= 0 ? calculateNormal() : normalize (lerpedNormal);
    
    // Accumulate the contribution of every light.
    const vec3 lighting =   directionalLightContributions (n, v) +
                            pointLightContributions (q, n, v) +
                            spotlightContributions (q, n, v);
    
    // Output the calculated fragment colour.
    fragmentColour = vec4 (scene.ambience + lighting, material.transparency);
}

/**
    Fetches the material properties of the fragment based on the index inputs.
*/
void fetchMaterialProperties()
{
    // Components are array-depth pairs, this allows us to retrieve the correct map.
    const vec4 albedo       = texture (textures[albedoIndex.x], vec3 (uv, float (albedoIndex.y)));
    const vec3 properties   = texture (textures[physicsIndex.x], vec3 (uv, float (physicsIndex.y))).xyz;

    // Disect the albedo.
    material.albedo         = albedo.rgb;
    material.transparency   = albedo.a;

    // Reflectance controls the fresnel effect of a material. Here we restrict the F0 co-efficient based conductivity.
    const float dielecticReflectance = 0.2;
    const float conductorReflectance = 1.0;

    // Roughness is optained by converting from a smoothness factor.
    material.roughness       = max (1.0 - properties.x, 0.0);
    material.conductivity    = properties.z;
    material.reflectance     = properties.y * mix (dielecticReflectance, conductorReflectance, material.conductivity);

    // Normal maps are optional.
    if (normalIndex.x >= 0)
    {
        material.normal = texture (textures[normalIndex.x], vec3 (uv, float (normalIndex.y))).xyz;
    }
}

/**
    Calculates the normal of the fragment using normal-mapping. This is heavily based on the algorithm 
    presented here: http://ogldev.atspace.co.uk/www/tutorial26/tutorial26.html
*/
vec3 calculateNormal()
{
    const vec3 normal       = normalize (lerpedNormal);
    const vec3 unitTangent  = normalize (lerpedTangent);
    const vec3 tangent      = normalize (unitTangent - dot (unitTangent, normal) * normal);
    const vec3 bitangent    = cross (tangent, normal);
    const mat3 tbnMatrix    = mat3 (tangent, bitangent, normal);
    const vec3 bumpedNormal = 2.0 * material.normal - vec3 (1.0);
    return normalize (tbnMatrix * bumpedNormal);
}

/**
    Calculates the lighting contribution of a directional light at the given index.
*/
vec3 directionalLightContribution (const in uint index, const in vec3 normal, const in vec3 view)
{
    // Directional lights don't need attenuation.
    const DirectionalLight light = directionalLights.lights[index];
    const vec3 l = -light.direction;
    const vec3 E = light.intensity;

    return calculateReflectance (l, normal, view, E);
}

/**
    Calculates the lighting contribution of a point light at the given index.
*/
vec3 pointLightContribution (const in uint index, const in vec3 position, const in vec3 normal, const in vec3 view)
{
    // Point lights use uniform attenuation.
    const PointLight light = pointLights.lights[index];

    // We'll need the distance and direction from the light to the surface for attenuation.
    const vec3  bigL    = light.position - position;
    const float dist    = length (bigL);
    const vec3  l       = bigL / dist;

    // Point light attenuation formula is: 1 / (Kc + Kl * d + Kq * d * d).
    const float attenuation = light.range >= dist ? 
        1.0 / (light.aConstant + light.aLinear * dist + light.aQuadratic * dist * dist) :
        0.0;

    if (attenuation > 0.0)
    {
        // Scale the intensity accordingly.
        const vec3 E = light.intensity * attenuation;

        return calculateReflectance (l, normal, view, E);
    }
    else
    {
        return vec3 (0.0);
    }
}

/**
    Calculates the lighting contribution of a spotlight at the given index.
*/
vec3 spotlightContribution (const in uint index, const in vec3 position, const in vec3 normal, const in vec3 view)
{
    // Spotlights require a special luminance attenuation and cone attenuation.
    const Spotlight light = spotlights.lights[index];

    // We'll need the distance and direction from the light to the surface for attenuation.
    const vec3  bigL    = light.position - position;
    const float dist    = length (bigL);
    const vec3  l       = bigL / dist;
    const vec3  R       = light.direction;
    const float p       = light.concentration;

    // Luminance attenuation formula is: pow (max {-R.l, 0}), p) / (Kc + kl * d + Kq * d * d).
    const float luminance = light.range >= dist ? 
        pow (max (dot (-R, l), 0.0), p) / (light.aConstant + light.aLinear * dist + light.aQuadratic * dist * dist) :
        0.0;

    // Cone attenuation is: acos ((-l.R)) > angle / 2. Attenuate using smoothstep.
    const float lightAngle  = degrees (acos (max (dot (-l, R), 0.0)));
    const float halfAngle   = light.coneAngle / 2.0;
    const float coneCutOff  = lightAngle <= halfAngle ? smoothstep (1.0, 0.75, lightAngle / halfAngle) : 0.0;

    // Put it all together.
    const float attenuation = luminance * coneCutOff;

    if (attenuation > 0.0)
    {
        return calculateReflectance (l, normal, view, light.intensity * attenuation);
    }
    else
    {
        return vec3 (0.0);
    }
}

/**
    Calculates the lighting contribution of every directional light in the scene.
*/
vec3 directionalLightContributions (const in vec3 normal, const in vec3 view)
{
    vec3 lighting = vec3 (0.0);

    for (uint i = 0; i < directionalLights.count; ++i)
    {
        lighting += directionalLightContribution (i, normal, view);
    }

    return lighting;
}

/**
    Calculates the lighting contribution of every point light in the scene.
*/
vec3 pointLightContributions (const in vec3 position, const in vec3 normal, const in vec3 view)
{
    vec3 lighting = vec3 (0.0);

    for (uint i = 0; i < pointLights.count; ++i)
    {
        lighting += pointLightContribution (i, position, normal, view);
    }

    return lighting;
}

/**
    Calculates the lighting contribution of every spotlight in the scene.
*/
vec3 spotlightContributions (const in vec3 position, const in vec3 normal, const in vec3 view)
{
    vec3 lighting = vec3 (0.0);

    for (uint i = 0; i < spotlights.count; ++i)
    {
        lighting += spotlightContribution (i, position, normal, view);
    }

    return lighting;
}

/**
    Calculates the diffuse and specular component of a light with the given parameters.
    
    Params:
        l = The surface to light direction.
        n = The surface normal of the fragment.
        v = The surface to view/eye direction.
        e = The intensity of the light.
*/
vec3 calculateReflectance (const in vec3 l, const in vec3 n, const in vec3 v, const in vec3 e)
{
    // Determine whether we can actually light the surface.
    const float lDotN = max (dot (l, n), 0.0);

    if (lDotN == 0.0)
    {
        return vec3 (0.0);
    }

    // Support physically based and non-physically based shading techniques.
    #ifndef PHYSICALLY_BASED_SHADING
        
        // Conductive surfaces absorb light so no diffuse reflection occurs.
        const float diffuseContribution = 1.0 - material.conductivity;

        // We need the half vector for reflectance calculations.
        const vec3  h       = halfVector (l, v);
        const float hDotV   = dot (h, v);
        const float vDotN   = max (dot (v, n), 0.0001);

        // Calculate and scale diffuse and specular reflectance.
        const vec3 diffuse = diffuseContribution > 0.0 ? 
            disneyDiffuse (lDotN, vDotN, hDotV) * diffuseContribution : 
            vec3 (0.0);

        const vec3 specular = microfacetSpecular (l, n, h, lDotN, vDotN, hDotV);
        return e * (diffuse + specular);

    #else
        
        return e * (lambertDiffuse (lDotN) + blinnPhongSpecular (l, n, v));

    #endif
}

/**
    The most basic diffuse lighting model. Lambertian diffuse causes a relatively uniform reflectance by disregarding
    surface roughness.
*/
vec3 lambertDiffuse (const in float lDotN)
{
    return material.albedo * lDotN;
}

/**
    An inexpensive specular model which attempts to approximate shininess and specular colour from PBS parameters.
*/
vec3 blinnPhongSpecular (const in vec3 l, const in vec3 n, const in vec3 v)
{
    // First we need to interpret PBS parameters for shading.
    const vec3  albedo          = material.albedo;
    const float luminosity      = albedo.r * 0.2126f + albedo.g * 0.7151f + albedo.b * 0.0722f;
    const vec3  specularColour  = mix (vec3 (material.reflectance), vec3 (luminosity), material.conductivity);

    const float shininess       = ((2.0 / pow (material.roughness, 2.0)) - 2.0) * 4.0;

    // Using the half vector we can calculate the specularity of a surface.
    return shininess > 0.0 ? 
        specularColour * pow (max (dot (halfVector (l, v), n), 0.0), shininess) 
        : vec3 (0.0);
}

/**
    A state-of-the-art diffuse model from Disney as presented here (slide 17): 
    http://blog.selfshadow.com/publications/s2016-shading-course/hoffman/s2016_pbs_recent_advances_v2.pdf
*/
vec3 disneyDiffuse (const in float lDotN, const in float vDotN, const in float hDotV)
{
    // The base colour is simply the albedo.
    const vec3 baseColour = material.albedo;

    // Calculate fresnel weightings FL and FV.
    const float fresnelL = pow (1.0 - lDotN, 5.0);
    const float fresnelV = pow (1.0 - vDotN, 5.0);

    // Now we need a retro-reflection weighting RR.
    const float roughReflection = 2.0 * material.roughness * pow (hDotV, 2.0);

    // We can start putting the formula together now. 
    // fLambert = baseColour / PI.
    const vec3 lambert = baseColour / pi;

    // fretro-reflection: fLambert * RR * (FL + FV + FL * FV * (RR - 1)).
    const vec3 retroReflection = lambert * roughReflection * 
        (fresnelL + fresnelV + fresnelL * fresnelV * (roughReflection - 1.0));
    
    // fd = fLambert * (1 - 0.5 * FL) * (1 - 0.5 * FV) + fretro-reflection.
    return lambert * (1.0 - 0.5 * fresnelL) * (1.0 - 0.5 * fresnelV) + retroReflection;
}

/**
    Using a similar structure to the Cook-Torrance model, calculates the specular lighting of the fragment using
    fresnel, geometry and distribution components:
    http://blog.selfshadow.com/publications/s2016-shading-course/hoffman/s2016_pbs_recent_advances_v2.pdf
*/
vec3 microfacetSpecular (const in vec3 l, const in vec3 n, const in vec3 h,
    const in float lDotN, const in float vDotN, const in float hDotV)
{
    // Conductive materials reflect using their albedo, everything else reflects using white.
    const vec3 albedo = mix (vec3 (material.reflectance), material.albedo, material.conductivity);

    // Perform the required dot products.
    const float lDotH = dot (l, h);
    const float hDotN = dot (h, n);

    // Calculate the three attenuation components.
    const vec3  f = fresnelReflectance (albedo, lDotH);
    const float g = geometricAttenuation (lDotN) * geometricAttenuation (vDotN);
    const float d = distribution (hDotN);

    // Calculate the denominator.
    const float denominator = 4.0 * lDotN * vDotN;
    
    // Return the specular effect.
    return denominator > 0.2 ? (f * g * d) / denominator : vec3 (0.0);
}

/**
    Calcualtes the fresnel effect for specular lighting based on Schlick's approximation.
*/
vec3 fresnelReflectance (const in vec3 albedo, const in float lDotH)
{
    // F(0) = F0 + (1 - F0) * pow (1 - cos(0), 5).
    return albedo + (1.0 - albedo) * pow (1.0 - lDotH, 5.0);
}

/**
    Calculates an attenuation factor representing self-shadowing based on the Smith function.
    http://jcgt.org/published/0003/02/03/
    http://blog.selfshadow.com/publications/s2013-shading-course/rad/s2013_pbs_rad_notes.pdf
*/
float geometricAttenuation (const in float dotProduct)
{
    const float roughSqr    = material.roughness * material.roughness;
    const float dotSqr      = dotProduct * dotProduct;

    const float numerator   = 2.0 * dotProduct;
    const float denominator = dotProduct + sqrt (roughSqr + (1.0 - roughSqr) * dotSqr);

    return numerator / denominator;
}

/**
    Calculate a distribution attenuation factor using either GGX, Blinn-Phong or Beckmann:
    http://blog.selfshadow.com/publications/s2013-shading-course/rad/s2013_pbs_rad_notes.pdf
    http://blog.selfshadow.com/publications/s2013-shading-course/lazarov/s2013_pbs_black_ops_2_notes.pdf
*/
float distribution (const in float hDotN)
{
    // Values required for multiple distribution functions.
    const float hDotNSqr = hDotN * hDotN;
    const float roughSqr = material.roughness * material.roughness;

    // GGX.
    const float ggxNumerator    = roughSqr;
    const float ggxDenominator  = pi * pow (hDotNSqr * (roughSqr - 1.0) + 1.0, 2.0);

    return ggxNumerator / ggxDenominator;

    // Blinn-Phong.
    //return ((material.roughness + 2.0) / (pi * 2.0)) * pow (hDotN, material.roughness * maxShininess);

    // Beckmann.
    /*const float tanNumerator    = 1.0 - hDotNSqr;
    const float tanDenominator  = hDotNSqr * roughSqr;
    const float tangent         = tanNumerator / tanDenominator;

    const float exponential = exp (-tangent);
    const float denominator = pi * roughSqr * (hDotNSqr * hDotNSqr);
    return exponential / denominator;*/
}

/**
    Calculates the vector half way between the given surface-to-light and surface-to-viewer directions.
*/
vec3 halfVector (const in vec3 l, const in vec3 v)
{
    return normalize (l + v);
}