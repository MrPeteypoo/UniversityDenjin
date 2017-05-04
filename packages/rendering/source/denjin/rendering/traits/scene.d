/**
    Contains types and trait requirements to allow the usage of a given type as a "scene" which renderers can use to
    render frames from.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: MIT
*/
module denjin.rendering.traits.scene;

/// Renderers require a scene to know what objects must be rendered in a frame. This will be frequently accessed and
/// the cost of having a class interface with countless virtual functions would be very high. To allow the renderer to
/// work at maximum capacity a static interface will be used. Any scene "type" given to the renderer must meet the 
/// requirements set out below.
///
/// In brief, the scene will be used to provide a means of retrieving every object that needs to be rendered, IDs for 
/// the resource each object needs and they should be grouped by mesh. Additionally, the scene will contain information
/// about required lights.
///
/// Members:
/// upDirection = Returns a value which can be used as a 3D vector of floats, a unit vector representing the up direction of the world.
/// ambientLightIntensity = Returns a value which can be used as a 3D vector of floats, contains RGB colour channels ranging from 0f to 1f.
/// camera = Returns an object containing camera data.
/// instances = Returns an input range of objects which contain instance data.
/// instancesByMesh = Given a MeshID, returns an input range which contains instance data for the given MeshID.
/// directionalLights = Returns an input range of objects containing directional light data.
/// pointLights = Returns an input range of objects containing point light data.
/// spotlights = Returns an input range of objects containing spotlight data.
///
/// See_Also:
///     isCamera, std.range.isInputRange, isInstance, isVector3F, MeshID
template isScene (T)
{
    import std.range    : ElementType, isInputRange, ReturnType;
    import std.traits   : hasMember, isImplicitlyConvertible, isArray;
    import denjin.rendering.ids;
    import denjin.rendering.traits : isVector3F;

    // These members must exist, most can be either variables or functions.
    static assert (hasMember!(T, "upDirection"));
    static assert (hasMember!(T, "ambientLightIntensity"));
    static assert (hasMember!(T, "camera"));
    static assert (hasMember!(T, "instances"));
    static assert (hasMember!(T, "instancesByMesh"));
    static assert (hasMember!(T, "directionalLights"));
    static assert (hasMember!(T, "pointLights"));
    static assert (hasMember!(T, "spotlights"));

    // The return types of each member must meet the requirements specified below.
    void testType (in T scene)
    {
        enum isInputRangeOrArray(U) = isInputRange!U || isArray!U;

        auto upDirVector    = scene.upDirection;
        alias UpDirType     = typeof (upDirVector);
        static assert (isVector3F!UpDirType);

        auto ambientLight   = scene.ambientLightIntensity;
        alias AmbLightType  = typeof (ambientLight);
        static assert (isVector3F!AmbLightType);

        auto camera     = scene.camera;
        alias CamType   = typeof (camera);
        static assert (isCamera!CamType);

        auto instances  = scene.instances;
        alias R1Type    = typeof (instances);
        static assert (isInputRangeOrArray!R1Type);
        static assert (isInstance!(ElementType!R1Type));

        auto byMesh     = scene.instancesByMesh (MeshID.init);
        alias R2Type    = typeof (byMesh);        
        static assert (isInputRangeOrArray!R2Type);
        static assert (isInstance!(ElementType!R2Type));

        auto directionalLights  = scene.directionalLights;
        alias R3Type            = typeof (directionalLights);
        static assert (isInputRangeOrArray!R3Type);
        static assert (isDirectionalLight!(ElementType!R3Type));

        auto pointLights    = scene.pointLights;
        alias R4Type        = typeof (pointLights);
        static assert (isInputRangeOrArray!R4Type);
        static assert (isPointLight!(ElementType!R4Type));

        auto spotlights = scene.spotlights;
        alias R5Type    = typeof (spotlights);
        static assert (isInputRangeOrArray!R5Type);
        static assert (isSpotlight!(ElementType!R5Type));
    }

    enum isScene = true;
}
///
pure nothrow @safe @nogc unittest
{
    import denjin.rendering.ids;

    struct Camera
    {
        float[3] position;
        float[3] direction;
        float fieldOfView() const @property { return 75f; }
        float nearPlaneDistance() const @property { return .3f; }
        float farPlaneDistance() const { return 300f; }
    }
    struct Instance
    {
        InstanceID id;
        MeshID meshID() const { return MeshID.init; }
        MaterialID materialID() const @property { return MaterialID.init; }
        bool isStatic;
        float[4][3] transformationMatrix;
    }
    struct DirectionalLight
    {
        LightID id;
        bool isStatic() const { return true; }
        immutable(bool) isShadowCaster() const { return false; }
        float[3] direction;
        immutable float[3] intensity;
    }
    struct PointLight
    {
        enum LightID id = 0;
        bool isStatic;
        bool isShadowCaster;
        float radius;
        float[3] position;
        immutable(float[3]) intensity;
        immutable(float[3]) attenuation() const { return [0,0,0]; }
    }
    struct Spotlight
    {
        DirectionalLight dLight;
        alias dLight this;
        float range;
        float coneAngle;
        float[3] position;
        int[3] attenuation;
    }
    class SceneTest
    {   
        float[3] upDirection;
        float[3] ambientLightIntensity;
        Camera camera() const { return Camera.init; }
        Instance[5] instances;
        const(Instance[]) instancesByMesh(MeshID) const { return instances[]; }
        DirectionalLight[] directionalLights() const @property { return []; }
        PointLight[10] pointLights;
        Spotlight[] spotlights() const { return [Spotlight.init]; }
    }
    static assert (isScene!SceneTest);
}

