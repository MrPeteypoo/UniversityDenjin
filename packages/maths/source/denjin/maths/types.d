/**
    A collection of type aliases for mathematical data types.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: Copyright © 2017, Simon Peter Campbell
    License: MIT
*/
module denjin.maths.types;

// Engine.
import denjin.maths.vector;

// 2D vectors.
alias Vector2(T)    = Vector!(T, 2);
alias Vector2b      = Vector2!byte;
alias Vector2s      = Vector2!short;
alias Vector2i      = Vector2!int;
alias Vector2l      = Vector2!long;

alias Vector2ub     = Vector2!ubyte;
alias Vector2us     = Vector2!ushort;
alias Vector2ui     = Vector2!uint;
alias Vector2ul     = Vector2!ulong;

alias Vector2f      = Vector2!float;
alias Vector2d      = Vector2!double;
alias Vector2r      = Vector2!real;

// 3D vectors.
alias Vector3(T)    = Vector!(T, 3);
alias Vector3b      = Vector3!byte;
alias Vector3s      = Vector3!short;
alias Vector3i      = Vector3!int;
alias Vector3l      = Vector3!long;

alias Vector3ub     = Vector3!ubyte;
alias Vector3us     = Vector3!ushort;
alias Vector3ui     = Vector3!uint;
alias Vector3ul     = Vector3!ulong;

alias Vector3f      = Vector3!float;
alias Vector3d      = Vector3!double;
alias Vector3r      = Vector3!real;

// 4D vectors.
alias Vector4(T)    = Vector!(T, 4);
alias Vector4b      = Vector4!byte;
alias Vector4s      = Vector4!short;
alias Vector4i      = Vector4!int;
alias Vector4l      = Vector4!long;

alias Vector4ub     = Vector4!ubyte;
alias Vector4us     = Vector4!ushort;
alias Vector4ui     = Vector4!uint;
alias Vector4ul     = Vector4!ulong;

alias Vector4f      = Vector4!float;
alias Vector4d      = Vector4!double;
alias Vector4r      = Vector4!real;