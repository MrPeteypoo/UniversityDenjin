/**
    Contains asset system and scene system ID types.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: Copyright © 2017, Simon Peter Campbell
    License: MIT
*/
module denjin.rendering.ids;

/// Identifies unique renderable instances of a mesh which can be rendered in a scene.
alias InstanceID = uint;

/// Identifies unique lights in a scene.
alias LightID = uint;

/// Identifies unique meshes which may be referenced by many instances.
alias MeshID = uint;

/// Identifies unique materials which describe how a surface should be modelled when rendered.
alias MaterialID = uint;