/**
    Common representations of different asset types such as a model mesh and surface material.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: Copyright © 2017, Simon Peter Campbell
    License: MIT
*/
module denjin.assets.types;

// Phobos.
import std.algorithm    : clamp;
import std.traits       : isArray, isDynamicArray, isStaticArray;

// Engine.
import denjin.misc.ids : MaterialID, MeshID;

/**
    Provides a description of the material properties of a rendered object. 

    Properties are physically-based with the ability to specify uniform surface-wide values or specify texture maps to
    use instead.
*/
struct RenderMaterial
{
    private
    {
        MaterialID  m_id;                               /// An ID uniquely identifying this instance of a RenderMaterial.
        float       m_smoothness    = 0f;               /// A smoothness factor.
        float       m_reflectance   = 0f;               /// A reflectance factor.
        float       m_conductivity  = 0f;               /// A conductivity factor.
        float[4]    m_albedo        = [0f, 0f, 0f, 1f]; /// The base colour and opacity of the material.

        string      m_physicsMap;   /// The file location to a texture map to use for physics properties.
        string      m_albedoMap;    /// The file location to a texture map to use for the albedo.
        string      m_normalMap;    /// The file location to a texture map to use for bump-mapping normals.
    }

    /// Construct the material with a unique ID but leave other parameters as default values.
    this (in MaterialID id) pure nothrow @safe @nogc
    {
        m_id = id;
    }

    /**
        The identifier allows systems to optimise for unique material types, for example a renderer may load the data
        at load-time to perform faster.

        Returns:
            The identifier for the material.
    */
    MaterialID id() const pure nothrow @safe @nogc @property { return m_id; }

    /// Smoothness controls the self-shadowing behaviour of a surface. The smoother the less self-shadowing will occur.
    /// Returns: A zero to one smoothness factor.
    float smoothness() const pure nothrow @safe @nogc @property { return m_smoothness; }

    /// Reflectance controls the fresnel effect on a surface.
    /// Returns: A zero to one smoothness factor.
    float reflectance() const pure nothrow @safe @nogc @property { return m_reflectance; }

    /**
        Conductivity effects how much light energy is absorbed, dielectrics should be zero and metals should be one.
        Blending will occur between these values.

        Returns: A zero to one conductivity factor.
    */
    float conductivity() const pure nothrow @safe @nogc @property { return m_conductivity; }

    /// The first three values represent the base colour of the material, the fourth is an opacity factor.
    /// Returns: An array of four floats ranging from zero to one.
    ref const(float[4]) albedo() const pure nothrow @safe @nogc @property { return m_albedo; }

    /// The file location of a texture map to be used for smoothness, reflectance and conductivity values.
    /// Returns: A file location as a string, An empty string indicates no texture map should be used.
    string physicsMap() const pure nothrow @safe @nogc @property { return m_physicsMap; }

    /// The file location of a texture map to be used for base colour and opacity.
    /// Returns: A file location as a string, An empty string indicates no texture map should be used.
    string albedoMap() const pure nothrow @safe @nogc @property { return m_albedoMap; }

    /// The file location of a texture map to be used for bump mapping normals.
    /// Returns: A file location as a string, An empty string indicates no texture map should be used.
    string normalMap() const pure nothrow @safe @nogc @property { return m_normalMap; }

    /// Sets the smoothness factor of the material. This will be clamped in the range zero to one.
    void smoothness (in float value) pure nothrow @safe @nogc @property
    {
        m_smoothness = value.clamp (0f, 1f);
    }
    
    /// Sets the reflectance factor of the material. This will be clamped in the range zero to one.
    void reflectance (in float value) pure nothrow @safe @nogc @property 
    {
        m_reflectance = value.clamp (0f, 1f);
    }

    /// Sets the conductivity factor of the material. This will be clamped in the range zero to one.
    void conductivity (in float value) pure nothrow @safe @nogc @property
    {
        m_conductivity = value.clamp (0f, 1f);
    }

    /**
        Sets the base colour and opacity of the material. Static arrays with a length less than 4 will not compile. 
        Dynamic arrays with a length less than 4 will be ignored.
    */
    void albedo(T)(auto ref T array) @property
        if (isArray!T && ((isStaticArray!T && T.length >= 4) || isDynamicArray!T))
    {
        static if (isDynamicArray!T)
        {
            assert (array.length >= 4);
            if (array.length < 4) return;
        }
        m_albedo = array[0..4];

        // Perhaps a compiler bug is preventing std.algorithm : each from mutating the array in-place?
        foreach (ref f; m_albedo)
        {
            f = f.clamp (0f, 1f);
        }
    }

    /// Sets the base colour and opacity of the material, each value will be clamped in the range zero to one.
    void setAlbedo (in float red, in float green, in float blue, in float alpha) pure nothrow @safe @nogc
    {
        m_albedo =
        [
            red.clamp (0f, 1f),
            green.clamp (0f, 1f),
            blue.clamp (0f, 1f),
            alpha.clamp (0f, 1f)
        ];
    }

