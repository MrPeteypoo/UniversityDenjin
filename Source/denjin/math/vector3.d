module denjin.math.vector3;


// Phobos.
import std.traits : isNumeric;


// Module properties.
@nogc:
@safe:
pure:
nothrow:


/**
A numeric structure representing a 3-dimensional vector of floats containing an x, y and z component.
See also Vector3T.
*/
alias Vector3 = Vector3T!(float);

/// 
unittest
{
    // Construction.
    auto vecA = Vector3 ();             // Most efficient but no default assignment of x, y and z.
    auto vecB = Vector3 (2f);           // Defaults each component to 0.
    auto vecC = Vector3 (3f, 4f, 5f);   // Assign a value to each component.
    auto vecD = Vector3.zero;           // Constant versions of common vectors also exist.

    assert (vecB.x == 2f && vecB.y == 2f && vecB.z == 2f);
    assert (vecC.x == 3f && vecC.y == 4f && vecC.z == 5f);
    assert (vecD.x == 0f && vecD.y == 0f && vecD.z == 0f);
}


/**
    A numeric structure representing a 3-dimensional vector containing an x, y and z component.
    The underlying type can be specified but must be numerical.

    Params:
        Number = The underlying numerical type of the vector.
*/
struct Vector3T(Number)
    if (isNumeric!(Number))
{
    // Members.
    Number  x = void;   /// The left/right component.
    Number  y = void;   /// The up/down component.
    Number  z = void;   /// The forward/back component.


    // Member aliases.
    alias a = x, i = x; 
    alias b = y, j = y; 
    alias c = z, k = z; 


    // Constants.
    enum zero       = Vector3T!Number (0);          /// Represents (0, 0, 0).
    enum one        = Vector3T!Number (1);          /// Represents (1, 1, 1).
    enum right      = Vector3T!Number (1, 0, 0);    /// Represents (1, 0, 0).
    enum up         = Vector3T!Number (0, 1, 0);    /// Represents (0, 1, 0).
    enum forward    = Vector3T!Number (0, 0, 1);    /// Represents (0, 0, 1).
    enum left       = Vector3T!Number (-1, 0, 0);   /// Represents (-1, 0, 0).
    enum down       = Vector3T!Number (0, -1, 0);   /// Represents (0, -1, 0).
    enum back       = Vector3T!Number (0, 0, -1);   /// Represents (0, 0, -1).


    /**
        Initialises each member of the vector to the given value.
    */
    this (in Number value)
    {
        this.x = value;
        this.y = value;
        this.z = value;
    }


    /**
        Initialises the vector with the given component values.
    */
    this (in Number x, in Number y, in Number z)
    {
        this.x = x;
        this.y = y;
        this.z = z;
    }

/+
    /**
        Constructs a 3D vector from a 2D vector.
    */
    this (in Vector2T!Number vector2, in Number z)
    {
        this.x = vector2.x;
        this.y = vector2.y;
        this.z = z;
    }


    /**
        Constructs a 3D vector from a 4D vector, discards the w component.
    */
    this (in Vector4T!Number vector4)
    {
        this.x = vector4.x;
        this.y = vector4.y;
        this.z = vector4.z;
    }

+/

}

///
unittest
{
    auto vecFloat = Vector3T!float();
    auto vecInt = Vector3T!int();
    auto vecUint = Vector3T!uint();
}