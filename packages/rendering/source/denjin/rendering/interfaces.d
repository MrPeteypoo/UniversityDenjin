/**
    Contains implementation-agnostic dynamic interfaces for rendering systems.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: MIT
*/
module denjin.rendering.interfaces;

// Engine.
import denjin.rendering.assets  : isAssets;
import denjin.rendering.ids     : MeshID;
import denjin.rendering.scene   : isCamera, isDirectionalLight, isInstance, isPointLight, isScene, isSpotlight, 
                                  isVector3F;

/// An interface to assets management systems which contain models and textures that the rendering needs to load in
/// order to represent a scene.
interface IAssets
{

}

/// An interface to rendering systems.
/// See_Also:
///     isAssets, isScene
interface IRenderer (Assets, Scene)
    //if (isAssets!Asserts && isScene!Scene)
{
    /// Requests the renderer stop what it's doing, shutdown and clear its resources.
    void clear() nothrow;

    /// Requests the renderer load any resources it may need and prepare for rendering.
    /// Params:
    ///     assets  = Contains assets that need to be loaded before rendering the next frame.
    ///     scene   = Contains static and dynamic instances of objects which will be rendered in the future.
    void load (in ref Assets assets, in ref Scene scene);

    /// Requests the renderer resets any resolution-dependent data as it may have changed.
    void reset (in uint width, in uint height);

    /// Requests the renderer perform any pre-rendering tasks it needs to.
    void update (in float deltaTime);

    /// Requests that a frame be rendered by the GPU with the given scene objects.
    void render (in ref Scene scene) nothrow;
}

/// An interface for a scene management system. This provides the renderers with the necessary data to render objects
/// in a frame. The interface follows the requirements set out by the isScene constraint. This is a dynamic interface
/// and as such will cause run-time overhead. It exists primarily as a schematic for a scene management system which
/// an engine implements. The renderers do not require systems to inherit from this interface, it just provides a
/// guideline for people to follow.
///
/// Params:
///     Vec3F = The type to use
/// See_Also:
///     isScene, isVector3F, isCamera, isInstance, isDirectionalLight, isPointLight, isSpotlight
interface IScene (Vec3F, Camera, Instance, DirectionalLight, PointLight, Spotlight)
    if (isVector3F!Vec3F && isCamera!Camera && isInstance!Instance &&
        isDirectionalLight!DirectionalLight && isPointLight!PointLight && isSpotlight!Spotlight)
{
    /// Should return a 3D unit vector describing the up direction of the world.
    @property inout(Vec3F) upDirection() inout;

    /// Should return a 3D vector with RGB channels ranging from 0f to 1f, this lighting will be applied to everything.
    @property inout(Vec3F) ambientLightIntensity() inout;

    /// Contains data which describes the camera to use when rendering the scene.
    @property ref inout(Camera) camera() inout;

    /// A collection of instances to be rendered.
    @property inout(Instance[]) instances() inout;

    /// A collection of instances to be rendered which all use the same mesh corresponding to the given MeshID.
    inout(Instance[]) instancesByMesh (in MeshID meshID) inout;

    /// A collection of directional lights active in the scene.
    @property inout(DirectionalLight[]) directionalLights() inout;

    /// A collection of point lights active in the scene.
    @property inout(PointLight[]) pointLights() inout;

    /// A collection of spotlights active in the scene.
    @property inout(Spotlight[]) spotlights() inout;
}
///
pure nothrow @safe @nogc unittest
{
    import denjin.rendering.ids;
    import denjin.rendering.scene : isScene;

    struct Camera
    {
        float[3] position;
        float[3] direction;
        float fieldOfView() const @property { return 75f; }
        float nearPlaneDistance() const @property { return .3f; }
        float farPlaneDistance() const { return 300f; }
    }
    struct Instance
    {
        InstanceID id;
        MeshID meshID() const { return MeshID.init; }
        MaterialID materialID() const @property { return MaterialID.init; }
        bool isStatic;
        float[4][3] transformationMatrix;
    }
    struct DirectionalLight
    {
        LightID id;
        bool isStatic() const { return true; }
        immutable(bool) isShadowCaster() const { return false; }
        float[3] direction;
        immutable float[3] intensity;
    }
    struct PointLight
    {
        enum LightID id = 0;
        bool isStatic;
        bool isShadowCaster;
        float radius;
        float[3] position;
        immutable(float[3]) intensity;
        immutable(float[3]) attenuation() const { return [0,0,0]; }
    }
    struct Spotlight
    {
        DirectionalLight dLight;
        alias dLight this;
        float range;
        float coneAngle;
        float[3] position;
        int[3] attenuation;
    }

    alias Scene = IScene!(float[3], Camera, Instance, DirectionalLight, PointLight, Spotlight);
    static assert (isScene!Scene);
}