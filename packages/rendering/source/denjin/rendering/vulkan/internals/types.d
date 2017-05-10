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
alias Mat4 = float[4][4];
alias Vec3 = Vector!(float, 3);

/**
    Wraps an array of T elements in a package which can be used in a shader. The generated array cannot be larger than
    16KiB.
    
    Params:
        T           = The type of the element being stored in the array.
        capacity    = The total number of elements that can be stored in the array.
*/
struct UniformArray (T, size_t capacity = 1)
{
    static assert ((Array.sizeof + 16) < 16_384, "A UniformArray cannot be larger than 16KiB.");

    align (16)
    {
        alias Array = Element[capacity]; /// The array is sized to the given capacity of aligned objects.

        uint    length; /// The number of elements that have data written to them.
        Array   array;  /// The number of elements writable in the array.
    }

    /// Each element is forcefully aligned to Vulkans requirements of 16-bytes.
    align (16) struct Element
    {
        T item;             /// The item being aligned.
        alias item this;    /// The item can be used normally as the given type.
    }

    /// The uniform array is a subtype of the primary array.
    alias array this;
}
///
pure nothrow @safe @nogc unittest
{
    static assert (UniformArray!(ubyte).Element.sizeof == 16);
    static assert (UniformArray!(float).Element.sizeof == 16);
    static assert (UniformArray!(double).Element.sizeof == 16);
    static assert (UniformArray!(float[3]).Element.sizeof == 16);
    static assert (UniformArray!(float[5]).Element.sizeof == 32);
}

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

    static assert (Spotlight.sizeof == 60);
}