    /// Sets the texture map to use for smoothness, reflectance and conductivity. An empty string will disable the map.
    void physicsMap (string textureMap) pure nothrow @safe @nogc @property { m_physicsMap = textureMap; }

    /// Sets the texture map to use for base colour and opacity. An empty string will disable the map.
    void albedoMap (string textureMap) pure nothrow @safe @nogc @property { m_albedoMap = textureMap; }

    /// Sets the texture map to use for bump mapping. An empty string will disable the map.
    void normalMap (string textureMap) pure nothrow @safe @nogc @property { m_normalMap = textureMap; }
}
///
pure nothrow @safe unittest
{
    import std.math                 : approxEqual;
    import denjin.rendering.traits  : isMaterial;

    // The material must meet the requirements of materials used by the renderer.
    static assert (isMaterial!RenderMaterial);
    
    // We can default construct a material.
    auto matA = RenderMaterial();

    // We can give a material a MaterialID at construction.
    auto matB = RenderMaterial(1);
    assert (matB.id == 1);

    // Physics parameters are set as follows.
    matB.smoothness = 0.5f;
    assert (matB.smoothness.approxEqual (0.5f));

    matB.reflectance = 0.1f;
    assert (matB.reflectance.approxEqual (0.1f));

    matB.conductivity = 1f;
    assert (matB.conductivity.approxEqual (1f));

    // Base colour is set as follows. Also every float value is clamped between 0f and 1f.
    matB.albedo = [2f, -1f, 0.5f, 0.25f];
    assert (matB.albedo[0].approxEqual (1f));
    assert (matB.albedo[1].approxEqual (0f));
    assert (matB.albedo[2].approxEqual (0.5f));
    assert (matB.albedo[3].approxEqual (0.25f));

    /// Component-wise setting is available a follows.
    matB.setAlbedo (0f, 1.1f, -100f, 5f);
    assert (matB.albedo[0].approxEqual (0f));
    assert (matB.albedo[1].approxEqual (1f));
    assert (matB.albedo[2].approxEqual (0f));
    assert (matB.albedo[3].approxEqual (1f));
 
    // Materials should default to not using texture maps.
    assert (matB.physicsMap.length == 0);
    assert (matB.albedoMap.length == 0);
    assert (matB.normalMap.length == 0);

    // Materials can also be told to use texture maps.
    matB.physicsMap = "physics.png";
    assert (matB.physicsMap == "physics.png");

    matB.albedoMap = "albedo.png";
    assert (matB.albedoMap == "albedo.png");
    
    matB.normalMap = "normal.png";
    assert (matB.normalMap == "normal.png");
}

// Clamping tests.
pure nothrow @safe unittest
{
    import std.math : approxEqual;

    // Use a default material.
    auto mat = RenderMaterial();

    void clampTest(string member)(ref RenderMaterial mat)
    {
        __traits (getMember, mat, member) = .5f;
        assert (__traits (getMember, mat, member).approxEqual (.5f));
        
        __traits (getMember, mat, member) = 1.1f;
        assert (__traits (getMember, mat, member).approxEqual (1f));

        __traits (getMember, mat, member) = -0.1f;
        assert (__traits (getMember, mat, member).approxEqual (0f));
    }

    void clampAlbedoTest(ref RenderMaterial mat, float value, bool componentWise)
    {
        if (componentWise)  mat.setAlbedo (value, value, value, value);
        else                mat.albedo = [value, value, value, value];
        
        immutable valueTest = value < 0f ? 0f : value > 1f ? 1f : value;
        assert (mat.albedo[0].approxEqual (valueTest));
        assert (mat.albedo[1].approxEqual (valueTest));
        assert (mat.albedo[2].approxEqual (valueTest));
        assert (mat.albedo[3].approxEqual (valueTest));
    }

    clampTest!("smoothness")(mat);
    clampTest!("reflectance")(mat);
    clampTest!("conductivity")(mat);

    clampAlbedoTest (mat, .5f, true);
    clampAlbedoTest (mat, .5f, false);
    clampAlbedoTest (mat, -0.1f, true);
    clampAlbedoTest (mat, -0.1f, false);
    clampAlbedoTest (mat, 1.1f, true);
    clampAlbedoTest (mat, 1.1f, false);
}

/**
    Provides the data necessary to construct a renderable mesh.

    These meshes can be used to create instances from, allowing multiple objects in a scene to be represented by the
    same mesh data containing in this structure.
*/
struct RenderMesh
{
    private
    {
        MeshID m_id; /// An ID which should represent a unique mesh. This should be referenced by instances.
    }

