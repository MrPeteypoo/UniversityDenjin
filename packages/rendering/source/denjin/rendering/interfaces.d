/**
    Contains implementation-agnostic dynamic interfaces for rendering systems.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: MIT
*/
module denjin.rendering.interfaces;

/// An interface to assets management systems which contain models and textures that the rendering needs to load in
/// order to represent a scene.
interface IAssets
{

}

/// An interface to rendering systems.
interface IRenderer
{
    /// Requests the renderer stop what it's doing, shutdown and clear its resources.
    void clear() nothrow;

    /// Requests the renderer load any resources it may need and prepare for rendering.
    void load();

    /// Requests the renderer resets any resolution-dependent data as it may have changed.
    void reset (in uint width, in uint height);

    /// Requests the renderer perform any pre-rendering tasks it needs to.
    void update (in float deltaTime);

    /// Requests that a frame be rendered by the GPU.
    /// Params: deltaTime = The number of seconds since the last update.
    void render() nothrow;
}