/**
    Functionality extending mathematical types.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: Copyright © 2017, Simon Peter Campbell
    License: MIT
*/
module denjin.maths.functions;

// Phobos.
import std.range    : ElementType;
import std.traits   : isFloatingPoint, isNumeric;
import std.typecons : Flag, No, Yes;

// Engine.
import denjin.maths.traits  : isDynamicVector, isStaticVector, isVector;
import denjin.maths.types   : Matrix4;

/**
    Constructs a projection matrix with a perspective view using the given parameters. This is modelled very similarly
    after the glm::perspective function.

    Params:
        depthZeroToOne  = Determines whether the depth should be clamped from zero to one (Vulkan requires this).
        rightHanded     = Whether the matrix should use the right-handed or left-handed formula.
        T               = The numerical type of the matrix.
        fieldOfView     = The vertical field of view in radians.
        aspectRatio     = The aspect ratio of the viewport.
        nearClip        = How close objects can be before being clipped.
        farClip         = How far away objects can be before being clipped.

    Returns:
        A 4x4 matrix containing a perspective projection matrix.
*/
Matrix4!T perspective (Flag!"depthZeroToOne" depthZeroToOne  = Yes.depthZeroToOne,
                       Flag!"rightHanded"    rightHanded     = Yes.rightHanded,
                       T = float)
                       (in T fieldOfView, in T aspectRatio, in T nearClip, in T farClip)
    if (isNumeric!T)
{
    import std.math             : approxEqual, tan;
    import denjin.maths.types   : Matrix4;

    /// Some constants we'll need.
    enum zero   = T(0);
    enum one    = T(1);
    enum two    = T(2);
    enum val23  = rightHanded ? -one : one;

    immutable tanHalfFOV    = tan (fieldOfView / two);
    immutable aspectHalfTan = aspectRatio * tanHalfFOV;
    immutable nearToFar     = farClip - nearClip;

    // Create a blank matrix.
    Matrix4!T matrix    = zero;
    matrix[0][0]        = !aspectHalfTan.approxEqual (zero) ? one / aspectHalfTan : zero;
    matrix[1][1]        = !tanHalfFOV.approxEqual (zero) ? one / tanHalfFOV : zero;
    matrix[2][3]        = val23;
    
    static if (depthZeroToOne && rightHanded)
    {
        immutable farToNear = nearClip - farClip;
        matrix[2][2]        = !farToNear.approxEqual (zero) ? farClip / farToNear : zero;
        matrix[3][2]        = !nearToFar.approxEqual (zero) ? -(farClip * nearClip) / nearToFar : zero;
    }
    else
    {
        // Other cases can avoid multiple if statements by grouping them together.
        if (!nearToFar.approxEqual (zero))
        {
            static if (depthZeroToOne && !rightHanded)
            {
                matrix[2][2] = farClip / nearToFar;
                matrix[3][2] = -(farClip * nearClip) / nearToFar;
            }
            else static if (!depthZeroToOne)
            {
                static if (rightHanded) matrix[2][2] = -(farClip + nearClip) / nearToFar;
                else                    matrix[2][2] = (farClip + nearClip) / nearToFar;
                matrix[3][2] = -(two * farClip * nearClip) / nearToFar;
            }
        }
    }
    return matrix;
}
///
pure nothrow @safe @nogc unittest
{
    // Test that it compiles.
    enum projection = perspective (60f, 1.77f, 0.01f, 1000f);
    enum allZero    = perspective (0f, 0f, 0f, 0f);
    enum fovZero    = perspective (0f, 1.77f, 0.01f, 1000f);
    enum aspectZero = perspective (60f, 0f, 0.01f, 1000f);
    enum nearZero   = perspective (60f, 1.77f, 0f, 1000f);
    enum farZero    = perspective (60f, 1.77f, 0.01f, 0f);
}

