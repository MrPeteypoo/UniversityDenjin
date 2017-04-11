/**
    Contains a templatised n-dimensional numeric vector structure.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: MIT
*/
module denjin.maths.vector;

// Phobos.
import std.traits   : isDynamicArray, isNumeric, isSigned, isStaticArray;
import std.typecons : Flag, No, Yes;

// Engine.
import denjin.misc.mixins : generateMemberEnum, generateMemberProperty, unrollLoop;

/**
    A templatised vector which can contain any numerical data type and can be as large as you wish. It features
    extensive use of loop unrolling to allow for compile-time computation using vectors.
    
    Params:
        Number      = A numerical type to use as the underlying data type of the Vector.
        Dimensions  = Specifies the dimensions the Vector represents and therefore how many components are stored.
*/
struct Vector (Number, size_t Dimensions)
    if (isNumeric!Number && Dimensions > 0)
{
    nothrow:
    pure:
    @nogc:
    @safe:

    // Members.
    Number[dimensions] array = void; /// The underlying vector data.

    // Template info.
    enum    dimensions  = Dimensions;                   /// How many components the vector stores.
    alias   Type        = Vector!(Number, dimensions);  /// The complete usable type.
    alias   NumericType = Number;                       /// The underlying type used to store data.

    mixin (generateMemberProperty!(Number, "array[0]", "x", "i", "s", "r", "u"));   /// 1D short-hand.
    mixin (generateMemberEnum!(Type, "zero", dimensions, 0));                       /// Represents (0...).
    mixin (generateMemberEnum!(Type, "one", dimensions, 1));                        /// Represents (1...).
    mixin (generateMemberEnum!(Type, "right", dimensions, 1, 0));                   /// Represents (1, 0...).
    static if (isSigned!Number) enum left = -right;                                 /// Represents (-1, 0...).

    static if (dimensions >= 2)
    {
        mixin (generateMemberProperty!(Number, "array[1]", "y", "j", "t", "g", "v"));   /// 2D short-hand.
        mixin (generateMemberEnum!(Type, "up", dimensions, 0, 1, 0));                   /// Represents (0, 1, 0...).
        static if (isSigned!Number) enum down = -up;                                    /// Represents (0, -1, 0...).
    }

    static if (dimensions >= 3)
    {
        mixin (generateMemberProperty!(Number, "array[2]", "z", "k", "p", "b"));    /// 3D short-hand.
        mixin (generateMemberEnum!(Type, "forward", dimensions, 0, 0, 1, 0));       /// Represents (0, 0, 1, 0...).
        static if (isSigned!Number) enum back = -forward;                           /// Represents (0, 0, -1, 0...).
    }

    static if (dimensions >= 4)
    {
        mixin (generateMemberProperty!(Number, "array[3]", "w", "l", "q", "a"));    /// 4D short-hand.
    }

    /// Sets each component of the vector to the given value.
    this (in Number value)
    {
        mixin (unrollLoop!(0, dimensions, "array[$@] = value;"));
    }

    /// Creates a vector by setting each component to the values in the given vectors. This construction method
    /// supports a mixture of numeric and vector types. The total number of components much match or exceed the
    /// dimensional space of the vector. If the number of components exceeds the dimensional space of the vector then
    /// the excess will be truncated and ignored.
    /// Params:
    ///     values = A list of numeric/vector values to initialise each component of the vector with.
    this (T...)(auto ref T params)
        if (dimensions > 1 && componentCount!T >= dimensions)
    {
        import std.functional : forward;
        modifyComponents!(0, 0, "=")(forward!params);
    }

    // Operators.
    ref Number opIndex (size_t index)
    in
    {
        assert (index < dimensions);
    }
    body
    {
        return array[index];
    }

    Number opIndex (size_t index) const
    in 
    {
        assert (index < dimensions);
    }
    body
    {
        return array[index];
    }

    /// Unary operations on vectors will return a vector with the operator being applied to each component.
    Type opUnary (string op)() const
    {
        Type result;
        mixin (unrollLoop!(0, dimensions, "result[$@] = " ~ op ~ "array[$@];"));
        return result;
    }

    /// Binary operations with numeric values will scale each component by the value. Binary operations on dynamic 
    /// arrays will be performed in a component-wise manner at run-time, component-wise operations will be performed 
    /// for all arrays and vectors with more than one component.
    auto opBinary (string op, T) (auto ref T rhs) const
        if (isDynamicArray!T || (isValueType!T && (componentCount!T == 1 || componentCount!T >= dimensions)))
    {
        import std.functional : forward;
        return binaryOperation!(op, Yes.vecOnLHS)(forward!rhs);
    }

    /// Operations when the vector is on the right hand side are exactly the same as the left hand side.
    auto opBinaryRight (string op, T)(auto ref T lhs)
        if (isDynamicArray!T || (isValueType!T && (componentCount!T == 1 || componentCount!T >= dimensions)))
    {
        import std.functional : forward;
        return binaryOperation!(op, No.vecOnLHS)(forward!lhs);
    }

    void opOpAssign (string op, T)(auto ref T rhs)
        if (isDynamicArray!T || (isValueType!T && (componentCount!T == 1 || componentCount!T == dimensions)))
    {
        // Component-wise operations.
        static if (isDynamicArray!T || componentCount!T >= dimensions)
        {
            import std.functional : forward;
            static if (isDynamicArray!T)
            {
                assert (rhs.length >= dimensions);
            }

            modifyComponents!(0, 0, op)(forward!rhs);
        }

        // Single-value scaling operations.
        else
        {
            enum loop = "array[$@]" ~ op ~ "=" ~ paramAccessor!("rhs", "$@", T) ~ ";";
            mixin (unrollLoop!(0, dimensions, loop));
        }
    }

    auto opCast (T)() const
        if (isVector!T)
    {
        import std.algorithm.comparison : min;

        // Firstly construct the new object.
        auto copy = T();
        enum loop = "
            static if (is (T.NumericType : NumericType))    copy.array[$@] = array[$@];
            else                                            copy.array[$@] = cast(T.NumericType) array[$@];
        ";

        // Now we can assign each member.
        mixin (unrollLoop!(0, min (dimensions, T.dimensions), loop));
        return copy;
    }

    private:

        /// Determines the resulting type of performing an operation on the current vector and the given type.
        template ResultingType (string op, T)
        {
            enum a = Number.init;
            enum b = T.init;

            static if (isNumeric!T) mixin ("alias NewType = typeof (a" ~ op ~ "b);");
            else                    mixin ("alias NewType = typeof (a" ~ op ~ "b[0]);");

            static if (isDynamicArray!T || componentCount!T == 1)
            {
                alias ResultingType = Vector!(NewType, dimensions);
            }
            else
            {
                import std.algorithm.comparison : min;
                alias ResultingType = Vector!(NewType, min (dimensions, componentCount!T));
            }
        }

        /// Counts the number of available numeric components in the given parameter pack.
        /// Params: 
        ///     Type    = A numeric/array/vector type.
        ///     Params  = A parameter pack containing numeric/vector types.
        template componentCount (Type, Params...)
        {
            template count (Type)
            {
                static if (isNumeric!Type)          enum count = 1;
                else static if (isStaticArray!Type) enum count = Type.length;
                else static if (isVector!Type)      enum count = Type.dimensions;
                else
                {
                    static assert (
                        false, "Only numeric, static array and Vector types can be counted."
                    );
                }
            }

            // Using the ternary operator causes compilation errors.
            static if (Params.length == 0)  enum componentCount = count!Type;
            else                            enum componentCount = count!Type + componentCount!Params;
        }

        /// Determines whether the given type meets the requirements of being a vector type.
        /// Params: T = The type to check.
        template isVector (T)
        {
            static if ( __traits (compiles, T.NumericType) &&
                        __traits (compiles, T.dimensions) &&
                        __traits (compiles, Vector!(T.NumericType, T.dimensions)) &&
                        is (T : Vector!(T.NumericType, T.dimensions)))
            {
                enum isVector = true;
            }
            else
            {
                enum isVector = false;
            }
        }

        /// Determines whether the given type is a numeric, array or vector type.
        /// Params: T = The type to check.
        template isValueType (T)
        {
            enum isValueType = isNumeric!T || isStaticArray!T || isDynamicArray!T || isVector!T;
        }

        /// Determines how a parameter should be accessed based on the type.
        /// Params: 
        ///     name    = The identifier of the object.
        ///     symbol  = The symbol representing an array index.
        ///     T       = The type of the object being accessed.
        template paramAccessor (string name, string symbol, T)
        {
            static if (isDynamicArray!T || componentCount!T > 1)    enum paramAccessor = name ~ "[" ~ symbol ~ "]";
            else static if (!isNumeric!T && componentCount!T == 1)  enum paramAccessor = name ~ "[0]";
            else                                                    enum paramAccessor = name;
        }

        /// Modifies each component to the values contained in the given parameter pack using the given operator.
        /// Params:
        ///     vecIndex    = The component index of the vector to set the value for.
        ///     paramIndex  = The current index of the given parameter to retrieve a value with.
        ///     op          = The operator to modify components with, e.g. '=', '+=', '-='.
        ///     param       = The current parameter to retrieve values from.
        ///     params      = The remaining parameters to retrieve values from.
        ///     Param       = The type of the current parameter, this is implicit.
        ///     Params      = The types of the remaining parameters, this is implicit.
        void modifyComponents   (size_t vecIndex, size_t paramIndex, string op, Param, Params...) 
                                (auto ref Param param, auto ref Params params)
        {
            import std.functional : forward;

            // Ensure we don't go out of bounds.
            static assert (vecIndex < dimensions);
            static if (!isDynamicArray!Param)   static assert (paramIndex < componentCount!Param);
            else                                assert (paramIndex < param.length);

            // Set the current components value.
            enum target     = "array[vecIndex]";
            enum operator   = op == "=" ? op : op ~ "=";
            enum value      = paramAccessor!("param", "paramIndex", Param);

            mixin (divideByZeroSafety!(op, value));
            mixin (target ~ operator ~ value ~ ";");

            // Ensure we don't go out of the bounds of the parameter.
            enum nextVecIndex   = vecIndex + 1;
            enum nextParamIndex = paramIndex + 1;
            static if (nextVecIndex < dimensions)
            {
                // Handle dynamic arrays with runtime selection.
                static if (isDynamicArray!Param)
                {
                    if (nextParamIndex < param.length)
                    {
                        modifyComponents!(nextVecIndex, nextParamIndex, op) (forward!param, forward!params);
                    }
                    
                    else static if (params.length > 0)
                    {
                        modifyComponents!(nextVecIndex, nextParamIndex, op) (forward!params);
                    }
                }

                // Handle numeric, vector and static array types.
                else static if (nextParamIndex < componentCount!Param)
                {
                    modifyComponents!(nextVecIndex, nextParamIndex, op) (forward!param, forward!params);
                }

                else static if (params.length > 0)
                {
                    modifyComponents!(nextVecIndex, 0, op) (forward!params);
                }
            }
        }

        /// Performs a binary operation with the vector contents either on the left or right hand side.
        auto binaryOperation (string op, Flag!"vecOnLHS" vecOnLHS, T) (in auto ref T value) const
        {
            // Construct the loop body.
            auto result = ResultingType!(op, T)();
            enum target = "result[i] = ";
            enum self   = "array[i]";
            enum param  = paramAccessor!("value", "i", T);
            enum lhs    = vecOnLHS ? self : param;
            enum rhs    = vecOnLHS ? param : self;
            enum safety = divideByZeroSafety!(op, rhs);
            enum loop   = safety ~ target ~ lhs ~ op ~ rhs ~ ";";

            // Manually loop for dynamic arrays at run-time.
            static if (isDynamicArray!T)
            {
                assert (value.length >= result.dimensions);
                for (size_t i = 0; i < rhs.length && i < result.dimensions; ++i)
                {
                    mixin (loop);
                }
            }

            // Unroll the loop to allow for compile-time computation.
            else
            {
                mixin (unrollLoop!(0, result.dimensions, loop, "i"));
            }

            return result;
        }

        /// A template containing code to assert whether a variable is equal to zero.
        /// Params: 
        ///     operator = The operator being performed.
        ///     variable = The name of the variable to check.
        template divideByZeroSafety (string operator, string variable)
        {
            static if (operator == "/" || operator == "%")
            {
                enum divideByZeroSafety = "assert (" ~ variable ~ " != 0);";
            }

            else
            {
                enum divideByZeroSafety = "{ }";
            }
        }
}
///
@safe @nogc pure nothrow unittest
{
    // Most efficient constructor, data is not set to any value.
    enum vec1f = Vector!(float, 1)();
    static assert (vec1f.array.length == vec1f.dimensions);
    
    // Sets each component to zero.
    enum vec2f = Vector!(float, 2)(0f);
    static assert (vec2f.x == 0f);
    static assert (vec2f.y == 0f);

    // Short-hand exists for common vector values.
    enum vec3f = Vector!(float, 3).up;
    static assert (vec3f.x == 0f);
    static assert (vec3f.y == 1f);
    static assert (vec3f.z == 0f);

    // Can be constructed with static arrays, vectors and numbers.
    import std.math : approxEqual;

    enum byte[1]    arr1b  = [4];
    enum            intVal = 10;
    enum            vec4f  = Vector!(float, 4)(arr1b, vec2f, intVal);
    static assert (approxEqual (vec4f.x, arr1b[0]));
    static assert (vec4f.y == vec2f.x);
    static assert (vec4f.z == vec2f.y);
    static assert (approxEqual (vec4f.w, intVal));
    
    // Component-wise construction is also available. Array accessor notation is supported.
    enum vec5f = Vector!(float, 5)(1f, 2f, 3f, 4f, 5f);
    static assert (vec5f[0] == 1f);
    static assert (vec5f[1] == 2f);
    static assert (vec5f[2] == 3f);
    static assert (vec5f[3] == 4f);
    static assert (vec5f[4] == 5f);

    // Vectors/arrays/parameter lists larger than the desired vector will be truncated.
    enum truncVec5f = Vector!(float, 5)(intVal, arr1b, vec5f);
    static assert (approxEqual (truncVec5f[0], intVal));
    static assert (approxEqual (truncVec5f[1], arr1b[0]));
    static assert (truncVec5f[2] == vec5f[0]);
    static assert (truncVec5f[3] == vec5f[1]);
    static assert (truncVec5f[4] == vec5f[2]);

    // Short-hand component access is available up to 4D vectors.
    static assert (vec2f.x == vec2f.i && vec2f.x == vec2f.s && vec2f.x == vec2f.r && vec2f.x == vec2f.u);
    static assert (vec2f.y == vec2f.j && vec2f.y == vec2f.t && vec2f.y == vec2f.g && vec2f.x == vec2f.v);
    static assert (vec3f.z == vec3f.k && vec3f.z == vec3f.p && vec3f.z == vec3f.b);
    static assert (vec4f.w == vec4f.l && vec4f.w == vec4f.q && vec4f.w == vec4f.a);
}

