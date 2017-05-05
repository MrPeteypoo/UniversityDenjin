/**
    Miscellaneous traits that are common across multiple type constraints.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: Copyright © 2017, Simon Peter Campbell
    License: MIT
*/
module denjin.rendering.traits.misc;

// Aliases.
alias isVector3 (T, ElementT)   = isVector!(T, ElementT, 3);
alias isVector3F (T)            = isVector!(T, float, 3);

/** 
    Checks if the given type meets the requirements of being used as a Vector in rendering systems.

    The given type will be checked to see if it has at least n-dimensions with the given element
    type. It must be a random access range or a static array with a length know at compile-time.
*/
template isVector (T, ElementT, size_t Dimensions)
    if (Dimensions > 0)
{
    import std.range : ElementType, isRandomAccessRange;
    import std.traits : isImplicitlyConvertible, isStaticArray;

    static if (!isStaticArray!T)
    {
        static assert (isRandomAccessRange!T);
    }

    static assert (isImplicitlyConvertible!(ElementType!T, ElementT));
    static assert (T.length >= Dimensions);

    enum isVector = true;
}
///
pure nothrow @safe @nogc unittest
{
    static assert (isVector!(short[4], int, 3));
    static assert (isVector!(float[3], float, 3));
    static assert (isVector!(float[4], float, 4));
}