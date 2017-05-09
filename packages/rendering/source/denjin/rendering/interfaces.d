/**
    Contains implementation-agnostic dynamic interfaces for rendering systems.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: Copyright © 2017, Simon Peter Campbell
    License: MIT
*/
module denjin.rendering.interfaces;

// Engine.
import denjin.misc.ids          : MaterialID, MeshID;
import denjin.rendering.traits  : isAssets, isCamera, isDirectionalLight, isInstance, isMaterial, isMesh, isPointLight, 
                                  isScene, isSpotlight, isVector;

/**
    An interface to assets management systems which contain models and textures that the rendering needs to load in
    order to represent a scene.

    See_Also:
        isMaterial, isMesh
*/
interface IAssets (Material, Mesh)
    if (isMaterial!Material &&
        isMesh!Mesh)
{
    /// Retrieves data for every material that needs to be loaded.
    inout(Material[]) materials() inout @property;

    /// Retrieves data for every mesh that needs to be loaded.
    inout(Mesh[]) meshes() inout @property;

    /// Retrieve the data for a unique material which corresponds to the given ID.
    ref inout(Material) material (in MaterialID id) inout;

    /// Retrieve the data for a unique mesh which corresponds to the given ID.
    ref inout(Mesh) mesh (in MeshID id) inout;
}

/**
    An interface to rendering systems. 
    
    Rendering systems can use any asset or scene management system, provided it meets the requirements set out by 
    isAssets and isScene. Construction should be performed by derived classes in their constructor, the interface
    functions can then be used to polymorphically manage a renderer.
    
    See_Also:
        isAssets, isScene
*/
interface IRenderer (Assets, Scene)
    if (isAssets!Assets && isScene!Scene)
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

/**
    An interface for a scene management system. 
    
    This provides the renderers with the necessary data to render objects in a frame. The interface follows the 
    requirements set out by the isScene constraint. This is a dynamic interface and as such will cause run-time 
    overhead. It exists primarily as a schematic for a scene management system which an engine implements. The 
    renderers do not require systems to inherit from this interface, it just provides a guideline for people to follow.

    Params:
        Vec3F = The type to use

    See_Also:
        isScene, isCamera, isInstance, isDirectionalLight, isPointLight, isSpotlight
*/
interface IScene (Vec3F, Camera, Instance, DirectionalLight, PointLight, Spotlight)
    if (isVector!(Vec3F, float, 3) && 
        isCamera!Camera && 
        isInstance!Instance &&
        isDirectionalLight!DirectionalLight && 
        isPointLight!PointLight && 
        isSpotlight!Spotlight)
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