// Short-hand.
@safe @nogc pure nothrow unittest
{
    import std.math : approxEqual;

    // 1D.
    enum vec1z = Vector!(float, 1).zero;
    enum vec1o = Vector!(float, 1).one;
    enum vec1l = Vector!(float, 1).left;
    enum vec1r = Vector!(float, 1).right;
    static assert (vec1z.x.approxEqual (0f));
    static assert (vec1o.x.approxEqual (1f));
    static assert (vec1r.x.approxEqual (1f));
    static assert (vec1l.x.approxEqual (-1f));

    // 2D.
    enum vec2z = Vector!(float, 2).zero;
    enum vec2o = Vector!(float, 2).one;
    enum vec2r = Vector!(float, 2).right;
    enum vec2l = Vector!(float, 2).left;
    enum vec2u = Vector!(float, 2).up;
    enum vec2d = Vector!(float, 2).down;
    static assert (vec2z.x.approxEqual (0f)  && vec2z.y.approxEqual (0f));
    static assert (vec2o.x.approxEqual (1f)  && vec2o.y.approxEqual (1f));
    static assert (vec2r.x.approxEqual (1f)  && vec2r.y.approxEqual (0f));
    static assert (vec2l.x.approxEqual (-1f) && vec2l.y.approxEqual (0f));
    static assert (vec2u.x.approxEqual (0f)  && vec2u.y.approxEqual (1f));
    static assert (vec2d.x.approxEqual (0f)  && vec2d.y.approxEqual (-1f));

    // 3D.
    enum vec3z = Vector!(float, 3).zero;
    enum vec3o = Vector!(float, 3).one;
    enum vec3r = Vector!(float, 3).right;
    enum vec3l = Vector!(float, 3).left;
    enum vec3u = Vector!(float, 3).up;
    enum vec3d = Vector!(float, 3).down;
    enum vec3f = Vector!(float, 3).forward;
    enum vec3b = Vector!(float, 3).back;
    static assert (vec3z.x.approxEqual (0f)  && vec3z.y.approxEqual (0f)  && vec3z.z.approxEqual (0f));
    static assert (vec3o.x.approxEqual (1f)  && vec3o.y.approxEqual (1f)  && vec3o.z.approxEqual (1f));
    static assert (vec3r.x.approxEqual (1f)  && vec3r.y.approxEqual (0f)  && vec3r.z.approxEqual (0f));
    static assert (vec3l.x.approxEqual (-1f) && vec3l.y.approxEqual (0f)  && vec3l.z.approxEqual (0f));
    static assert (vec3u.x.approxEqual (0f)  && vec3u.y.approxEqual (1f)  && vec3u.z.approxEqual (0f));
    static assert (vec3d.x.approxEqual (0f)  && vec3d.y.approxEqual (-1f) && vec3d.z.approxEqual (0f));
    static assert (vec3f.x.approxEqual (0f)  && vec3f.y.approxEqual (0f)  && vec3f.z.approxEqual (1f));
    static assert (vec3b.x.approxEqual (0f)  && vec3b.y.approxEqual (0f)  && vec3b.z.approxEqual (-1f));

    // 4D.
    enum vec4z = Vector!(float, 4).zero;
    enum vec4o = Vector!(float, 4).one;
    enum vec4r = Vector!(float, 4).right;
    enum vec4l = Vector!(float, 4).left;
    enum vec4u = Vector!(float, 4).up;
    enum vec4d = Vector!(float, 4).down;
    enum vec4f = Vector!(float, 4).forward;
    enum vec4b = Vector!(float, 4).back;
    static assert (vec4z.x.approxEqual (0f)  && vec4z.y.approxEqual (0f)  && vec4z.z.approxEqual (0f)  && vec4z.w.approxEqual (0f));
    static assert (vec4o.x.approxEqual (1f)  && vec4o.y.approxEqual (1f)  && vec4o.z.approxEqual (1f)  && vec4o.w.approxEqual (1f));
    static assert (vec4r.x.approxEqual (1f)  && vec4r.y.approxEqual (0f)  && vec4r.z.approxEqual (0f)  && vec4r.w.approxEqual (0f));
    static assert (vec4l.x.approxEqual (-1f) && vec4l.y.approxEqual (0f)  && vec4l.z.approxEqual (0f)  && vec4l.w.approxEqual (0f));
    static assert (vec4u.x.approxEqual (0f)  && vec4u.y.approxEqual (1f)  && vec4u.z.approxEqual (0f)  && vec4u.w.approxEqual (0f));
    static assert (vec4d.x.approxEqual (0f)  && vec4d.y.approxEqual (-1f) && vec4d.z.approxEqual (0f)  && vec4d.w.approxEqual (0f));
    static assert (vec4f.x.approxEqual (0f)  && vec4f.y.approxEqual (0f)  && vec4f.z.approxEqual (1f)  && vec4f.w.approxEqual (0f));
    static assert (vec4b.x.approxEqual (0f)  && vec4b.y.approxEqual (0f)  && vec4b.z.approxEqual (-1f) && vec4b.w.approxEqual (0f));
}

