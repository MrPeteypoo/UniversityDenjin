/**
    Contains a representation of a Vulkan logical-device/device-function structure.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: MIT
*/
module denjin.rendering.vulkan.device;

// Phobos.
import std.container.array  : Array;
import std.exception        : enforce;
import std.functional       : forward;
import std.string           : startsWith;

// Engine.
import denjin.rendering.vulkan.misc : enforceSuccess, nullHandle, safelyDestroyVK;

// External.
import erupted.functions    : createDispatchDeviceLevelFunctions, DispatchDevice, vkCreateDevice;
import erupted.types        : uint32_t, VkAllocationCallbacks, VkDevice, VkDeviceCreateInfo, VkDeviceQueueCreateInfo, 
                              VkPhysicalDevice, VkQueue;

/// A logical device, allowing for the storage and calling of device-level functionality. It can be passed as a 
/// VkDevice to Vulkan functions as necessary. Device-level functions can be called directly using opDispatch too.
struct VulkanDevice
{
    private
    {
        alias Queues    = Array!VkQueue;
        enum nullDevice = nullHandle!VkDevice;

        VkDevice        m_handle = nullDevice;  /// The handle of the logical device.
        uint32_t        m_renderQueueFamily;    /// The index of the queue family used to render.
        uint32_t        m_presentQueueFamily;   /// The index of the queue family used to present to the display.
        Queues          m_renderQueues;         /// Contains every queue available, as specified during device creation.
        Queues          m_presentQueues;        /// Contains every queue available for presenting, this will be empty if a single queue family is used for both tasks.
        DispatchDevice  m_funcs;                /// Contains function pointers to device-level functions related to this logical device.
    }

    // Use subtyping to allow the retrieval of the handle implicitly.
    alias handle this;

    /// The object is not copyable.
    @disable this (this);

    /// Creates the Vulkan device based in the given physical device and creation information.
    this (ref VkPhysicalDevice physicalDevice, in ref VkDeviceCreateInfo info, in VkAllocationCallbacks* alloc = null,
          in uint32_t renderQueueIndex = uint32_t.max, in uint32_t presentQueueIndex = uint32_t.max)
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
        // Ensure we clean up after ourselves.
        clear();

        // Create the device and retrieve the device-level function pointers.
        vkCreateDevice (physicalDevice, &info, alloc, &m_handle).enforceSuccess;
        m_funcs = createDispatchDeviceLevelFunctions (m_handle);

        // Now we need to initialise the queues.
        const auto infos        = info.pQueueCreateInfos[0..info.queueCreateInfoCount];
        m_renderQueueFamily     = renderQueueIndex;
        m_presentQueueFamily    = presentQueueIndex;

        if (m_renderQueueFamily != uint32_t.max)
        {
            retrieveQueues (infos, m_renderQueueFamily, m_renderQueues);
        }
        if (m_presentQueueFamily != uint32_t.max && m_presentQueueFamily != m_renderQueueFamily)
        {
            retrieveQueues (infos, m_renderQueueFamily, m_renderQueues);
        }  
    }

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
                // No need to check the validity of the function as they may be checking themselves.
                return mixin (target);
            }

            else static if (is (parameters[0] == VkDevice))
            {
                // Confirm the function is valid before calling.
                assert (target);
                return mixin (target)(handle, forward!params);
            }

            else
            {
                // Confirm the function is valid before calling.
                assert (target);
                return mixin (target)(forward!params);
            }
        }
    }

    /// Destroys the device and returns the logical device to an uninitialised state.
    nothrow @nogc
    void clear()
    {
        // Be sure to wait until the device is idle to destroy it.
        if (handle != nullDevice)
        {
            assert (m_funcs.vkDeviceWaitIdle);
            m_funcs.vkDeviceWaitIdle (m_handle);
            m_handle.safelyDestroyVK (m_funcs.vkDestroyDevice, m_handle, null);
            m_funcs = DispatchDevice.init;
        }
    }

    /// Retrieves the queues for the given queue family index.
    void retrieveQueues (in VkDeviceQueueCreateInfo[] queueInfo, in uint32_t queueFamilyIndex, ref Queues container)
    in
    {
        assert (m_funcs.vkGetDeviceQueue);
    }
    body
    {
        foreach (ref info; queueInfo)
        {
            if (info.queueFamilyIndex == queueFamilyIndex)
            {
                container.length = info.queueCount;
                foreach (i; 0..info.queueCount)
                {
                    m_funcs.vkGetDeviceQueue (m_handle, queueFamilyIndex, i, &container[i]);
                    enforce (container[i]);
                }
            }
        }
    }

    /// Gets a const copy of the device handle.
    pure nothrow @safe @nogc
    @property const(VkDevice) handle() const { return m_handle; }

    /// Gets a modifiable copy of the device handle.
    pure nothrow @safe @nogc
    @property VkDevice handle() { return m_handle; }

    /// Gets a const reference to the available device-level functions.
    pure nothrow @safe @nogc
    @property ref const(DispatchDevice) funcs() const { return m_funcs; }

    /// Gets the index of the queue family that was specified for rendering.
    pure nothrow @safe @nogc
    @property uint32_t renderQueueFamily() const { return m_renderQueueFamily; }

    /// Gets the index of the queue family that was specified for presenting.
    pure nothrow @safe @nogc
    @property uint32_t presentQueueFamily() const { return m_presentQueueFamily; }

    /// Gets a const reference to the render queues loaded during device creation.
    pure nothrow @safe @nogc
    @property ref const(Queues) renderQueues() const { return m_renderQueues; }

    /// Gets a const reference to the presentation queues loaded during device creation. These queues may be the same
    /// as the render queues as they may come from the same family. Be careful.
    pure nothrow @safe @nogc
    @property ref const(Queues) presentQueues() const 
    { 
        return hasPresentableRenderQueues ? m_renderQueues : m_presentQueues;
    }

    /// Checks whether render queue family and present queue family indices are the same. If they are then it's likely
    /// that presentation commands can be called in the normal render queues.
    pure nothrow @safe @nogc
    @property bool hasPresentableRenderQueues() const 
    { 
        if (m_renderQueueFamily == uint32_t.max && m_presentQueueFamily == uint32_t.max)
        {
            return false;
        }
        return m_renderQueueFamily == m_presentQueueFamily; 
    }

    /// Determines whether the given name is a function available to the device.
    static template isVkFunc (string name)
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