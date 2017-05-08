/**
    Checkable type traits which determine whether a type is suitable for representing assets and asset management
    systems. Contained trait requirements must be met to use a Denjin rendering system.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: Copyright © 2017, Simon Peter Campbell
    License: MIT
*/
module denjin.rendering.traits.assets;

/**
    Checks if a given type is suitable for usage as an asset management system.

    Allows for the storage and retrieval of assets used by rendering systems. An assets system should return all 
    materials and meshes when required, but also be able to retrieve singular objects using a unique MaterialID and
    MeshID.

    Members:
    materials: An input range of objects representing unique materials which must be loaded. 
    meshes: An input range of objects representing unique meshes which must be loaded.
    material: A pointer to a representation of a single material which corresponds to a given MaterialID.
    mesh: A pointer to a representation of a single mesh which corresponds to a given MeshID.

    See_Also:
        isMaterial, isMesh
*/
template isAssets (T)
{
    import std.range        : ElementType, isInputRange;
    import std.traits       : hasMember, isArray, PointerTarget;
    import denjin.misc.ids  : MaterialID, MeshID;

    // These members must exist. The following can be variables or functions.
    static assert (hasMember!(T, "materials"));
    static assert (hasMember!(T, "meshes"));
    
    // The following must be functions taking a single mandatory parameter.
    static assert (hasMember!(T, "material"));
    static assert (hasMember!(T, "mesh"));

    // The return types and parameters of members must meet the following requirements.
    void testType (in T assets)
    {
        enum isArrayOrInputRange (U) = isArray!U || isInputRange!U;

        auto materials  = assets.materials;
        alias MatRange  = typeof (materials);
        static assert (isArrayOrInputRange!MatRange);
        static assert (isMaterial!(ElementType!MatRange));

        auto meshes     = assets.meshes;
        alias MeshRange = typeof (meshes);
        static assert (isArrayOrInputRange!MeshRange);
        static assert (isMesh!(ElementType!MeshRange));

        auto material   = assets.material (MaterialID.init);
        alias Material  = typeof (material);
        static assert (isMaterial!(PointerTarget!Material));

        auto mesh       = assets.mesh (MeshID.init);
        alias Mesh      = typeof (mesh);
        static assert (isMesh!(PointerTarget!Mesh));
    }

    enum isAssets = true;
}
///
pure nothrow @safe @nogc unittest
{
    import denjin.misc.ids : MaterialID, MeshID;

    struct Material
    {
        MaterialID id;
        float smoothness;
        float reflectance() const { return 0; }
        float conductivity() const @property { return 0; }
        float[4] albedo() const { return [0,0,0,0]; }
        string physicsMap;
        string albedoMap() const { return ""; }
        enum normalMap = "";
    }
    struct Mesh
    {
        immutable MeshID id = 0;
        float[3][] positions;
        enum float[3][] normals = [[0f,0f,0f]];
        float[3][] tangents() const @property { return [[0f,0f,0f],[0f,0f,0f]]; }
        float[2][2] textureCoordinates;
        short[] elements;
    }
    interface Assets
    {
        inout(Material[]) materials() inout @property;
        inout(Mesh[]) meshes() inout @property;

        inout(Material*) material (in MaterialID id) inout;
        ref inout(Mesh*) mesh (in MeshID id) inout;
    }

    static assert (isAssets!Assets);
}