/**
    Constructs a view matrix with the given parameters. This is modelled very similarly after the glm::lookAt function.

    Params:
        depthZeroToOne  = Determines whether the depth should be clamped from zero to one (Vulkan requires this).
        rightHanded     = Whether the matrix should use the right-handed or left-handed formula.
        T               = The numerical type of the matrix and input vectors.
        eye             = The position of the eye in world-space.
        centre          = The central point where the eye is looking in world-space.
        up              = The world-space direction pointing upwards.

    Returns:
        A 4x4 matrix containing a view matrix.
*/
auto lookAt (Flag!"rightHanded" rightHanded = Yes.rightHanded, T = float, U = float, V = float)
                 (auto ref T[3] eye, auto ref U[3] centre, auto ref V[3] up)
    if (isFloatingPoint!T)
{
    import std.traits : Select;

    // We need to determine what type to return.
    alias Num  = typeof (eye[0] * centre[0] * up[0]);

    // We need to know how far the centre is from the eye.
    immutable Num[3] eyeToCentre = [centre[0] - eye[0], centre[1] - eye[1], centre[2] - eye[2]];

    // We must create a new XYZ co-ordinate system.
    immutable x = eyeToCentre.normalised;
    immutable y = mixin (Select!(rightHanded, cross (x, up).normalised.stringof, 
                                              cross (up, x).normalised.stringof));
    immutable z = mixin (Select!(rightHanded, cross (y, x).stringof,
                                              cross (x, y).stringof));
    Matrix4!Num result = void;
    result[0][0] = y[0];
    result[0][1] = z[0];
    result[0][2] = mixin (Select!(rightHanded, (-x[0]).stringof, (x[0]).stringof));
    result[0][3] = Num (0);
    result[1][0] = y[1];
    result[1][1] = z[1];
    result[1][2] = mixin (Select!(rightHanded, (-x[1]).stringof, (x[1]).stringof));
    result[1][3] = Num (0);
    result[2][0] = y[2];
    result[2][1] = z[2];
    result[2][2] = mixin (Select!(rightHanded, (-x[2]).stringof, (-[2]).stringof));
    result[2][3] = Num (0);
    result[3][0] = -dot (y, eye);
    result[3][1] = -dot (z, eye);
    result[3][2] = mixin (Select!(rightHanded, (dot (x, eye)).stringof, (-dot (x, eye)).stringof));
    result[3][3] = Num (1);
    return result;
}
///
pure nothrow @safe @nogc unittest
{
    enum view = lookAt ([0f, 0f, 0f], [0f, 0f, 1f], [0f, 1f, 0f]);
}

/// Normalises the given vector. A divide by zero can occur and but is avoided if safety is specified.
void normalise (Flag!"safe" safe = Yes.safe, T = float[3]) (ref T vector)
    if (isVector!T && isFloatingPoint!(ElementType!T))
{
    void normaliseVector (Num)(ref T vector, auto ref Num magnitude)
    {
        for (size_t i = 0; i < vector.length; ++i)
        {
            vector[i] /= magnitude;
        }
    }

    static if (safe)
    {
        import std.math : approxEqual, sqrt;

        // Ensure we don't cause a divide by zero error.
        immutable magSqr    = vector.magnitudeSqr;
        enum zero           = ElementType!T(0);

        if (!magSqr.approxEqual (zero)) normaliseVector (vector, magSqr.sqrt);
    }
    else normaliseVector (vector, vector.magnitude);
}
///
unittest
{
    import std.math             : approxEqual;
    import denjin.maths.types   : Vector3f;

    /// Create a scaled vector then normalise it so that it becomes a direction.
    auto vec3f = Vector3f (100f, 50f, 25f);
    vec3f.normalise!(No.safe);
    assert (vec3f.x.approxEqual (0.87287f, 0.00001f));
    assert (vec3f.y.approxEqual (0.43643f, 0.00001f));
    assert (vec3f.z.approxEqual (0.21821f, 0.00001f));
    assert (vec3f.magnitude.approxEqual (1f));

    // Normalising again shouldn't change the data.
    vec3f.normalise!(Yes.safe);
    assert (vec3f.x.approxEqual (0.87287f, 0.00001f));
    assert (vec3f.y.approxEqual (0.43643f, 0.00001f));
    assert (vec3f.z.approxEqual (0.21821f, 0.00001f));
    assert (vec3f.magnitude.approxEqual (1f));
}

