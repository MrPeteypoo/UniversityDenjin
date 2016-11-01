/**
    Provides helpful metaprogramming functions that don't exist in Phobos but are helpful in the construction of games
    and/or the engine itself.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: MIT
*/
module denjin.utility.meta;


/// Produces code which will create a parameter list based on the count and given parameters. If Count is less than
/// Params then the list will be truncated at the end. If Count is more than Params then the last value in Params will
/// be used to fill the remaining places in the list.
/// Params: 
///     Count   = How many parameters are required, this must be more than zero.
///     Params  = The parameter values to use when producing the list.
string parameters (alias Count, Params...)() @property
    if (Count.max >= Params.length)
{
    import std.meta;// : aliasSeqOf;
    import std.range;// : iota;

    string code = "";

    foreach (i; aliasSeqOf!(iota (0, Count)))
    {
        static if (i == 0)
        {
            // Don't add the comma on the first parameter.
            code ~= Params[i].stringof;
        }
        else static if (i < Params.length)
        {
            // Use the parameters given in the parameter pack whilst they're available.
            code ~= ", " ~ Params[i].stringof;
        }
        else
        {
            // Use the last given value for all parameters not specified by the parameter pack.
            code ~= ", " ~ Params[$-1].stringof;
        }
    }

    return code;
}
///
unittest
{
    // A convenient way to construct parameter packs from basic types.
    immutable threeStrings = parameters!(3, "bob", "jim", "john");
    static assert (threeStrings == `"bob", "jim", "john"`);

    // The count is allowed to be higher than the passed parameters, the last member will be repeated.
    immutable repeated = parameters!(10, 0, 1, 2, 10);
    static assert (repeated == "0, 1, 2, 10, 10, 10, 10, 10, 10, 10");

    // Extra parameters are truncated when the count is lower than the total parameters.
    immutable truncated = parameters!(5, 3.14, 360.0, 1.0 / 4, 1.0, 20.456, 6.0, 7.0);
    static assert (truncated == "3.14, 360.000, 0.25, 1.00000, 20.456");

    // Types can be mixed and matched effectively, though using classes and structs is undefined behaviour.
    immutable mixAndMatch = parameters!(6, false, true, 'c', "string", -1L, 5UL);
    static assert (mixAndMatch == `false, true, 'c', "string", -1L, 5LU`);
}


/// Generates a property to access a component and optionally, any aliases to the given property.
/// Params:
///     Type            = The type of the member being accessed by the property.
///     MemberAccessor  = How the member should be accessed by the property.
///     PropertyName    = The desired symbol name of the property to be generated.
///     Aliases         = Any additional aliases that will redirect to PropertyName.
template GenerateMemberProperty (Type, string MemberAccessor, string PropertyName, Aliases...)
{
    import std.array    : replace;
    import std.traits   : fullyQualifiedName;

    enum GenerateMemberProperty = 
        (getter ~ setter ~ aliases)
        .replace ("$Type", fullyQualifiedName!Type)
        .replace ("$PropertyName", PropertyName)
        .replace ("$MemberAccessor", MemberAccessor);
    
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

    enum aliases = Aliases.length == 0 ? "" : GenerateAliases!(PropertyName, Aliases);
}


/// Generates a series of aliases to the desired symbol.
/// Params:
///     ReferTo = The type/function/variable that the generated aliases will refer to.
///     Aliases = A collection of string aliases that will be generated to refer to ReferTo.
template GenerateAliases (string ReferTo, Aliases...)
    if (ReferTo.length > 0 && Aliases.length > 0)
{
    import std.array : join, replace;

    static if (Aliases.length > 1)
    {
        enum GenerateAliases = join ([GenerateAliases!(ReferTo, Aliases[1 .. $]), newAlias]);
    }
    
    else
    {
        enum GenerateAliases = newAlias;
    }

    private enum newAlias = 
        "alias $Alias = $ReferTo;"
        .replace ("$Alias", Aliases[0])
        .replace ("$ReferTo", ReferTo);
}