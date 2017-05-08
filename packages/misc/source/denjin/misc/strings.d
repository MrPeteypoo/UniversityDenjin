/**
    Miscellaneous functionality for string types.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: Copyright © 2017, Simon Peter Campbell
    License: MIT
*/
module denjin.misc.strings;

// Phobos.
import std.digest.crc   : crc32Of;
import std.traits       : Unqual;
import std.utf          : byChar;

/// Hash a string based on its contents, not it's pointer. Uses a method similar to boost::hash.
uint toHash (string s) pure nothrow @nogc
{
    // Handle the case where a string is null.
    if (s is null) return 0;

    // We can retrieve an array of four ubytes by calculating the CRC.
    immutable hash = crc32Of (s.byChar);
    static assert (is(Unqual!(typeof(hash)) == ubyte[4]));

    // We can put the four ubytes together to create a uint.
    return (hash[0] << 24) | (hash[1] << 16) | (hash[2] << 8) | hash[3];
}
///
pure nothrow @nogc unittest
{
    // Any string will do.
    immutable hash1 = toHash ("bob");
    assert (hash1 == 1_085_393_909);

    // An empty string will always return zero.
    immutable hash2 = toHash ("");
    assert (hash2 == 0);
}