    alias Vec3 = float[3];      /// 3D vectors are represented by an array of 3 floats.
    alias Vec2 = float[2];      /// 2D vectors are represented by an array of 2 floats.
    Vec3[] positions;           /// Contains the position of every vertex of the mesh.
    Vec3[] normals;             /// Contains the surface normal of every vertex of the mesh.
    Vec3[] tangents;            /// Contains the surface tangents of every vertex of the mesh.
    Vec2[] textureCoordinates;  /// Contains the UV co-ordinates of every vertex of the mesh.
    uint[] elements;            /// Contains the elements necessary to construct triangles from vertex positions.

    /**
        Construct a mesh with the given ID. 
    
        The ID should uniquely identify the mesh, it should not be shared by other meshes.
    */
    this (in MeshID id) pure nothrow @safe @nogc
    {
        m_id = id;
    }

    /// Gets the unique identifier of the mesh.
    MeshID id() const pure nothrow @safe @nogc @property { return m_id; }
}
///
pure nothrow @safe unittest
{
    import denjin.rendering.traits : isMesh;

    // The mesh must meet the requirements of the renderer.
    static assert (isMesh!RenderMesh);

    // We can default construct meshes but the ID may not be unique.
    enum meshA = RenderMesh();
    static assert (meshA.id == 0);

    auto meshB = RenderMesh(1);
    assert (meshB.id == 1);

    // Vertex attributes can be added like so.
    meshB.positions ~= [1f, 1f, 1f];
    assert (meshB.positions[$-1] == [1f, 1f, 1f]);

    meshB.normals ~= [2f, 2f, 2f];
    assert (meshB.normals[$-1] == [2f, 2f, 2f]);
    
    meshB.tangents ~= [3f, 3f, 3f];
    assert (meshB.tangents[$-1] == [3f, 3f, 3f]);

    meshB.elements ~= [0u, 0u, 0u];
    assert (meshB.elements == [0u, 0u, 0u]);

    // Convenience functions exist to do this as well.
    meshB.addVertex ([2f, 2f, 2f]);
    assert (meshB.positions[$-1] == [2f, 2f, 2f]);
}

/// An entire vertex is added to the given RenderMesh.
/// Params:
///     mesh    = The mesh to add a vertex to.
///     normal  = The surface normal of the vertex, this is used in lighting calculations.
///     tangent = The tangent of the surface normal, this is used in bump mapping techniques.
///     uv      = The texture-coordinate for the new vertex.
void addVertex (ref RenderMesh mesh, 
                in RenderMesh.Vec3 position, 
                in RenderMesh.Vec3 normal = [0f, 1f, 0f], 
                in RenderMesh.Vec3 tangent = [0f, 0f, 1f], 
                in RenderMesh.Vec2 uv = [0f, 0f]) pure nothrow @safe
{
    mesh.positions          ~= position;
    mesh.normals            ~= normal;
    mesh.tangents           ~= tangent;
    mesh.textureCoordinates ~= uv;
}
///
pure nothrow @safe unittest
{
    auto mesh = RenderMesh();
    mesh.addVertex ([1f, 1f, 1f], [2f, 2f, 2f], [3f, 3f, 3f], [4f, 4f]);

    assert (mesh.positions[0] == [1f, 1f, 1f]);
    assert (mesh.normals[0] == [2f, 2f, 2f]);
    assert (mesh.tangents[0] == [3f, 3f, 3f]);
    assert (mesh.textureCoordinates[0] == [4f, 4f]);
}

/**
    An entire triangle is added to the given RenderMesh.
    
    Params:
        first   = The starting position index of the triangle.
        second  = The position index of the vertex to draw a line from the first position to.
        third   = The position index of the vertex to draw a line from the second position to. A line will then be draw 
                  back to the first position index.
*/
void addTriangle (ref RenderMesh mesh, in uint first, in uint second, in uint third) pure nothrow @safe
{
    // Eagerly increase the element length for efficiency.
    mesh.elements.length += 3;

    // Specify each new element.
    mesh.elements[$-3] = first;
    mesh.elements[$-2] = second;
    mesh.elements[$-1] = third;
}
///
pure nothrow @safe unittest
{
    // Adding a triangle to be rendered is easy!
    auto mesh = RenderMesh();
    
    // First add the necessary positions. Here we're creating a quad.
    mesh.positions.length += 4;
    mesh.positions[$-4] = [0f, 0f, 0f];
    mesh.positions[$-3] = [1f, 0f, 0f];
    mesh.positions[$-2] = [0f, 1f, 0f];
    mesh.positions[$-1] = [1f, 1f, 0f];

    // Now we can construct the two triangles necessary to draw a quad, this will be done counter-clockwise.
    mesh.addTriangle (0, 1, 2);
    mesh.addTriangle (2, 1, 3);

    assert (mesh.elements[0] == 0);
    assert (mesh.elements[1] == 1);
    assert (mesh.elements[2] == 2);
    assert (mesh.elements[3] == 2);
    assert (mesh.elements[4] == 1);
    assert (mesh.elements[5] == 3);
}