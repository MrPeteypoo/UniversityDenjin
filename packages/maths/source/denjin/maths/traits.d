/**
    A collection of type constraints testing if a type is mathematically based.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: Copyright © 2017, Simon Peter Campbell
    License: MIT
*/
module denjin.maths.traits;

/**
    Tests if the given type is capable of being used as a vector, either statically or dynamically.

    Params:
        T           = The type to check.
        isStatic    = Checks whether the type is implicitly convertible to a static array.
        dimensions  = Checks if the vector has the desired dimensions. Zero will cause this check to be ignored.
*/
template isVector (T, bool isStatic = false, size_t dimensions = 0)
{
    import std.meta     : anySatisfy;
    import std.range    : ElementType, isRandomAccessRange;
    import std.traits   : ImplicitConversionTargets, isArray, isImplicitlyConvertible, isStaticArray;

    alias targets       = ImplicitConversionTargets!T;
    alias ElementT      = ElementType!T;
    enum range          = isRandomAccessRange!T || anySatisfy!(isRandomAccessRange, targets);
    enum anyArray       = isArray!T || isImplicitlyConvertible!(T, ElementT[]) || anySatisfy!(isArray, targets);

    static if (!isStatic)
    {
        enum isVector = range || anyArray;
    }
    else static if (anyArray)
    {
        enum staticArray    = isStaticArray!T || anySatisfy!(isStaticArray, targets);
        enum staticLength   = __traits (compiles, T.length);

        static if (dimensions != 0)
        {
            enum isVector = isImplicitlyConvertible!(T, ElementT[dimensions]);
        }
        else static if (staticLength)
        {
            enum isVector = isImplicitlyConvertible!(T, ElementT[T.length]);
        }
        else
        {
            enum isVector = staticArray;
        }
    }
    else
    {
        enum isVector = false;
    }
}

enum isDynamicVector (T) = isVector!(T, false, 0);
///
pure nothrow @safe @nogc unittest
{
    import denjin.maths.types : Vector3f, Vector2i, Vector3ub, Vector4r;

    static assert (isDynamicVector!(float[3]));
    static assert (isDynamicVector!(float[]));
    static assert (isDynamicVector!(Vector3f));
    static assert (isDynamicVector!(Vector2i));
    static assert (isDynamicVector!(Vector3ub));
    static assert (isDynamicVector!(Vector4r));
    
    static assert (!isDynamicVector!(int));
    static assert (!isDynamicVector!(double));
}

/// Tests if the given type is capable of being used as a vector which has a length which is known at compile-time.
enum isStaticVector (T, size_t dimensions = 0) = isVector!(T, true, dimensions);
///
pure nothrow @safe @nogc unittest
{
    import denjin.maths.types : Vector3f, Vector2i, Vector3ub, Vector4r;

    static assert (isStaticVector!(float[2],    2));
    static assert (isStaticVector!(Vector2i,    2));
    static assert (isStaticVector!(Vector3f,    3));
    static assert (isStaticVector!(Vector3ub,   3));
    static assert (isStaticVector!(Vector4r,    4));

    static assert (!isStaticVector!(double,     1));
    static assert (!isStaticVector!(char,       1));
    static assert (!isStaticVector!(float[],    2));
}