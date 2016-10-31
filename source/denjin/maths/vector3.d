/**
    Contains a templatised three-dimensional vector structure including common utility functions associated with
    vector mathematics.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: MIT
*/
module denjin.maths.vector3;


// Phobos.
import std.traits : isNumeric, isSigned;


/**
    A templatised Vector which can contain any numerical data type and can be as large as you wish.
    
    Params:
        Number = A numerical type to use as the underlying data type of the Vector.
        Dimensions = Specifies the dimensions the Vector represents and therefore how many components are stored.
*/
struct Vector (Number, size_t Dimensions)
    if (isNumeric!Number && Dimensions > 0)
{    
    // Members.
    Number[dimensions] array = void; /// The underlying vector data.


    // Template info.
    alias Vector    = Vector!(Number, Dimensions);  /// The complete usable type.
    alias Type      = Number;                       /// The underlying type used to store data.
    enum dimensions = Dimensions;                   /// How many dimenions of space the vector represents.
    

    // 1D short-hand.
    alias   x = array[0],   /// The right/left component.
            i = x,          /// ditto
            s = x,          /// ditto
            u = x,          /// ditto
            r = x;          /// The red colour channel.
            
    enum    zero   = Vector (0),                            /// Each component is zero: (0...).
            one    = Vector (1),                            /// Each component is one: (1...).
            right  = Vector (mixin (parameters (1, 0)));    /// Represents (1, 0...);
    
    static if (isSigned!Number)
        enum left = Vector (mixin (parameters (-1, 0))); /// Represents (-1, 0...).


    // 2D short-hand.
    static if (Dimensions >= 2)
    {
        alias   y = array[1],   /// The up/down component.
                j = y,          /// ditto
                t = y,          /// ditto
                v = y,          /// ditto
                g = y;          /// The green colour channel.

        enum up = Vector (mixin (parameters (0, 1, 0))); /// Represents (0, 1, 0...).

        static if (isSigned!Number)
            enum down = Vector (mixin (parameters (0, -1, 0))); /// Represents (0, -1, 0...).
    }


    // 3D short-hand.
    static if (Dimensions >= 3)
    {
        alias   z = array[2],   /// The forward/backward component.
                k = z,          /// ditto
                p = z,          /// ditto
                b = z;          /// The blue colour channel.

        enum forward = Vector (mixin (parameters (0, 0, 1, 0))); /// Represents (0, 0, 1, 0...).

        static if (isSigned!Number)
            enum backward = Vector (mixin (parameters (0, 0, -1, 0))); /// Represents (0, 0, -1, 0...).
    }


    // 4D short-hand.
    static if (Dimensions >= 4)
    {
        alias   w = array[3],   /// The fourth-dimensional axis component.
                l = w,          /// ditto
                q = w,          /// ditto
                a = w;          /// The alpha colour channel for transparency.
    }


    /// Sets each component of the vector to the given value.
    this (in Number value)
    {
        foreach (i; 0 .. dimensions)
        {
            array[i] = value;
        }
    }

    /// Creates a vector by setting each component to the specified values. The number of parameters being passed must
    /// match the dimensional size of the vector.
    /// Params: 
    ///     values = A list of parameters to use to initialise each component of the vector.
    this (Number...)(in Number values)
        if (values.length == Dimensions)
    {
        foreach (i; 0 .. Dimensions)
        {
            array[i] = values[i];
        }
    }

    
    
    private:

        /// Produces a string to mixin a parameter list for component-wise construction of a vector.
        /// Params: 
        ///     Args = A pack of specified parameters, the last will be used as the value for unspecified values. 
        auto parameters (T...)(in T args)
            if (args.length > 0)
        {
            auto        code    = "" ~ args[0];
            immutable   length  = args.length;

            foreach (i; 1 .. Dimensions)
            {
                code ~= i < length ? ", " ~ args[i] : ", " ~ args[length - 1];
            }

            return code;
        }
}
///
unittest
{
    // Most efficient constructor, data is not set to any value.
    immutable vec1f = Vector!(float, 1);
    
    // Sets each component to zero.
    immutable vec2f = Vector!(float, 2)(0f);    
    assert (vec2f.x == 0f && vec2f.y == 0f);

    // Short-hand exists for common vector values.
    immutable vec3f = Vector!(float, 3).forward;
    assert (vec3f.x == 0f && vec3f.y == 0f && vec3f.z == 1f);

    // Can be constructed with vectors, values are extracted.
    immutable vec4f = Vector!(float, 4)(vec1f, vec2f, 0f);
    assert (vec4f.x == vec1f.x && vec4f.y == vec2f.x && vec4f.z == vec2f.y && vec4f.w == 0f);
    
    // Component-wise construction is also available. Array accessor notation is supported.
    immutable vec5f = Vector!(float, 5)(1f, 2f, 3f, 4f, 5f);
    assert (vec5f[0] == 1f && vec5f[1] == 2f && vec5f[2] == 3f && vec5f[3] == 4f && vec5[4] == 5f);

    // Short-hand component access is available up to 4D vectors.
    assert (vec1f.x == vec1f.i && vec1f.x == vec1f.s && vec1f.x == vec1f.r && vec1f.x == vec1f.u);
    assert (vec2f.y == vec2f.j && vec2f.y == vec2f.t && vec2f.y == vec2f.g && vec2f.x == vec2f.v);
    assert (vec3f.z == vec3f.k && vec3f.z == vec3f.p && vec3f.z == vec3f.b);
    assert (vec4f.w == vec4f.l && vec4f.w == vec4f.q && vec4f.w == vec4f.a);
}


