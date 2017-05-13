/**
    Enables the loading of assets such as meshes and materials which are used by the renderer.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: Copyright © 2017, Simon Peter Campbell
    License: MIT
*/
module denjin.assets.loading;

// Phobos. 
import std.conv         : to;
import std.algorithm    : move;
import std.stdio        : writeln;

// Engine.
import denjin.assets.rendering  : RenderMaterial, RenderMesh, addVertex, addTriangle;
import denjin.misc.ids          : MaterialID, MeshID, materialID, meshID;

// External.
import derelict.assimp3.types : aiMesh;

/// Loads a RenderMesh from an ASSIMP mesh at the given location.
void loadRenderMesh (ref RenderMesh[MeshID] meshes, in aiMesh* assimpMesh) nothrow 
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

        // Don't do anything if the mesh already exists.
        immutable id = name.meshID;
        if ((id in meshes) is null)
        {
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

            meshes[id] = move (renderMesh);
        }
    }
    catch (Throwable)
    {
        assert (false, "Uh oh");
    }
}

/// Loads a RenderMaterial with the given name (currently hard-coded).
void loadRenderMaterial(string name)(ref RenderMaterial[MaterialID] materials)
{
    try
    {
        writeln ("Reading material: ", name);
        immutable id = name.materialID;
        if ((id in materials) is null)
        {

            auto material = RenderMaterial (name.materialID);
            with (material)
            {
                setAlbedo (0.25f, 0.5f, 0.25f, 1f);
                smoothness      = 0.5f;
                reflectance     = 0.5f;
                conductivity    = 0f;
                albedoMap       = "textures/albedo/" ~ name ~ ".png";
                physicsMap      = "textures/physics/" ~ name ~ ".png";
                normalMap       = "textures/normal/" ~ name ~ ".png";

                static if (name == "arch")
                {
                }

                else static if (name == "bricks")
                {
                }

                else static if (name == "ceiling")
                {
                }

                else static if (name == "chain")
                {
                }

                else static if (name == "column_a")
                {
                }

                else static if (name == "column_b")
                {
                }

                else static if (name == "column_c")
                {
                }

                else static if (name == "details")
                {
                }

                else static if (name == "fabric_a")
                {
                    physicsMap  = "textures/physics/drapes.png";
                }

                else static if (name == "fabric_c")
                {
                    physicsMap  = "textures/physics/curtains.png";
                }

                else static if (name == "fabric_d")
                {
                    physicsMap  = "textures/physics/drapes.png";
                }

                else static if (name == "fabric_e")
                {
                    physicsMap  = "textures/physics/drapes.png";
                }

                else static if (name == "fabric_f")
                {
                    physicsMap  = "textures/physics/curtains.png";
                }

                else static if (name == "fabric_g")
                {
                    physicsMap  = "textures/physics/curtains.png";
                }

                else static if (name == "flagpole")
                {
                }

                else static if (name == "floor")
                {
                }

                else static if (name == "leaf")
                {
                }

                else static if (name == "Material")
                {
                }

                // Lion head.
                else static if (name == "Material__25")
                {
                }

                // Lion mantle.
                else static if (name == "Material__298")
                {
                }

                // Blank picture frame.
                else static if (name == "Material__47")
                {
                }

                // Flowers on pots.
                else static if (name == "Material__57")
                {
                }

                else static if (name == "roof")
                {
                }

                else static if (name == "vase")
                {
                }

                else static if (name == "vase_hanging")
                {
                }

                else static if (name == "vase_round")
                {
                }
    
                else
                {
                    static assert (false, "We don't handle this yet! " ~ name);
                }
            }
            materials[id] = move (material);
        }
    }
    catch (Throwable)
    {
    }
}