// Array index operator.
@safe @nogc pure nothrow unittest
{
    auto vec3d  = Vector!(double, 3).one;
    vec3d[1]    = 10.0;
    vec3d.z     = 20.0;
    assert (vec3d.x == 1.0);
    assert (vec3d.y == 10.0);
    assert (vec3d[2] == 20.0);

    immutable kvec = vec3d;
    assert (kvec[0] == 1.0);
    assert (kvec[1] == 10.0);
    assert (kvec[2] == 20.0);
}

// Negation operator.
@safe @nogc pure nothrow unittest
{
    enum vec4i  = Vector!(int, 4) (5, -10, 12_930, 346_542);
    enum neg    = -vec4i;
    static assert (-vec4i.x == neg.x);
    static assert (-vec4i.y == neg.y);
    static assert (-vec4i.z == neg.z);
    static assert (-vec4i.w == neg.w);
}

// Binary operators.
@safe pure nothrow unittest
{
    import std.math : approxEqual;
    enum vec3i = Vector!(int, 3)(100, 10, 1);

    // Single value scaling.
    enum scaled1 = vec3i * 100;
    static assert (is (typeof (scaled1) == typeof (vec3i)));
    static assert (scaled1.x == 10_000);
    static assert (scaled1.y == 1_000);
    static assert (scaled1.z == 100);

    enum scaled2 = vec3i * 100f;
    static assert (is (typeof (scaled2) == Vector!(float, vec3i.dimensions)));
    static assert (scaled2.x.approxEqual (10_000f));
    static assert (scaled2.y.approxEqual (1_000f));
    static assert (scaled2.z.approxEqual (100f));

    // Component-wise scaling.
    enum int[3] arrayi = [0, 90, 99];
    enum vecAddArray = vec3i + arrayi;
    static assert (is (typeof (vecAddArray) == typeof (vec3i)));
    static assert (vecAddArray.x == 100);
    static assert (vecAddArray.y == 100);
    static assert (vecAddArray.z == 100);

    enum vecAddVec = vec3i - vecAddArray;
    static assert (is (typeof (vecAddVec) == typeof (vec3i)));
    static assert (vecAddVec.x == 0);
    static assert (vecAddVec.y == -90);
    static assert (vecAddVec.z == -99);

    // Dynamic array support.
    immutable dynArrayi3 = [6, 7, 8];
    immutable dynSubVec3 = dynArrayi3 - vec3i;
    static assert (is (typeof (dynSubVec3) == immutable (typeof (vec3i))));
    assert (dynSubVec3.x == -94);
    assert (dynSubVec3.y == -3);
    assert (dynSubVec3.z == 7);

    immutable dynArrayi5 = [2, 5, -1, 4, 5];
    immutable vecDivDyn5 = vec3i / dynArrayi5;
    static assert (is (typeof (vecDivDyn5) == immutable (typeof (vec3i))));
    assert (vecDivDyn5.x == 50);
    assert (vecDivDyn5.y == 2);
    assert (vecDivDyn5.z == -1);
}