/**
    This will check if the given type is suitable for representing a surface material.

    Members:
    id: A unique ID which identifies the material, must implicitly convert to a MaterialID.
    smoothness: A float value ranging from 0f to 1f, controls how smooth the surface appears.
    reflectance: A float value ranging from 0f to 1f, controls the fresnel effect on surfaces.
    conductivity: A float value ranging from 0f to 1f, controls how much diffuse reflection occurs.
    albedo: A 4D vector type of floats, these should be RGBA channels ranging from 0f to 1f.
    physicsMap: A string which can be used as a file location to load a 3-channel image containing smoothness, reflectance and conductivity channels.
    albedoMap: A string which can be used as a file location to load a 4-channel image containing RGB albedo with an alpha transparency value.
    normalMap: A string which can be used as a file location to load a 3-channel image acting as a normal map for models.

    See_Also:
        isVector
*/
template isMaterial (T)
{
    import std.traits               : hasMember, isConvertibleToString, isImplicitlyConvertible, isSomeString;
    import denjin.misc.ids          : MaterialID;
    import denjin.rendering.traits  : isVector;

    // These members must exist, all of which can be variables or functions.
    static assert (hasMember!(T, "id"));
    static assert (hasMember!(T, "smoothness"));
    static assert (hasMember!(T, "reflectance"));
    static assert (hasMember!(T, "conductivity"));
    static assert (hasMember!(T, "albedo"));
    static assert (hasMember!(T, "physicsMap"));
    static assert (hasMember!(T, "albedoMap"));
    static assert (hasMember!(T, "normalMap"));

    // The return types of each member must meet the requirements specified below.
    void testType (in T material)
    {
        enum isString (U) = isConvertibleToString!U || isSomeString!U;

        auto id     = material.id;
        alias IDT   = typeof (id);
        static assert (isImplicitlyConvertible!(IDT, MaterialID));

        auto smoothness = material.smoothness;
        alias SmoothT   = typeof (smoothness);
        static assert (isImplicitlyConvertible!(SmoothT, float));

        auto reflectance    = material.reflectance;
        alias ReflectT      = typeof (reflectance);
        static assert (isImplicitlyConvertible!(ReflectT, float));

        auto conductivity   = material.conductivity;
        alias ConductT      = typeof (conductivity);
        static assert (isImplicitlyConvertible!(ConductT, float));

        auto albedo     = material.albedo;
        alias AlbedoT   = typeof (albedo);
        static assert (isVector!(AlbedoT, float, 4));

        auto physicsMap = material.physicsMap;
        alias PhysMapT  = typeof (physicsMap);
        static assert (isString!PhysMapT);

        auto albedoMap  = material.albedoMap;
        alias AlbMapT   = typeof (albedoMap);
        static assert (isString!AlbMapT);

        auto normalMap  = material.normalMap;
        alias NormMapT  = typeof (normalMap);
        static assert (isString!NormMapT);
    }

    enum isMaterial = true;
}
///
pure nothrow @safe @nogc unittest
{
    import denjin.misc.ids : MaterialID;

    struct Material
    {
        MaterialID id;
        float smoothness;
        float reflectance() const { return 0; }
        float conductivity() const @property { return 0; }
        float[4] albedo() const { return [0,0,0,0]; }
        string physicsMap;
        string albedoMap() const { return ""; }
        enum normalMap = "";
    }

    static assert (isMaterial!Material);
}

/**
    Checks if the given type is suitable for representing a Mesh object which can be drawn by a renderer.

    Members:
    id: A value which is implicitly convertible to a MeshID and should uniquely identify the mesh.
    positions: An array or random access range containing 3D vectors of floats denoting the vertex positions that make up the mesh.
    normals: An array or random access range containing 3D vectors of floats denoting the normal of each vertex.
    tangents: An array or random access range containing 3D vectors of floats denoting the tangent of each vertex normal.
    textureCoordinates: An array or random access range containing 2D vectors of floats denoting the UV coordinate of each vertex.
    elements: An array or random access range containing uints, this is used to build triangles from the given positions.

    See_Also:
        isVector
*/
template isMesh (T)
{
    import std.range                : ElementType, isRandomAccessRange;
    import std.traits               : hasMember, isArray, isImplicitlyConvertible;
    import denjin.misc.ids          : MeshID;
    import denjin.rendering.traits  : isVector;

    // These members must exist, all of which can be variables or functions.
    static assert (hasMember!(T, "id"));
    static assert (hasMember!(T, "positions"));
    static assert (hasMember!(T, "normals"));
    static assert (hasMember!(T, "tangents"));
    static assert (hasMember!(T, "textureCoordinates"));
    static assert (hasMember!(T, "elements"));

    // The return types of each member must meet these requirements.
    void testType (in T mesh)
    {
        enum isArrayOrRandomAccessRange (U) = isArray!U || isRandomAccessRange!U;
        
        auto id     = mesh.id;
        alias IDT   = typeof (id);
        static assert (isImplicitlyConvertible!(IDT, MeshID));

        auto positions  = mesh.positions;
        alias PosRange  = typeof (positions);   
        static assert (isArrayOrRandomAccessRange!PosRange);
        static assert (isVector!(ElementType!PosRange, float, 3));

        auto normals    = mesh.normals;
        alias NormRange = typeof (normals);
        static assert (isArrayOrRandomAccessRange!NormRange);
        static assert (isVector!(ElementType!NormRange, float, 3));

        auto tangents   = mesh.tangents;
        alias TanRange  = typeof (tangents);
        static assert (isArrayOrRandomAccessRange!TanRange);
        static assert (isVector!(ElementType!TanRange, float, 3));

        auto uvs        = mesh.textureCoordinates;
        alias UVRange   = typeof (uvs);
        static assert (isArrayOrRandomAccessRange!UVRange);
        static assert (isVector!(ElementType!UVRange, float, 2));

        auto elements   = mesh.elements;
        alias ElemType  = typeof (elements);
        static assert (isArrayOrRandomAccessRange!ElemType);
        static assert (isImplicitlyConvertible!(ElementType!ElemType, uint));
    }

    enum isMesh = true;
}
///
pure nothrow @safe @nogc unittest
{
    import denjin.misc.ids : MeshID;
    
    struct Mesh
    {
        immutable MeshID id = 0;
        float[3][] positions;
        enum float[3][] normals = [[0f,0f,0f]];
        float[3][] tangents() const @property { return [[0f,0f,0f],[0f,0f,0f]]; }
        float[2][2] textureCoordinates;
        short[] elements;
    }

    static assert (isMesh!Mesh);
}