/**
    A numeric structure representing a three-dimensional vector of floats containing an x, y and z component.
    See_Also: Vector3T.
*/
alias Vector3 = Vector3T!float;
/// 
unittest
{
    // Construction.
    auto vecA = Vector3();              // Most efficient but no default assignment of x, y and z.
    auto vecB = Vector3 (2f);           // Defaults each component to 2.
    auto vecC = Vector3 (3f, 4f, 5f);   // Assign a value to each component.
    auto vecD = Vector3.zero;           // Constant versions of common vectors also exist.
    assert (vecB.x == 2f && vecB.y == 2f && vecB.z == 2f);
    assert (vecC.x == 3f && vecC.y == 4f && vecC.z == 5f);
    assert (vecD.x == 0f && vecD.y == 0f && vecD.z == 0f);
}


/**
    A numeric structure representing a three-dimensional vector containing an x, y and z component.
    The underlying type can be specified but must be numerical.

    Params: Number = The underlying numerical type of the vector.
*/
struct Vector3T(Number)
    if (isNumeric!Number)
{
    // Members.
    Number  x = void;   /// The left/right component.
    alias   i = x,      /// ditto
            s = x,      /// ditto
            u = x,      /// ditto
            r = x;      /// The red colour channel.

    Number  y = void;   /// The up/down component.
    alias   j = y,      /// ditto
            t = y,      /// ditto
            v = y,      /// ditto
            g = y;      /// The green colour channel. 

    Number  z = void;   /// The forward/back component.
    alias   k = z,      /// ditto
            p = z,      /// ditto
            b = z;      /// The blue colour channel.


    // Constants.
    enum zero       = Vector3T!Number (0);          /// Represents (0, 0, 0).
    enum one        = Vector3T!Number (1);          /// Represents (1, 1, 1).
    enum right      = Vector3T!Number (1, 0, 0);    /// Represents (1, 0, 0).
    enum up         = Vector3T!Number (0, 1, 0);    /// Represents (0, 1, 0).
    enum forward    = Vector3T!Number (0, 0, 1);    /// Represents (0, 0, 1).
    enum left       = Vector3T!Number (-1, 0, 0);   /// Represents (-1, 0, 0).
    enum down       = Vector3T!Number (0, -1, 0);   /// Represents (0, -1, 0).
    enum back       = Vector3T!Number (0, 0, -1);   /// Represents (0, 0, -1).


    /// Initialises each member of the vector to the given value.
    this (in Number value)
    {
        this.x = value;
        this.y = value;
        this.z = value;
    }


    /// Initialises the vector with the given component values.
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