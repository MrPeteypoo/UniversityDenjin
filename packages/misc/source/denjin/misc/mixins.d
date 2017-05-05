/**
    Provides helpful metaprogramming functions that don't exist in Phobos but are helpful in the construction of games
    and/or the engine itself.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: Copyright © 2017, Simon Peter Campbell
    License: MIT
*/
module denjin.misc.mixins;

/**
    Produces code which will create a parameter list based on the count and given parameters. If $(DDOC_PARAM Count) is
    less than $(DDOC_PARAM Params) then the list will be truncated at the end. If $(DDOC_PARAM Count) is more than 
    $(DDOC_PARAM Params) then the last value in $(DDOC_PARAM Params) will be used to fill the remaining places in the 
    list.
 
    Params: 
        count   = How many parameters are required, this must be more than zero.
        Params  = The parameter values to use when producing the list.

    Returns: 
        A string representation of list of parameters.
*/
template generateParameters (size_t count, Params...)
    if (Params.length > 0 && count > 0)
{
    template code (size_t count, size_t i, alias value, Params...)
    {
        static if (i < count)
        {
            enum prefix     = i != 0 ? ", " : "";
            enum parameter  = prefix ~ value.stringof;

            static if (Params.length != 0)
            {
                // Use the parameters given in the parameter pack whilst they're available.
                enum code = parameter ~ code!(count, i + 1, Params);
            }

            else
            {
                enum code = parameter ~ code!(count, i + 1, value);
            }
        }

        else
        {
            enum code = "";
        }
    }

    enum generateParameters = code!(count, size_t (0), Params);
}
///
@safe unittest
{
    import std.algorithm : count;

    // A convenient way to construct parameter packs from basic types.
    enum threeStrings = generateParameters!(3, "bob", "jim", "john");
    static assert (threeStrings == `"bob", "jim", "john"`);

    // The count is allowed to be higher than the passed parameters, the last member will be repeated.
    enum repeated = generateParameters!(10, 0, 1, 2, 10);
    static assert (repeated == "0, 1, 2, 10, 10, 10, 10, 10, 10, 10");

    // Extra parameters are truncated when the count is lower than the total parameters.
    enum truncCount = 5;
    enum truncated  = generateParameters!(truncCount, 3.14, 360.0, 1.0 / 4, 1.0, 20.456, 6.0, 7.0);
    static assert (truncated.count (',') == truncCount - 1);

    // Types can be mixed and matched effectively, though using classes and structs is undefined behaviour.
    enum mixAndMatch = generateParameters!(6, false, true, 'c', "string", -1L, 5UL);
    static assert (mixAndMatch == `false, true, 'c', "string", -1L, 5LU`);
}

/** 
    Generates a property to access a component and optionally, any aliases to the given property. This will not add a
    member to the struct/class, it will merely provide accessors to a member.

    Params:
        Type            = The type of the member being accessed by the property.
        memberAccessor  = How the member should be accessed by the property.
        propertyName    = The desired symbol name of the property to be generated.
        Aliases         = Any additional aliases that will redirect to $(DDOC_PARAM propertyName).

    Returns: 
        A string containing code to create the desired member property.
*/
template generateMemberProperty (Type, string memberAccessor, string propertyName, Aliases...)
{
    import std.array : replace;

    enum generateMemberProperty = 
        (getter ~ setter ~ aliases)
            .replace ("$Type", Type.stringof)
            .replace ("$PropertyName", propertyName)
            .replace ("$MemberAccessor", memberAccessor);
    
    enum getter = "
        $Type $PropertyName() @property const
        {
            return $MemberAccessor;
        }";

    enum setter = "
        void $PropertyName (in $Type value) @property
        {
            $MemberAccessor = value;
        }";

    enum aliases = Aliases.length == 0 ? "" : generateAliases!(propertyName, Aliases);
}
///
@safe unittest
{
    // We're going to create a class with an int member "m_a" and a property which gets/sets it. We will also add
    // multiple aliases which access the generated property.
    struct Widget
    { 
        private int m_value;

        public:
            mixin (generateMemberProperty!(int, "m_value", "a", "b", "c", "d"));
    }

    // We're going to instantiate and object and set the value, then we can confirm the property does what we expect.
    auto widget = Widget();
    widget.a = 5;
    assert (widget.a == 5 && widget.b == widget.a && widget.c == widget.a && &widget.d == &widget.a);

    widget.d = 10;
    assert (widget.a == 10);
}

