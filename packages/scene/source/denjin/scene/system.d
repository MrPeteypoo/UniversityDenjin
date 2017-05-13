/**
    Contains the scene management system used by the engine.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: Copyright © 2017, Simon Peter Campbell
    License: MIT
*/
module denjin.scene.system;

// Phobos.
import core.atomic      : atomicOp;
import std.algorithm    : each, move;
import std.conv         : to;
import std.stdio        : writeln;

// Engine.
import denjin.maths.functions   : cross, normalised;
import denjin.maths.types       : Vector3f;
import denjin.misc.ids          : InstanceID, MaterialID, MeshID, materialID, meshID;
import denjin.scene.rendering   : RenderCamera, RenderInstance, RenderDLight, RenderPLight, RenderSLight;

/// Contains a representation of a renderable seen as required by the renderer.
struct Scene
{
    enum Vector3f upDirection           = Vector3f (0f, 1f, 0f);    /// The up direction of the world.
    enum Vector3f ambientLightIntensity = Vector3f (.1f);           /// Ambient light to be applied to every surface.
    
    private
    {
        static shared(InstanceID)   freeID;         /// The current free instance ID.
        RenderCamera                m_camera;       /// Currently only one camera is supported.
        RenderInstance[][MeshID]    m_instances;    /// A collection of instances grouped by mesh ID.
        RenderDLight[]              m_dLights;      /// A collection of directional lights.
        RenderPLight[]              m_pLights;      /// A collection of point lights.
        RenderSLight[]              m_sLights;      /// A collection of spotlights.
        float                       m_seconds = 0f; /// How many seconds the scene has been running.
    }

    /// Load a scene from the given configuration file. Currently this is ignored and a hard-coded scene is loaded.
    this (in string config)
    {
        hardCodedInstances;
        hardCodedLights;
    }

    /// Gets a reference to the stored camera data.
    ref const(RenderCamera) camera() const pure nothrow @safe @nogc @property { return m_camera; };

    /// Gets the collection of directional lights.
    const(RenderDLight[]) directionalLights() const pure nothrow @safe @nogc @property { return m_dLights; }

    /// Gets the collection of point lights.
    const(RenderPLight[]) pointLights() const pure nothrow @safe @nogc @property { return m_pLights; }

    /// Gets the collection of spotlights.
    const(RenderSLight[]) spotlights() const pure nothrow @safe @nogc @property { return m_sLights; }

    /// Gets the collection of instances that correspond to the given MeshID.
    const(RenderInstance[]) instancesByMesh (in MeshID id) const pure nothrow @safe @nogc
    {
        // We must check if the given entry exists.
        const entry = id in m_instances;
        return entry is null ? [] : *entry;
    }

    /// Gets a range giving access to every instance in the scene. This is a particular expensive operation.
    RenderInstance[] instances() const pure nothrow @property
    {
        RenderInstance[] array;
        m_instances.values.each!((ref group)
        {
            array.reserve (group.length);
            array ~= group[0..$];
        });
        return array;
    }

