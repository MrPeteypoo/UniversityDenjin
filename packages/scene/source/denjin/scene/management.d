/**
    Contains the scene management system used by the engine.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: Copyright © 2017, Simon Peter Campbell
    License: MIT
*/
module denjin.scene.management;

// Phobos.
import std.algorithm : each;

// Engine
import denjin.misc.ids      : MeshID;
import denjin.scene.types   : RenderCamera, RenderInstance, RenderDLight, RenderPLight, RenderSLight;

/// Contains a representation of a renderable seen as required by the renderer.
struct Scene
{
    enum float[3] upDirection           = [0f, 1f, 0f];     /// The up direction of the world.
    enum float[3] ambientLightIntensity = [.1f, .1f, .1f];  /// Ambient light to be applied to every surface.
    private
    {
        RenderCamera                m_camera;       /// Currently only one camera is supported.
        RenderInstance[][MeshID]    m_instances;    /// A collection of instances grouped by mesh ID.
        RenderDLight[]              m_dLights;      /// A collection of directional lights.
        RenderPLight[]              m_pLights;      /// A collection of point lights.
        RenderSLight[]              m_sLights;      /// A collection of spotlights.
    }

    /// Gets a reference to the stored camera data.
    ref const(RenderCamera) camera() const pure nothrow @safe @nogc @property { return m_camera; };

    /// Gets the collection of directional lights.
    const(RenderDLight[]) directionalLights() const pure nothrow @safe @nogc @property { return m_dLights; }

    /// Gets the collection of point lights.
    const(RenderPLight[]) pointLights() const pure nothrow @safe @nogc @property { return m_pLights; }

    /// Gets the collection of spotlights.
    const(RenderSLight[]) spotlights() const pure nothrow @safe @nogc @property { return m_sLights; }

    /// Gets the collection of instances that correspond to the given MeshID.
    const(RenderInstance[]) instancesByMesh (in MeshID id) const pure nothrow @safe @nogc
    {
        // We must check if the given entry exists.
        const entry = id in m_instances;
        return entry is null ? [] : *entry;
    }

    /// Gets a range giving access to every instance in the scene. This is a particular expensive operation.
    RenderInstance[] instances() const pure nothrow @property
    {
        RenderInstance[] array;
        m_instances.values.each!((ref group)
        {
            array.reserve (group.length);
            array ~= group[0..$];
        });
        return array;
    }
}
///
pure nothrow @safe @nogc unittest
{
    import denjin.rendering.traits : isScene;

    // Ensure the scene meets the requirements of the renderer.
    static assert (isScene!Scene);
}