/// Generates a series of aliases to the desired symbol.
/// Params:
///     referTo = The type/function/variable that the generated aliases will refer to.
///     Aliases = A collection of string aliases that will be generated to refer to referTo.
template generateAliases (string referTo, Aliases...)
    if (referTo.length > 0 && Aliases.length > 0)
{
    import std.array : replace;

    static if (Aliases.length > 1)
    {
        enum generateAliases = generateAliases!(referTo, Aliases[1 .. $]) ~ newAlias;
    }
    
    else
    {
        enum generateAliases = newAlias;
    }

    private enum newAlias = 
        "alias $Alias = $ReferTo;"
            .replace ("$Alias", Aliases[0])
            .replace ("$ReferTo", referTo);
}
///
@safe unittest
{
    // Aliases can be easily generated by doing the following.
    struct Vec1
    {
        double x;
        mixin (generateAliases!("x", "i", "r", "u"));
    }

    // Now we can access the same member with different names at no cost.
    auto vec1 = Vec1 (255.0);
    assert (vec1.x == 255.0 && vec1.i == 255.0 && vec1.r == 255.0 && vec1.u == 255.0);
    assert (vec1.x == vec1.i && vec1.x == vec1.r && vec1.x == vec1.u);
    assert (&vec1.x == &vec1.i && &vec1.x == &vec1.r && &vec1.x == &vec1.r && &vec1.x == &vec1.u);
}

/**
    Generates an enum of the given name and type, constructed with the given parameters. This may seem pointless and 
    verbose but it allows for objects to be constructed as enums with the same flexibility that generateParameters 
    provides.

    Params:
        Type        = The type of the enum being generated.
        name        = The identifier of the enum.
        paramCount  = How many parameters the type requires to construct.
        Params      = Parameters to pass to generateParameters to construct the enum with.

    Returns:
        A string containing code to create the desired enum with the given parameters.
*/
template generateMemberEnum (Type, string name, size_t paramCount, Params...)
{
    enum params = paramCount > 0 && Params.length > 0 ? generateParameters!(paramCount, Params) : "";
    enum generateMemberEnum = "enum " ~ name ~ "=" ~ Type.stringof ~ "(" ~ params ~ ");";
}
///
@safe unittest
{
    // We're going to create a struct to hold compile-time constants.
    struct A
    {
        mixin (generateMemberEnum!(double, "pi", 1, 3.14159));
        mixin (generateMemberEnum!(int, "a", 1, 2));
    }

    // Now we can access enums in the new class.
    static assert (is (typeof (A.pi) == double) && A.pi == 3.14159);
    static assert (is (typeof (A.a) == int) && A.a == 2);
}

/**
    Generates code which will unroll an array loop between the given range. The specified symbol will be replaced in 
    the given string with an index value.
 
    Params:
        start       = The first index in the loop.
        end         = When to stop incrementing the loop (exclusive, this value will not be used as an index).
        loopBody    = The body of the loop containing the given symbol, this will be duplicated for each index.
        symbol      = The symbol to be replaced in the loopBody string with each index value of the loop.
        stride      = How much to increment the index by.

    Returns:
        A string containing unrolled looping code.
*/
template unrollLoop (long start, long end, string loopBody, string symbol = "$@", long stride = 1)
{
    import std.array    : replace;
    import std.conv     : to;

    static if (start < end)
    {
        enum unrollLoop = loopBody.replace (symbol, start.to!string) ~ 
            unrollLoop!(start + stride, end, loopBody, symbol, stride);
    }
    
    else
    {
        enum unrollLoop = "";
    }
}
/// 
@safe unittest
{
    // An array to read values from and an array to write the values to.
    const int[3] read = [576, 128, 0];
    int[read.length] write = void;

    // Normally we would do a for loop, however instead we can unroll the loop by defining the body in a string.
    enum loopBody = "write[$@] = read[$@];";
    enum unrolledLoop = unrollLoop!(0, read.length, loopBody);

    // Now we have code we can use to mixin an unrolled loop.
    static assert (unrolledLoop == "write[0] = read[0];write[1] = read[1];write[2] = read[2];");

    // We can prove that the code works by mixing it in and checking the results.
    mixin (unrolledLoop);
    for (size_t i = 0; i < read.length; ++i)
    {
        assert (write[i] == read[i]);
    }
}