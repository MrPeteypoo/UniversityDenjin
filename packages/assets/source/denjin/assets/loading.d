/**
    Enables the loading of assets such as meshes and materials which are used by the renderer.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: Copyright © 2017, Simon Peter Campbell
    License: MIT
*/
module denjin.assets.loading;

// Phobos. 
import std.conv     : to;
import std.stdio    : writeln;

// Engine.
import denjin.assets.types  : RenderMaterial, RenderMesh, addVertex, addTriangle;
import denjin.misc.ids      : materialID, meshID;

// External.
import derelict.assimp3.types : aiMesh;

RenderMesh loadRenderMesh (in aiMesh* assimpMesh) nothrow 
in
{
    assert (assimpMesh !is null);
    assert (assimpMesh.mVertices !is null);
    assert (assimpMesh.mNormals !is null);
    assert (assimpMesh.mTangents !is null);
    assert (assimpMesh.mTextureCoords.length > 0);
}
body
{
    try
    {
        // We need a D-string representation of the name.
        immutable name = assimpMesh.mName.data.ptr.to!string;
        writeln ("Reading mesh: ", name);

        // Construct a mesh with a unique ID.
        auto renderMesh = RenderMesh (name.meshID);
        
        // Speed the process up by reserving enough memory.
        immutable reservation = cast (size_t) assimpMesh.mNumVertices;
        renderMesh.positions.reserve (reservation);
        renderMesh.normals.reserve (reservation);
        renderMesh.tangents.reserve (reservation);
        renderMesh.textureCoordinates.reserve (reservation);

        // Add the vertices.
        foreach (i; 0..reservation)
        {
            immutable pos   = assimpMesh.mVertices[i];
            immutable norm  = assimpMesh.mNormals[i];
            immutable tan   = assimpMesh.mTangents[i];
            immutable uv    = assimpMesh.mTextureCoords[0][i];

            renderMesh.addVertex ([pos.x, pos.y, pos.z],
                                  [norm.x, norm.y, norm.z],
                                  [tan.x, tan.y, tan.z],
                                  [uv.x, uv.y]);
        }

        // Add the elements.
        renderMesh.elements.reserve (cast (size_t) assimpMesh.mNumFaces * 3);
        foreach (i; 0..assimpMesh.mNumFaces)
        {
            const face      = assimpMesh.mFaces[i];
            const indices   = face.mNumIndices;
            if (indices >= 3)
            {
                renderMesh.addTriangle (face.mIndices[0], face.mIndices[1], face.mIndices[2]);
            }
        }

        return renderMesh;
    }
    catch (Throwable)
    {
        assert (false, "Uh oh");
    }
}

/// Loads a RenderMaterial with the given name (currently hard-coded).
RenderMaterial loadRenderMaterial (in string name) pure nothrow @nogc
{
    auto material = RenderMaterial (name.materialID);

    with (material)
    {
        smoothness      = 0.5f;
        reflectance     = 0.5f;
        conductivity    = 0f;
        setAlbedo (0.25f, 0.5f, 0.25f, 1f);

        if (name == "arch")
        {
            physicsMap      = "";
            albedoMap       = "";
            normalMap       = "";
        }

        else if (name == "bricks")
        {
            physicsMap      = "";
            albedoMap       = "";
            normalMap       = "";
        }

        else if (name == "ceiling")
        {
            physicsMap      = "";
            albedoMap       = "";
            normalMap       = "";
        }

        else if (name == "chain")
        {
            physicsMap      = "";
            albedoMap       = "";
            normalMap       = "";
        }

        else if (name == "column_a")
        {
            physicsMap      = "";
            albedoMap       = "";
            normalMap       = "";
        }

        else if (name == "column_b")
        {
            physicsMap      = "";
            albedoMap       = "";
            normalMap       = "";
        }

        else if (name == "column_c")
        {
            physicsMap      = "";
            albedoMap       = "";
            normalMap       = "";
        }

        else if (name == "details")
        {
            physicsMap      = "";
            albedoMap       = "";
            normalMap       = "";
        }

        else if (name == "fabric_a")
        {
            physicsMap      = "";
            albedoMap       = "";
            normalMap       = "";
        }

        else if (name == "fabric_c")
        {
            physicsMap      = "";
            albedoMap       = "";
            normalMap       = "";
        }

        else if (name == "fabric_d")
        {
            physicsMap      = "";
            albedoMap       = "";
            normalMap       = "";
        }

        else if (name == "fabric_e")
        {
            physicsMap      = "";
            albedoMap       = "";
            normalMap       = "";
        }

        else if (name == "fabric_f")
        {
            physicsMap      = "";
            albedoMap       = "";
            normalMap       = "";
        }

        else if (name == "fabric_g")
        {
            physicsMap      = "";
            albedoMap       = "";
            normalMap       = "";
        }

        else if (name == "flagpole")
        {
            physicsMap      = "";
            albedoMap       = "";
            normalMap       = "";
        }

        else if (name == "floor")
        {
            physicsMap      = "";
            albedoMap       = "";
            normalMap       = "";
        }

        else if (name == "leaf")
        {
            physicsMap      = "";
            albedoMap       = "";
            normalMap       = "";
        }

        else if (name == "Material")
        {
            physicsMap      = "";
            albedoMap       = "";
            normalMap       = "";
        }

        else if (name == "Material__25")
        {
            physicsMap      = "";
            albedoMap       = "";
            normalMap       = "";
        }

        else if (name == "Material__298")
        {
            physicsMap      = "";
            albedoMap       = "";
            normalMap       = "";
        }

        else if (name == "Material__47")
        {
            physicsMap      = "";
            albedoMap       = "";
            normalMap       = "";
        }

        else if (name == "Material__57")
        {
            physicsMap      = "";
            albedoMap       = "";
            normalMap       = "";
        }

        else if (name == "roof")
        {
            physicsMap      = "";
            albedoMap       = "";
            normalMap       = "";
        }

        else if (name == "vase")
        {
            physicsMap      = "";
            albedoMap       = "";
            normalMap       = "";
        }

        else if (name == "vase_hanging")
        {
            physicsMap      = "";
            albedoMap       = "";
            normalMap       = "";
        }

        else if (name == "vase_round")
        {
            physicsMap      = "";
            albedoMap       = "";
            normalMap       = "";
        }
    }

    return material;
}