/// This will check if the given type is suitable for representing a camera for rendering systems.
///
/// Members:
/// position = Returns a value which can be used as a 3D vector of floats acting as XYZ world-space co-ordinates.
/// direction = Returns a value which can be used as a 3D vector of floats and should be a unit vector.
/// fieldOfView = Returns a value which implicitly converts to a float and controls the FOV (degrees) in the viewport of the camera.
/// nearPlaneDistance = Returns a value which implicitly converts to a float and controls how close objects can be before being clipped.
/// farPlaneDistance = Returns a value which implicitly convers to a float and controls how far away objects can be before being clipped.
///
/// See_Also:
///     isVector3F
template isCamera (T)
{
    import std.traits : hasMember, isImplicitlyConvertible;
    import denjin.rendering.traits : isVector3F;

    // The type must contain these members, either as functions or variables.
    static assert (hasMember!(T, "position"));
    static assert (hasMember!(T, "direction"));
    static assert (hasMember!(T, "fieldOfView"));
    static assert (hasMember!(T, "nearPlaneDistance"));
    static assert (hasMember!(T, "farPlaneDistance"));

    // And the return values must meet the following requirements.
    void testType (in T camera)
    {
        auto position = camera.position;
        alias PosType = typeof (position);
        static assert (isVector3F!PosType);

        auto direction  = camera.direction;
        alias DirType   = typeof (direction);
        static assert (isVector3F!DirType);

        auto fieldOfView    = camera.fieldOfView;
        alias FOVType       = typeof (fieldOfView);
        static assert (isImplicitlyConvertible!(FOVType, float));

        auto nearPlane = camera.nearPlaneDistance;
        alias NearType = typeof (nearPlane);
        static assert (isImplicitlyConvertible!(NearType, float));

        auto farPlane = camera.farPlaneDistance;
        alias FarType = typeof (farPlane);
        static assert (isImplicitlyConvertible!(FarType, float));
    }

    enum isCamera = true;
}
///
pure nothrow @safe @nogc unittest
{
    struct Camera
    {
        float[4] position;
        float[3] direction;
        float fieldOfView() const @property { return 75f; }
        float nearPlaneDistance() const @property { return .3f; }
        float farPlaneDistance() const { return 300f; }
    }
    static assert (isCamera!Camera);
}

/// Checks to see if the given type meets the requirements for representing a renderable instance.
///
/// Members:
/// id = Returns a value which implicitly converts to an InstanceID, this uniquely identifies the instance.
/// meshID = Returns a value which implicitly converts to a MeshID, this identifies the mesh which should be rendered.
/// materialID = Returns a value which implicitly converts to a MaterialID, this identifies the material to use when rendering the mesh.
/// isStatic = Returns a value which implicitly converts to a bool, this enables static object optimisation.
/// transformationMatrix = Returns a value which implicitly converts to a 12-item array of floats representing a 4x3 column-major matrix.
/// See_Also:
///     InstanceID, MeshID, MaterialID
template isInstance (T)
{
    import std.traits : hasMember, isImplicitlyConvertible;
    import denjin.rendering.ids;

    // The following members must exist.
    static assert (hasMember!(T, "id"));
    static assert (hasMember!(T, "meshID"));
    static assert (hasMember!(T, "materialID"));
    static assert (hasMember!(T, "isStatic"));
    static assert (hasMember!(T, "transformationMatrix"));

    // The members must meet the following requirements.
    void testType (in T instance)
    {
        auto id         = instance.id;
        alias ID1Type   = typeof (id);
        static assert (isImplicitlyConvertible!(ID1Type, InstanceID));

        auto meshID     = instance.meshID;
        alias ID2Type   = typeof (meshID);
        static assert (isImplicitlyConvertible!(ID2Type, MeshID));

        auto matID      = instance.materialID;
        alias ID3Type   = typeof (matID);
        static assert (isImplicitlyConvertible!(ID3Type, MaterialID));

        auto isStatic   = instance.isStatic;
        alias FlagType  = typeof (isStatic);
        static assert (isImplicitlyConvertible!(FlagType, bool));

        // TODO: Insert Mat4x3 validation.
    }

    enum isInstance = true;
}
///
pure nothrow @safe @nogc unittest
{
    import denjin.rendering.ids;

    struct Instance
    {
        InstanceID id;
        MeshID meshID() const { return MeshID.init; }
        MaterialID materialID() const @property { return MaterialID.init; }
        bool isStatic;
        float[4][3] transformationMatrix;
    }
    static assert (isInstance!Instance);
}