    /// Moves the camera around the scene.
    public void update (float deltaTime)
    {
        import std.math : cos, sin, pow, abs;
        m_seconds += deltaTime;
        immutable t = -0.3f * m_seconds;
        immutable ct = cos(t * 0.3f);
        immutable rx = ct < 0 ? -12.0f : 12f;
        immutable st = sin(t);
        immutable rz = st < 0 ? -3.0f : 1.25f;
        immutable m = 0.1f;
        immutable ry = st < 0 ? -3.0f : 2f;
        immutable look_at = Vector3f (0, 2, st < 0 ? 2 : -10);
        immutable cam_pos = Vector3f(
                        rx * pow(abs(ct), m),
                        5.0f + ry * pow(abs(st), m),
                        1.5f + rz * pow(abs(st), m));
        m_camera.position = cam_pos;
        m_camera.direction = normalised(look_at - cam_pos);

        const cross = m_camera.direction.cross!Vector3f(Vector3f.up);
        //m_sLights[0].position = m_camera.position + cross;
        //m_sLights[0].direction = (look_at - m_sLights[0].position).normalised;

        m_sLights[1].position = Vector3f(-7.5f, 11f, -0.5f + 1.5f * cos(1 + t));
        m_sLights[1].direction = normalised(Vector3f(4f, 0f, -0.5f) - m_sLights[1].position);

        m_sLights[2].position = Vector3f(-7.5f, 11f, -0.5f + 1.5f * cos(t));
        m_sLights[2].direction = normalised(Vector3f(-4f, 0f, -0.5f) - m_sLights[2].position);

        m_sLights[3].position = Vector3f(-9.775f, .834f, 1.525f + .3f * cos(3 + t));
        m_sLights[3].direction = normalised(Vector3f(0.97f, 0.1f, -.6f));
    }

    /// Atomically increments the static freeID and returns an instance ID.
    private static InstanceID newID() nothrow @safe @nogc @property
    {
        return freeID.atomicOp!("+=")(1);
    }

    /// Loads test instances.
    private void hardCodedInstances()
    {
        // We're gonna create one instance per mesh and the unique ID will increment
        foreach (i; 0..383)
        {
            // These don't exist T_T
            if (i == 2 || i == 4) continue;

            // Start by retrieving the information needed for the instance.
            immutable name          = i < 10 ? "sponza_0" ~ i.to!string : "sponza_" ~ i.to!string;
            immutable instanceID    = newID;
            immutable meshID        = name.meshID;
            immutable materialID    = hardCodedMaterial (i);
            immutable isStatic      = true;
            immutable transform     = hardCodedTransforms (i);

            // Now we can create the instance.
            RenderInstance instance = 
            {
                id:                     instanceID,
                meshID:                 meshID,
                materialID:             materialID,
                isStatic:               isStatic,
                transformationMatrix:   transform
            };

            // Add the instance.
            if (auto arrayPointer = meshID in m_instances)
            {
                *arrayPointer ~= move (instance);
            }
            else
            {
                m_instances[meshID] = [move (instance)];
            }
        }
    }

