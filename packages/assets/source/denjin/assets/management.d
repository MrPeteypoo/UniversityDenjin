/**
    Functionality allowing for the containment and management of engine assets.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: Copyright © 2017, Simon Peter Campbell
    License: MIT
*/
module denjin.assets.management;

// Phobos.
import std.meta         : AliasSeq;
import std.string       : toStringz;

// Engine.
import denjin.assets.loading    : loadRenderMaterial, loadRenderMesh;
import denjin.assets.types      : RenderMaterial, RenderMesh;
import denjin.misc.ids          : MaterialID, MeshID;

// External.
import derelict.assimp3.assimp;
import derelict.assimp3.types;

/// Contains assets required by various parts of the engine that must be
struct Assets
{
    private 
    {
        RenderMaterial[MaterialID]  m_materials;  /// Contains every material available.
        RenderMesh[MeshID]          m_meshes;     /// Contains every mesh available.
    }

    /// Ensures the ASSIMP3 library is loaded.
    static this()
    {
        DerelictASSIMP3.load();
    }

    /**
        In an ideal world, this would load every asset specified in the given configuration file. Due to time 
        constraints this does not happen yet.
    */
    this (in string config)
    {
        scope (failure) clear;
        hardCodedMaterials;
        hardCodedMeshes;
    }

    /// Manually clears stored resources.
    void clear() pure nothrow
    {
        m_materials.clear;
        m_meshes.clear;
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

    /// In the future we'll load from a config file. For now we will just load testing files.
    private void hardCodedMeshes()
    {
        immutable   sponza  = "models/sponza.dae";
        enum        flags   = aiProcess_GenNormals | aiProcess_CalcTangentSpace | aiProcess_ImproveCacheLocality | 
                              aiProcess_JoinIdenticalVertices;
        const auto  scene   = aiImportFile (sponza.toStringz, flags);

        if (scene is null)
        {
            assert (false, "Sponza couldn't be loaded. Commit sudoku.");
        }

        // Ensure we clean up after ourselves.
        scope (exit) aiReleaseImport (scene);

        // Now we can add each mesh.
        foreach (i; 0..scene.mNumMeshes)
        {
            m_meshes.loadRenderMesh (scene.mMeshes[i]);
        }
    }

    /// In the future we'll load from a config file. For now we will just load testing data.
    private void hardCodedMaterials() nothrow
    {
        enum materials = AliasSeq!("arch", "bricks", "ceiling", "chain", "column_a", "column_b", "column_c", 
                                   "fabric_a", "fabric_c", "fabric_d", "fabric_e", "fabric_f", "fabric_g", "flagpole",
                                   "floor", "leaf", "Material", "Material__25", "Material__298", "Material__47", 
                                   "Material__57", "roof", "vase", "vase_hanging", "vase_round");

        foreach (matName; materials)
        {
            m_materials.loadRenderMaterial!(matName);
        }
    }
}
///
pure nothrow @safe @nogc unittest
{
    import denjin.rendering.traits : isAssets;

    // The struct must meet the requirements of the renderer.
    static assert (isAssets!Assets);
}