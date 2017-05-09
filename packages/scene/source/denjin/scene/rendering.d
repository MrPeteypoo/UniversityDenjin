/**
    Common types representing renderable scene objects such as instances, cameras, lights, etc.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: Copyright © 2017, Simon Peter Campbell
    License: MIT
*/
module denjin.scene.rendering;

// Engine.
import denjin.maths     : Vector3f;
import denjin.misc.ids  : InstanceID, LightID, MaterialID, MeshID;

/// Represents the camera viewport as used by the renderer.
struct RenderCamera
{
    Vector3f    position            = Vector3f.zero;    /// The position of the camera in world-space.
    Vector3f    direction           = Vector3f.zero;    /// The direction that the camera is facing in world-space.
    float       fieldOfView         = 75f;              /// The field of view of the camera in degrees.
    float       nearPlaneDistance   = .1f;              /// How close objects can be to the camera before being clipped.
    float       farPlaneDistance    = 1000f;            /// How far objects can be away from the camera before being clipped.
}
///
pure nothrow @safe @nogc unittest
{
    import denjin.rendering.traits : isCamera;
    static assert (isCamera!RenderCamera);
}

/// Represents a renderable instance of a mesh.
struct RenderInstance
{
    InstanceID  id;                     /// The unique ID of the instance.
    MeshID      meshID;                 /// The unique ID of the mesh to render for this instance.
    MaterialID  materialID;             /// The unique ID of the material to render the mesh with for this instance.
    bool        isStatic;               /// Indicates whether the instance ever moves.
    float[3][4] transformationMatrix =  /// The position, rotation and scale of the instance.
    [
        [1, 0, 0],
        [0, 1, 0],
        [0, 0, 1],
        [0, 0, 0]
    ];
}
///
pure nothrow @safe @nogc unittest
{
    import denjin.rendering.traits : isInstance;
    static assert (isInstance!RenderInstance);
}

/// A base struct for light types which are rendered in a scene.
struct RenderLight
{
    LightID     id;                         /// The unique identifier for the light.
    bool        isStatic;                   /// Indicates whether the light ever moves.
    bool        isShadowCaster;             /// Indicates whether the light casts shadows or not.
    Vector3f    intensity = Vector3f.zero;  /// The colour intensity of the light hitting a surface.
}

/// Represents a directional light in a scene.
struct RenderDLight
{
    RenderLight common;                     /// The base type containing common light data.
    Vector3f    direction = Vector3f.zero;  /// The direction of the incoming light.

    /// Subtype from the common light data.
    alias common this;
}
///
pure nothrow @safe @nogc unittest
{
    import denjin.rendering.traits : isDirectionalLight;
    static assert (isDirectionalLight!RenderDLight);
}

/// Represents a point light in a scene.
struct RenderPLight
{
    RenderLight common;                         /// The base type containing common light data.
    Vector3f    position    = Vector3f.zero;    /// The position of the light in world space.
    Vector3f    attenuation = Vector3f.zero;    /// Constant, linear, and quadratic attenuation co-efficients for the light.
    float       radius      = 40f;              /// The radius around the world position that will be effected by light.

    /// Subtype from the common light data.
    alias common this;
}
///
pure nothrow @safe @nogc unittest
{
    import denjin.rendering.traits : isPointLight;
    static assert (isPointLight!RenderPLight);
}

/// Represents a spotlight in a scene.
struct RenderSLight
{
    RenderLight common;                         /// The base type containing common light data.
    Vector3f    position    = Vector3f.zero;    /// The position of the light in world space.
    Vector3f    direction   = Vector3f.zero;    /// The direction of the light being cast.
    Vector3f    attenuation = Vector3f.zero;    /// Constant, linear, and quadratic attenuation co-efficients for the light.
    float       range       = 40f;              /// How far forward the light can reach.
    float       coneAngle   = 90f;              /// The angle of the spotlight cone in degrees.

    /// Subtype from the common light data.
    alias common this;
}
///
pure nothrow @safe @nogc unittest
{
    import denjin.rendering.traits : isSpotlight;
    static assert (isSpotlight!RenderSLight);
}
