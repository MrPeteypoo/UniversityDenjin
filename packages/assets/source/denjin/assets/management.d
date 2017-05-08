/**
    Functionality allowing for the containment and management of engine assets.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: Copyright © 2017, Simon Peter Campbell
    License: MIT
*/
module denjin.assets.management;

// Engine.
import denjin.assets.types  : RenderMaterial, RenderMesh;
import denjin.misc.ids      : MaterialID, MeshID;
import denjin.misc.strings  : toHash;

/// Contains assets required by various parts of the engine that must be
struct Assets
{
    private 
    {
        RenderMaterial[MaterialID]  m_materials;  /// Contains every material available.
        RenderMesh[MeshID]          m_meshes;     /// Contains every mesh available.
    }

    /**
        In an ideal world, this would load every asset specified in the given configuration file. Due to time 
        constraints this does not happen yet.
    */
    this (in string config)
    {
        
    }

    /// Returns a dynamic array containing every loaded material asset.
    const(RenderMaterial[]) materials() const pure nothrow @property
    {
        return m_materials.values;
    }

    /// Returns a dynamic array containing every loaded mesh asset.
    const(RenderMesh[]) meshes() const pure nothrow @property
    {
        return m_meshes.values;
    }

    /// Returns a pointer to the material corresponding to the given MaterialID. Null if not found.
    const(RenderMaterial*) material (in MaterialID id) const pure nothrow @safe @nogc
    {
        return id in m_materials;
    }

    /// Returns a pointer to the mesh corresponding to the given MeshID. Null if not found.
    const(RenderMesh*) mesh (in MeshID id) const pure nothrow @safe @nogc
    {
        return id in m_meshes;
    }
}
///
pure nothrow @safe @nogc unittest
{
    import denjin.rendering.traits : isAssets;

    // The struct must meet the requirements of the renderer.
    static assert (isAssets!Assets);
}

/// Returns the MaterialID representation of the given file location string.
MaterialID materialID (in string fileLocation) pure nothrow @nogc
{
    return cast (MaterialID) fileLocation.toHash;
}

/// Returns the MeshID representation of the given file location string.
MeshID meshID (in string fileLocation) pure nothrow @nogc
{
    return cast (MeshID) fileLocation.toHash;
}