    /// Adds a couple of different lights to the scene.
    private void hardCodedLights()
    {
        auto dLight         = RenderDLight();
        dLight.direction    = Vector3f (11f, -2f, -10f).normalised;
        dLight.intensity    = Vector3f (0.075f);
        m_dLights           ~= dLight;

        auto pLight         = RenderPLight();
        pLight.position     = Vector3f (4f, 3f, 0f);
        pLight.intensity    = Vector3f (1f);
        pLight.radius       = 100f;
        pLight.attenuation  = Vector3f (1f, 4.5f / pLight.radius, 75f / pLight.radius);
        m_pLights           ~= pLight;

        pLight.position     = Vector3f (0f, 5f, -5f);
        pLight.intensity    = Vector3f (1f);
        pLight.radius       = 100f;
        pLight.attenuation  = Vector3f (1f, 4.5f / pLight.radius, 75f / pLight.radius);
        m_pLights           ~= pLight;

        pLight.position     = Vector3f (-13f, 2f, 0f);
        pLight.intensity    = Vector3f (0.5f, 0.15f, 0.15f);
        pLight.radius       = 100f;
        pLight.attenuation  = Vector3f (1f, 4.5f / pLight.radius, 75f / pLight.radius);
        m_pLights           ~= pLight;

        pLight.position     = Vector3f (12f, 2f, 0f);
        pLight.intensity    = Vector3f (0.35f);
        pLight.radius       = 100f;
        pLight.attenuation  = Vector3f (1f, 4.5f / pLight.radius, 75f / pLight.radius);
        m_pLights           ~= pLight;

        pLight.position     = Vector3f (12f, 5f, 0f);
        pLight.intensity    = Vector3f (0.15f, 0.15f, 0.5f);
        pLight.radius       = 100f;
        pLight.attenuation  = Vector3f (1f, 4.5f / pLight.radius, 75f / pLight.radius);
        m_pLights           ~= pLight;

        pLight.position     = Vector3f (-13f, 5f, 0f);
        pLight.intensity    = Vector3f (0.15f, 0.5f, 0.15f);
        pLight.radius       = 100f;
        pLight.attenuation  = Vector3f (1f, 4.5f / pLight.radius, 75f / pLight.radius);
        m_pLights           ~= pLight;

        auto sLight             = RenderSLight();
        sLight.intensity        = Vector3f (0.25f);
        sLight.range            = 150f;
        sLight.coneAngle        = 60f;
        sLight.concentration    = 1f;
        sLight.attenuation      = Vector3f (1f, 4.5f / sLight.range, 75f / sLight.range);
        m_sLights               ~= sLight;
        
        sLight.intensity        = Vector3f (0.75f);
        sLight.range            = 1000f;
        sLight.coneAngle        = 60f;
        sLight.concentration    = 6f;
        sLight.attenuation      = Vector3f (1f, 4.5f / sLight.range, 75f / sLight.range);
        m_sLights               ~= sLight;
        
        sLight.intensity        = Vector3f (0.75f);
        sLight.range            = 1000f;
        sLight.coneAngle        = 60f;
        sLight.concentration    = 2f;
        sLight.attenuation      = Vector3f (1f, 4.5f / sLight.range, 75f / sLight.range);
        m_sLights               ~= sLight;
        
        sLight.intensity        = Vector3f (.75f);
        sLight.range            = 300f;
        sLight.coneAngle        = 90f;
        sLight.concentration    = 9f;
        sLight.attenuation      = Vector3f (1f, 4.5f / sLight.range, 75f / sLight.range);
        m_sLights               ~= sLight;
    }

