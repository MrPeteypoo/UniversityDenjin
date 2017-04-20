/**
    Contains a representation of a Vulkan logical-device/device-function structure.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: MIT
*/
module denjin.rendering.vulkan.device;

// Phobos.
import std.functional   : forward;
import std.string       : startsWith;

// Engine.
import denjin.rendering.vulkan.misc : enforceSuccess, nullHandle, safelyDestroyVK;

// External.
import erupted.functions    : createDispatchDeviceLevelFunctions, DispatchDevice, vkCreateDevice;
import erupted.types        : VkAllocationCallbacks, VkDevice, VkDeviceCreateInfo, VkPhysicalDevice;

/// A logical device, allowing for the storage and calling of device-level functionality. It can be passed as a 
/// VkDevice to Vulkan functions as necessary. Device-level functions can be called directly using opDispatch too.
struct VulkanDevice
{
    private VkDevice        m_handle = nullHandle!VkDevice; /// The handle of the logical device.
    private DispatchDevice  m_funcs;                        /// Contains function pointers to device-level functions related to this logical device.

    // Use subtyping to allow the retrieval of the handle implicitly.
    alias handle this;

    /// Gets a const copy of the device handle.
    pure nothrow @safe @nogc
    @property const(VkDevice) handle() const { return m_handle; }

    /// Gets a modifiable copy of the device handle.
    pure nothrow @safe @nogc
    @property VkDevice handle() { return m_handle; }

    /// Gets a const reference to the available device-level functions.
    pure nothrow @safe @nogc
    @property ref const(DispatchDevice) funcs() const { return m_funcs; }

    /// The object is not copyable.
    @disable this (this);

    /// Ensure we free the device upon destruction.
    nothrow @nogc
    ~this()
    {
        clear();
    }

    /// Forward function calls to the funcs structure at compile-time if possible. If the first parameter of the 
    /// function is a VkDevice then the parameter can be omitted.
    template opDispatch (string func)
        if (func.startsWith ("vk"))
    {
        auto opDispatch (T...) (auto ref T params)
            if (isVkFunc!func)
        {
            import std.traits : Parameters;

            alias FuncType      = typeof (__traits (getMember, funcs, func));
            alias parameters    = Parameters!FuncType;
            enum target         = m_funcs.stringof ~ "." ~ func;

            static if (params.length == 0 || parameters.length == 0)
            {
                return mixin (target);
            }

            else static if (is (parameters[0] == VkDevice))
            {
                return mixin (target)(handle, forward!params);
            }

            else
            {
                return mixin (target)(forward!params);
            }
        }
    }

    void create (ref VkPhysicalDevice physicalDevice, in ref VkDeviceCreateInfo info, in VkAllocationCallbacks* alloc = null)
    in
    {
        assert (vkCreateDevice);
        assert (physicalDevice != nullHandle!VkPhysicalDevice);
    }
    out
    {
        assert (handle != nullHandle!VkDevice);
    }
    body
    {
        clear();
        vkCreateDevice (physicalDevice, &info, alloc, &m_handle).enforceSuccess;
        m_funcs = createDispatchDeviceLevelFunctions (m_handle);
    }

    /// Destroys the device and returns the logical device to an uninitialised state.
    nothrow @nogc
    void clear()
    {
        m_handle.safelyDestroyVK (m_funcs.vkDestroyDevice, m_handle, null);
        m_funcs = DispatchDevice.init;
    }

    /// Determines whether the given name is a function available to the device.
    private template isVkFunc (string name)
    {
        import std.traits : isFunctionPointer, hasMember;

        static if (hasMember!(DispatchDevice, name))
        {
            alias Type      = typeof (__traits (getMember, DispatchDevice, name));
            enum isVkFunc   = isFunctionPointer!Type;
        }
        else
        {
            enum isVkFunc = false;
        }
    }
}