/// Checks if a type meets the requirements of representing a directional light in a scene.
///
/// Members:
/// id = Returns a value which implicitly converts to a LightID.
/// isStatic = Returns a value which implicitly converts to a bool. Enables static object optimisations.
/// isShadowCaster = Returns a value which implicitly converts to a bool. Controls whether the light casts a shadow.
/// direction = Returns a value which can be used as a 3D vector of floats and should be a unit vector.
/// intensity = Returns a value which can be used as a 3D vector of floats with RGB colour channels ranging from 0f to 1f.
///
/// See_Also:
///     isVector3F, LightID
template isDirectionalLight (T)
{
    import std.traits : hasMember, isImplicitlyConvertible;
    import denjin.rendering.ids;
    import denjin.rendering.traits : isVector3F;

    // The following members must exist.
    static assert (hasMember!(T, "id"));
    static assert (hasMember!(T, "isStatic"));
    static assert (hasMember!(T, "isShadowCaster"));
    static assert (hasMember!(T, "direction"));
    static assert (hasMember!(T, "intensity"));

    // The members must meet the following requirements.
    void testType (in T light)
    {
        auto id         = light.id;
        alias IDType    = typeof (id);
        static assert (isImplicitlyConvertible!(IDType, LightID));

        auto isStatic   = light.isStatic;
        alias FlagType  = typeof (isStatic);
        static assert (isImplicitlyConvertible!(FlagType, bool));

        auto isShadowCaster = light.isShadowCaster;
        alias Flag2Type     = typeof (isShadowCaster);
        static assert (isImplicitlyConvertible!(Flag2Type, bool));

        auto direction  = light.direction;
        alias DirType   = typeof (direction);
        static assert (isVector3F!DirType);

        auto intensity  = light.intensity;
        alias IntType   = typeof (intensity);
        static assert (isVector3F!IntType);
    }

    enum isDirectionalLight = true;
}
///
pure nothrow @safe @nogc unittest
{
    import denjin.rendering.ids;

    struct DirectionalLight
    {
        LightID id;
        bool isStatic() const { return true; }
        immutable(bool) isShadowCaster() const { return false; }
        float[3] direction;
        immutable float[3] intensity;
    }
    static assert (isDirectionalLight!DirectionalLight);
}

/// Checks if a type meets the requirements of representing a point light in a scene.
///
/// Members:
/// id = Returns a value which implicitly converts to a LightID.
/// isStatic = Returns a value which implicitly converts to a bool. Enables static object optimisations.
/// isShadowCaster = Returns a value which implicitly converts to a bool. Controls whether the light casts a shadow.
/// radius = Returns a value which implicitly converts to a float acting as the radius of the light.
/// position = Returns a value which can be used as a 3D vector of floats acting as XYZ world-space co-ordinates.
/// intensity = Returns a value which can be used as a 3D vector of floats with RGB colour channels ranging from 0f to 1f.
/// attenuation = Returns a value which can be used as a 3D vector of floats containing constant, quadratic and linear attenuation factors.
///
/// See_Also:
///     isVector3F, LightID
template isPointLight (T)
{
    import std.traits : hasMember, isImplicitlyConvertible;
    import denjin.rendering.ids;
    import denjin.rendering.traits : isVector3F;

    // The following members must exist.
    static assert (hasMember!(T, "id"));
    static assert (hasMember!(T, "isStatic"));
    static assert (hasMember!(T, "isShadowCaster"));
    static assert (hasMember!(T, "radius"));
    static assert (hasMember!(T, "position"));
    static assert (hasMember!(T, "intensity"));
    static assert (hasMember!(T, "attenuation"));

    // The members must meet the following requirements.
    void testType (in T light)
    {
        auto id         = light.id;
        alias IDType    = typeof (id);
        static assert (isImplicitlyConvertible!(IDType, LightID));

        auto isStatic   = light.isStatic;
        alias FlagType  = typeof (isStatic);
        static assert (isImplicitlyConvertible!(FlagType, bool));

        auto isShadowCaster = light.isShadowCaster;
        alias Flag2Type     = typeof (isShadowCaster);
        static assert (isImplicitlyConvertible!(Flag2Type, bool));

        auto radius     = light.radius;
        alias RadType   = typeof (radius);
        static assert (isImplicitlyConvertible!(RadType, float));

        auto position   = light.position;
        alias PosType   = typeof (position);
        static assert (isVector3F!PosType);

        auto intensity  = light.intensity;
        alias IntType   = typeof (intensity);
        static assert (isVector3F!IntType);

        auto attenuation    = light.attenuation;
        alias AttType       = typeof (attenuation);
        static assert (isVector3F!AttType);
    }

    enum isPointLight = true;
}
///
pure nothrow @safe @nogc unittest
{
    import denjin.rendering.ids;

    struct PointLight
    {
        enum LightID id = 0;
        bool isStatic;
        bool isShadowCaster;
        float radius;
        float[3] position;
        immutable(float[3]) intensity;
        immutable(float[3]) attenuation() const { return [0,0,0]; }
    }
    static assert (isPointLight!PointLight);
}

