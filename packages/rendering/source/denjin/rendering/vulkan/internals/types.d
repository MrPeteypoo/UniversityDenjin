/**
    Contains shader-suitable Vulkan types such as vectors and matrices.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: Copyright © 2017, Simon Peter Campbell
    License: MIT
*/
module denjin.rendering.vulkan.internals.types;

// Engine.
import denjin.maths : Vector;

// Aliases.
alias Vec3 = Vector!(float, 3);

/// The shader representation of a directional light.
struct DirectionalLight
{
    align (16)
    {
        Vec3 direction;  /// The direction of the light in world-space.
        Vec3 intensity;  /// The colour/intensity of the light.
    }
}
///
pure nothrow @safe @nogc unittest
{
    static assert (DirectionalLight.direction.offsetof == 0);
    static assert (DirectionalLight.intensity.offsetof == 16);

    static assert (DirectionalLight.sizeof == 32);
}

/// The shader representation of a point light.
struct PointLight
{
    align (4)
    {
        Vec3    position;   /// The position of the light in world-space.
        float   range;      /// The range of the point light.

        Vec3    intensity;  /// The colour/intensity of the light.
        float   aConstant;  /// The constant co-efficient for the attenuation formula.

        float   aLinear;    /// The linear co-efficient for the attenuation formula.
        float   aQuadratic; /// The quadratic co-efficient for the attenuation formula.
    }
}
///
pure nothrow @safe @nogc unittest
{
    static assert (PointLight.position.offsetof     == 0);
    static assert (PointLight.range.offsetof        == 12);

    static assert (PointLight.intensity.offsetof    == 16);
    static assert (PointLight.aConstant.offsetof    == 28);

    static assert (PointLight.aLinear.offsetof      == 32);
    static assert (PointLight.aQuadratic.offsetof   == 36);

    static assert (PointLight.sizeof == 40);
}

/// The shader representation of a spotlight.
struct Spotlight
{
    align (4)
    {
        Vec3    position;       /// The position of the light in world-space.
        float   coneAngle;      /// The angle of the cone in degrees.

        Vec3    direction;      /// The direction of the light in world-space.
        float   range;          /// The maximum range of the spotlight.

        Vec3    intensity;      /// The colour/intensity of the light.
        int     concentration;  /// How concentrated the beam of the spot light is, effects angular attenuation.

        float   aConstant;      /// The constant co-efficient for the attenuation formula.
        float   aLinear;        /// The linear co-efficient for the attenuation formula.
        float   aQuadratic;     /// The quadratic co-efficient for the attenuation formula.
        int     viewIndex;      /// The index of the view transform of the light.
    }
}
///
pure nothrow @safe @nogc unittest
{
    static assert (Spotlight.position.offsetof      == 0);
    static assert (Spotlight.coneAngle.offsetof     == 12);

    static assert (Spotlight.direction.offsetof     == 16);
    static assert (Spotlight.range.offsetof         == 28);

    static assert (Spotlight.intensity.offsetof     == 32);
    static assert (Spotlight.concentration.offsetof == 44);

    static assert (Spotlight.aConstant.offsetof     == 48);
    static assert (Spotlight.aLinear.offsetof       == 52);
    static assert (Spotlight.aQuadratic.offsetof    == 56);
    static assert (Spotlight.viewIndex.offsetof     == 60);

    static assert (Spotlight.sizeof == 64);
}