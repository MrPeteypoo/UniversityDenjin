/**
    Contains asset system and scene system ID types.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: Copyright © 2017, Simon Peter Campbell
    License: MIT
*/
module denjin.misc.ids;

// Engine.
import denjin.misc.strings : toHash;

/// Identifies unique renderable instances of a mesh which can be rendered in a scene.
alias InstanceID = uint;

/// Identifies unique lights in a scene.
alias LightID = uint;

/// Identifies unique meshes which may be referenced by many instances.
alias MeshID = uint;

/// Identifies unique materials which describe how a surface should be modelled when rendered.
alias MaterialID = uint;

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