    /// Given a sponza instance index, this will return a material ID for that object.
    private static MaterialID hardCodedMaterial (size_t sponzaIndex)
    {
        switch (sponzaIndex)
        {
            case 07: case 122: case 123: case 124: case 17: case 20: case 21: case 37: case 39: case 41: case 43: 
            case 45: case 47: case 49: case 51: case 53: case 55: case 56: case 57: case 58: case 59: case 60: case 61: 
            case 62: case 63: case 64: case 65: case 67:
                return materialID ("arch");

            case 05: case 06: case 116: case 258: case 34: case 36: case 379: case 382: case 66: case 68: case 69: 
            case 75:
                return materialID ("bricks");

            case 08: case 19: case 35: case 38: case 40: case 42: case 44: case 46: case 48: case 50: case 52: case 54:
                return materialID ("ceiling");

            case 330: case 331: case 332: case 333: case 339: case 340: case 341: case 342: case 348: case 349: 
            case 350: case 351: case 357: case 358: case 359: case 360:
                return materialID ("chain");

            case 09: case 10: case 11: case 118: case 119: case 12: case 120: case 121: case 13: case 14: case 15: 
            case 16:
                return materialID ("column_a");

            case 125: case 126: case 127: case 128: case 129: case 130: case 131: case 132: case 133: case 134:
            case 135: case 136: case 137: case 138: case 139: case 140: case 141: case 142: case 143: case 144:
            case 145: case 146: case 147: case 148: case 149: case 150: case 151: case 152: case 153: case 154:
            case 155: case 156: case 157: case 158: case 159: case 160: case 161: case 162: case 163: case 164:
            case 165: case 166: case 167: case 168: case 169: case 170: case 171: case 172: case 173: case 174:
            case 175: case 176: case 177: case 178: case 179: case 180: case 181: case 182: case 183: case 184:
            case 185: case 186: case 187: case 188: case 189: case 190: case 191: case 192: case 193: case 194:
            case 195: case 196: case 197: case 198: case 199: case 200: case 201: case 202: case 203: case 204:
            case 205: case 206: case 207: case 208: case 209: case 210: case 211: case 212: case 213: case 214:
            case 215: case 216: case 217: case 218: case 219: case 220: case 221: case 222: case 223: case 224:
            case 225: case 226: case 227: case 228: case 229: case 230: case 231: case 232: case 233: case 234:
            case 235: case 236: case 237: case 238: case 239: case 240: case 241: case 242: case 243: case 244:
            case 245: case 246: case 247: case 248: case 249: case 250: case 251: case 252: case 253: case 254:
            case 255: case 256: 
                return materialID ("column_b");

            case 100: case 101: case 102: case 103: case 104: case 105: case 106: case 107: case 108: case 109:
            case 110: case 111: case 112: case 113: case 114: case 115: case 22: case 23: case 24: case 25: case 26: 
            case 27: case 28: case 29: case 30: case 31: case 32: case 33: case 76: case 77: case 78: case 79: case 80: 
            case 81: case 82: case 83: case 84: case 85: case 86: case 87: case 88: case 89: case 90: case 91: case 92: 
            case 93: case 94: case 95: case 96: case 97: case 98: case 99:
                return materialID ("column_c");

            case 70: case 71: case 72: case 73: case 74:
                return materialID ("details");

            case 284: case 288:
                return materialID ("fabric_a");

            case 321: case 323: case 325: case 328:
                return materialID ("fabric_c");

            case 283: case 286: case 289:
                return materialID ("fabric_d");

            case 282: case 285: case 287:
                return materialID ("fabric_e");

            case 322: case 324: case 327:
                return materialID ("fabric_f");

            case 320: case 326: case 329:
                return materialID ("fabric_g");

            case 259: case 260: case 261: case 262: case 263: case 264: case 265: case 266: case 267: case 268: 
            case 269: case 270: case 271: case 272: case 273: case 274: case 290: case 291: case 292: case 293: 
            case 294: case 295: case 296: case 297: case 298: case 299: case 300: case 301: case 302: case 303: 
            case 304: case 305: case 306: case 307: case 308: case 309: case 310: case 311: case 312: case 313: 
            case 314: case 315: case 316: case 317: case 318: case 319: 
                return materialID ("flagpole");

            case 117: case 18:
                return materialID ("floor");

            case 00: case 275: case 276: case 277: case 278: case 279: case 280: case 281:
                return materialID ("leaf");

            
                //return materialID ("Material__25");

            case 03: case 377: case 378:
                return materialID ("Material__298");

            case 257:
                return materialID ("Material__47");

            case 380: case 381:
                return materialID ("roof");

            case 373: case 374: case 375: case 376:
                return materialID ("vase");

            case 334: case 335: case 336: case 337: case 338: case 343: case 344: case 345: case 346: case 347:
            case 352: case 353: case 354: case 355: case 356: case 361: case 362: case 363: case 364: case 365: 
                return materialID ("vase_hanging");

            case 01: case 366: case 367: case 368: case 369: case 370: case 371: case 372:
                return materialID ("vase_round");

            default:
                writeln ("Unable to assign material to: ", sponzaIndex);
                return 0;
        }
    }

    /// Gets an identity or custom model transform for a sponza model with the given index.
    private static float[3][4] hardCodedTransforms (size_t sponzaIndex) pure nothrow @safe @nogc
    {
        // The sponza model is working with a strange unit system. 
        enum s = 0.01f;
        switch (sponzaIndex)
        {
            default: // Identity.
                return 
                [
                    [s, 0f, 0f],
                    [0f, s, 0f],
                    [0f, 0f, s],
                    [0f, 0f, 0f]
                ];
        }
    }
}
///
pure nothrow @safe @nogc unittest
{
    import denjin.rendering.traits : isScene;

    // Ensure the scene meets the requirements of the renderer.
    static assert (isScene!Scene);
}