/// Returns the normalised unit vector of the given vector.
auto normalised (Flag!"safe" safe = Yes.safe, T = float[3]) (auto ref T vector)
    if (isVector!T && isFloatingPoint!(ElementType!T))
{
    import std.traits : Unqual;

    void setNormalised (U, Num)(ref U output, auto ref T vector, auto ref Num magnitude)
    {
        for (size_t i = 0; i < vector.length; ++i)
        {
            output[i] = vector[i] / magnitude;
        }
    }

    Unqual!T result = void;
    static if (safe)
    {
        import std.math : approxEqual, sqrt;

        // Ensure we don't cause a divide by zero error.
        immutable magSqr    = vector.magnitudeSqr;
        enum zero           = ElementType!T(0);

        if (!magSqr.approxEqual(zero))  setNormalised (result, vector, magSqr.sqrt);
        else                            result = vector;
    }
    else setNormalised (result, vector, vector.magnitude);
    return result;
}
///
pure nothrow @safe @nogc unittest
{
    import std.math             : approxEqual;
    import denjin.maths.types   : Vector3d, Vector3f;

    enum safeOne    = Vector3f.one.normalised!(Yes.safe);
    enum unsafeOne  = Vector3f.one.normalised!(No.safe);
    static assert (safeOne.x.approxEqual (0.57735f, 0.00001f));
    static assert (safeOne.y.approxEqual (0.57735f, 0.00001f));
    static assert (safeOne.z.approxEqual (0.57735f, 0.00001f));
    static assert (unsafeOne.x.approxEqual (0.57735f, 0.00001f));
    static assert (unsafeOne.y.approxEqual (0.57735f, 0.00001f));
    static assert (unsafeOne.z.approxEqual (0.57735f, 0.00001f));

    enum safeUnit   = Vector3d.forward.normalised!(Yes.safe);
    enum unsafeUnit = Vector3d.forward.normalised!(No.safe);
    static assert (safeUnit.x.approxEqual (0.0));
    static assert (safeUnit.y.approxEqual (0.0));
    static assert (safeUnit.z.approxEqual (1.0));
    static assert (unsafeUnit.x.approxEqual (0.0));
    static assert (unsafeUnit.y.approxEqual (0.0));
    static assert (unsafeUnit.z.approxEqual (1.0));

    enum safeZero = Vector3f.zero.normalised!(Yes.safe);
    static assert (safeZero.x.approxEqual (0f));
    static assert (safeZero.y.approxEqual (0f));
    static assert (safeZero.z.approxEqual (0f));
}

/// Calculates the magnitude of a vector.
auto magnitude (T) (auto ref T vector)
    if (isVector!T)
{
    import std.math : sqrt;
    return sqrt (vector.magnitudeSqr);
}
///
pure nothrow @safe @nogc unittest
{
    import std.math             : approxEqual;
    import denjin.maths.types   : Vector3d, Vector3f;

    enum floatMag = Vector3f.one.magnitude;
    static assert (floatMag.approxEqual (1.73205f, 0.00001f));

    enum doubleMag = Vector3d.one.magnitude;
    static assert (doubleMag.approxEqual (1.73205, 0.00001));

    enum normalMag = Vector3f.up.magnitude;
    static assert (normalMag.approxEqual (1f));

    enum scaledMag = (Vector3f.forward * 10f).magnitude;
    static assert (scaledMag.approxEqual (10f));
}

/// Calculates the squared magnitude of a vector. This is useless for comparing magnitudes as it is efficient.
auto magnitudeSqr (T)(auto ref T vector)
    if (isVector!T)
{
    static if (isStaticVector!T)
    {
        import denjin.misc.mixins : unrollLoop;
        
        // We can unroll the loop for static arrays.
        enum code = unrollLoop!(0, T.length, "vector[$@] * vector[$@] +");
        return mixin (code[0..$-1]);
    }
    else
    {
        alias Number    = typeof (a[0] * b[0]);
        Number result   = Number (0);

        foreach (num; vector)
        {
            result += num * num;
        }
        return result;
    }
}
///
pure nothrow @safe @nogc unittest
{
    import std.math             : approxEqual;
    import denjin.maths.types   : Vector3i, Vector3f;

    enum floatMagSqr = Vector3f.one.magnitudeSqr;
    static assert (floatMagSqr.approxEqual (3f));

    enum intMagSqr = Vector3i.one.magnitudeSqr;
    static assert (intMagSqr.approxEqual (3));

    enum normalMagSqr = Vector3f.up.magnitudeSqr;
    static assert (normalMagSqr.approxEqual (1f));
}