// Binary Assignment operators.
@safe pure nothrow unittest
{
    auto        vec5ul = Vector!(ulong, 5) (50, 30, 10, 1_000, 4_600);
    ulong[5]    arr5ul = [10, 20, 30, 40, 50];
    ulong[]     dyn5ul = [100, 200, 300, 400, 500];

    // Static and dynamic arrays are supported.
    vec5ul += arr5ul;
    assert (vec5ul[0] == 60);
    assert (vec5ul[1] == 50);
    assert (vec5ul[2] == 40);
    assert (vec5ul[3] == 1_040);
    assert (vec5ul[4] == 4_650);

    vec5ul *= dyn5ul;
    assert (vec5ul[0] == 6_000);
    assert (vec5ul[1] == 10_000);
    assert (vec5ul[2] == 12_000);
    assert (vec5ul[3] == 416_000);
    assert (vec5ul[4] == 2_325_000);

    // Scaling is supported alongside component-wise operations.
    vec5ul -= 1000;
    assert (vec5ul[0] == 5_000);
    assert (vec5ul[1] == 9_000);
    assert (vec5ul[2] == 11_000);
    assert (vec5ul[3] == 415_000);
    assert (vec5ul[4] == 2_324_000);

    vec5ul /= 2;
    assert (vec5ul[0] == 2_500);
    assert (vec5ul[1] == 4_500);
    assert (vec5ul[2] == 5_500);
    assert (vec5ul[3] == 207_500);
    assert (vec5ul[4] == 1_162_000);

    // Other vectors are supported.
    vec5ul /= vec5ul;
    assert (vec5ul[0] == 1);
    assert (vec5ul[1] == 1);
    assert (vec5ul[2] == 1);
    assert (vec5ul[3] == 1);
    assert (vec5ul[4] == 1);
}

// Casting.
@safe @nogc pure nothrow unittest
{
    import std.math : approxEqual;
    enum vec4i = Vector!(int, 4) (-500, 1_000, 100, 3_365_864);

    enum vec3i = cast (Vector!(int, 3)) vec4i;
    static assert (is (typeof (vec3i) == Vector!(int, 3)));
    static assert (vec3i.x == vec4i.x);
    static assert (vec3i.y == vec4i.y);
    static assert (vec3i.z == vec4i.z);

    enum vec3f = cast (Vector!(float, 3)) vec3i;
    static assert (is (typeof (vec3f) == Vector!(float, 3)));
    static assert (vec3f.x.approxEqual (vec4i.x));
    static assert (vec3f.y.approxEqual (vec4i.y));
    static assert (vec3f.z.approxEqual (vec4i.z));
}