/// Checks if a type meets the requirements of representing a spotlight in a scene.
///
/// Members:
/// id = Returns a value which implicitly converts to a LightID.
/// isStatic = Returns a value which implicitly converts to a bool. Enables static object optimisations.
/// isShadowCaster = Returns a value which implicitly converts to a bool. Controls whether the light casts a shadow.
/// range = Returns a value which implicitly converts to a float representing the maximum range of the light in the given direction.
/// coneAngle = Returns a value which implicitly converts to a float representing the angle (degrees) of light being cast from the spotlight.
/// position = Returns a value which can be used as a 3D vector of floats acting as XYZ world-space co-ordinates.
/// direction = Returns a value which can be used as a 3D vector of floats and should be a unit vector.
/// intensity = Returns a value which can be used as a 3D vector of floats with RGB colour channels ranging from 0f to 1f.
/// attenuation = Returns a value which can be used as a 3D vector of floats containing constant, quadratic and linear attenuation factors.
///
/// See_Also:
///     isVector3F, LightID
template isSpotlight (T)
{
    import std.traits : hasMember, isImplicitlyConvertible;
    import denjin.rendering.ids;
    import denjin.rendering.traits : isVector3F;

    // The following members must exist.
    static assert (hasMember!(T, "id"));
    static assert (hasMember!(T, "isStatic"));
    static assert (hasMember!(T, "isShadowCaster"));
    static assert (hasMember!(T, "range"));
    static assert (hasMember!(T, "coneAngle"));
    static assert (hasMember!(T, "position"));
    static assert (hasMember!(T, "direction"));
    static assert (hasMember!(T, "intensity"));
    static assert (hasMember!(T, "attenuation"));

    // The members must meet the following requirements.
    void testType (in T light)
    {
        auto id         = light.id;
        alias IDType    = typeof (id);
        static assert (isImplicitlyConvertible!(IDType, LightID));

        auto isStatic   = light.isStatic;
        alias FlagType  = typeof (isStatic);
        static assert (isImplicitlyConvertible!(FlagType, bool));

        auto isShadowCaster = light.isShadowCaster;
        alias Flag2Type     = typeof (isShadowCaster);
        static assert (isImplicitlyConvertible!(Flag2Type, bool));

        auto range      = light.range;
        alias RanType   = typeof (range);
        static assert (isImplicitlyConvertible!(RanType, float));

        auto angle      = light.coneAngle;
        alias AngType   = typeof (angle);
        static assert (isImplicitlyConvertible!(AngType, float));

        auto position   = light.position;
        alias PosType   = typeof (position);
        static assert (isVector3F!PosType);

        auto direction  = light.direction;
        alias DirType   = typeof (direction);
        static assert (isVector3F!DirType);

        auto intensity  = light.intensity;
        alias IntType   = typeof (intensity);
        static assert (isVector3F!IntType);

        auto attenuation    = light.attenuation;
        alias AttType       = typeof (attenuation);
        static assert (isVector3F!AttType);
    }

    enum isSpotlight = true;
}
///
pure nothrow @safe @nogc unittest
{
    import denjin.rendering.ids;

    struct DirectionalLight
    {
        LightID id;
        bool isStatic() const { return true; }
        immutable(bool) isShadowCaster() const { return false; }
        float[3] direction;
        immutable float[3] intensity;
    }
    struct Spotlight
    {
        DirectionalLight dLight;
        alias dLight this;
        float range;
        float coneAngle;
        float[3] position;
        int[3] attenuation;
    }
    static assert (isSpotlight!Spotlight);
}