/// Calculates the dot product of two vectors.
auto dot (A, B)(auto ref A a, auto ref B b)
    if (isVector!A && isVector!B)
{
    static if (isStaticVector!A && isStaticVector!B && A.length == B.length)
    {
        import denjin.misc.mixins : unrollLoop;
        
        // We can unroll the loop for static arrays.
        enum code = unrollLoop!(0, A.length, "a[$@] * b[$@]+");
        return mixin (code[0..$-1]);
    }
    else
    {
        // Firstly ensure we can perform the operations.
        assert (a.length == b.length);

        // Find out what type to return.
        alias Number    = typeof (a[0] * b[0]);
        Number result   = Number (0);

        for (size_t i; i < a.length && i < b.length; ++i)
        {
            result += a[i] * b[i];
        }
        return result;
    }
}
///
pure nothrow @safe @nogc unittest
{
    import std.math             : approxEqual;
    import denjin.maths.types   : Vector3f, Vector3i;

    enum rightF = Vector3f.right;
    enum upF    = Vector3f.up;
    static assert (rightF.dot (rightF).approxEqual  (1f));
    static assert (rightF.dot (-rightF).approxEqual (-1f));
    static assert (rightF.dot (upF).approxEqual     (0f));

    enum leftI  = Vector3i.left;
    enum backI  = Vector3i.back;
    static assert (leftI.dot (leftI)    == 1);
    static assert (leftI.dot (-leftI)   == -1);
    static assert (leftI.dot (backI)    == 0);
}

/// Calculates the cross product of two 3D vectors. 
/// Returns: A 3-length array.
auto cross (T, U)(auto ref T[3] a, auto ref U[3] b)
    if (isNumeric!T && isNumeric!U)
{
    typeof (a[0] * b[0])[3] result =
    [
        a[1] * b[2] - b[1] * a[2],
        a[2] * b[0] - b[2] * a[0],
        a[0] * b[1] - b[0] * a[1]
    ];
    return result;
}
///
pure nothrow @safe @nogc unittest
{
    import denjin.maths.types : Vector3f;

    // We're going to demonstrate the cross product of each positive axis.
    enum float[3] right = [1f, 0f, 0f];
    enum float[3] up    = [0f, 1f, 0f];
    enum forward        = Vector3f.forward;

    // Perform the cross products.
    enum rightUpCross       = cross (right, up);
    enum upForwardCross     = cross (up, forward);
    enum forwardRightCross  = cross (forward, right);

    // Ensure we were given arrays.
    static assert (is (typeof (rightUpCross)        == float[3]));
    static assert (is (typeof (upForwardCross)      == float[3]));
    static assert (is (typeof (forwardRightCross)   == float[3]));

    // Check to see that we got the correct directions.
    static assert (rightUpCross         == [0f, 0f, 1f]);
    static assert (upForwardCross       == [1f, 0f, 0f]);
    static assert (forwardRightCross    == [0f, 1f, 0f]);
}

/// Calculates the cross product of two 3D vectors.
/// Returns: An object of the specified type initialised with 3-length static array.
ReturnType cross (ReturnType, T, U)(auto ref T a, auto ref U b)
{
    import std.functional : forward;
    return ReturnType (cross (forward!a, forward!b));
}
///
pure nothrow @safe @nogc unittest
{
    import denjin.maths.types : Vector3f;

    // The function is designed for custom types.
    enum vecRight   = Vector3f.right;
    enum vecUp      = Vector3f.up;
    enum vecForward = Vector3f.forward;

    // It also works with normal arrays.
    enum float[3] arrRight    = [1f, 0f, 0f];
    enum float[3] arrUp       = [0f, 1f, 0f];
    enum float[3] arrForward  = [0f, 0f, 1f];

    // Perform the cross products.
    enum rightUpCross       = cross!(Vector3f)(vecRight, arrUp);
    enum upForwardCross     = cross!(Vector3f)(vecUp, arrForward);
    enum forwardRightCross  = cross!(Vector3f)(vecForward, arrRight);

    // Ensure we were given arrays.
    static assert (is (typeof (rightUpCross)        == Vector3f));
    static assert (is (typeof (upForwardCross)      == Vector3f));
    static assert (is (typeof (forwardRightCross)   == Vector3f));

    // Check the results.
    static assert (rightUpCross.array       == [0f, 0f, 1f]);
    static assert (upForwardCross.array     == [1f, 0f, 0f]);
    static assert (forwardRightCross.array  == [0f, 1f, 0f]);
}
