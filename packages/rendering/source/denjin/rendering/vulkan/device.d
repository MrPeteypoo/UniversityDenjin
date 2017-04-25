/**
    Contains a representation of a Vulkan logical-device/device-function structure.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: MIT
*/
module denjin.rendering.vulkan.device;

// Phobos.
import std.array                : array;
import std.algorithm.iteration  : filter, uniq;
import std.algorithm.sorting    : sort;
import std.container.array      : Array;
import std.exception            : enforce;
import std.functional           : forward;
import std.string               : startsWith;
import std.typecons             : Flag;

// Engine.
import denjin.rendering.vulkan.misc : enforceSuccess, enumerateQueueFamilyProperties, findPresentableQueueFamily,
                                      findSuitableQueueFamily, safelyDestroyVK;
import denjin.rendering.vulkan.nulls;

// External.
import erupted.functions    : createDispatchDeviceLevelFunctions, DispatchDevice, vkCreateDevice;
import erupted.types        : uint32_t, VkAllocationCallbacks, VkDevice, VkDeviceCreateInfo, VkDeviceQueueCreateInfo, 
                              VkPhysicalDevice, VkQueue, VkQueueFamilyProperties, VkQueueFlagBits, VkSurfaceKHR,
                              VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;

/// A logical device, allowing for the storage and calling of device-level functionality. It can be passed as a 
/// VkDevice to Vulkan functions as necessary. Device-level functions can be called directly using opDispatch too.
struct Device
{
    private
    {
        VkDevice    m_handle        = nullDevice;   /// The handle of the logical device.
        VkQueue     m_renderQueue   = nullQueue;    /// A handle to the queue used for rendering, this should be general purpose.
        VkQueue     m_computeQueue  = nullQueue;    /// A handle to the queue used for compute operations.
        VkQueue     m_transferQueue = nullQueue;    /// A handle to the queue used for transfer operations.
        VkQueue     m_presentQueue  = nullQueue;    /// A handle to the queue used for presenting swapchains.

        DispatchDevice  m_funcs;                /// Contains function pointers to device-level functions related to this logical device.
        uint32_t        m_renderQueueFamily;    /// The index of the queue family used to render.
        uint32_t        m_computeQueueFamily;   /// The index of the queue family used for compute operations.
        uint32_t        m_transferQueueFamily;  /// The index of the queue family used for transfer operations.
        uint32_t        m_presentQueueFamily;   /// The index of the queue family used for present operations.
    }

    // Use subtyping to allow the retrieval of the handle implicitly.
    alias handle this;

    /// The object is not copyable.
    @disable this (this);

    /// Creates a logical device based on the given physical device and creation information. The device will determine
    /// which queue families to use for different tasks so this data will be modified.
    this (VkPhysicalDevice gpu, ref VkDeviceCreateInfo deviceInfo, 
          VkSurfaceKHR presentationSurface = nullSurface,
          in VkAllocationCallbacks* callbacks = null)
    in
    {
        assert (vkCreateDevice);
        assert (gpu != nullPhysDevice);
    }
    body
    {
        // We'll need to retrieve information about the available queue families first.
        const auto familyProperties = gpu.enumerateQueueFamilyProperties();
        setQueueFamilyIndices (familyProperties, gpu, presentationSurface);
        createLogicalDevice (gpu, deviceInfo, callbacks);
        retrieveQueues (familyProperties);
    }

    /// Ensure we free the device upon destruction.
    nothrow @nogc
    ~this()
    {
        clear();
    }

    /// Forward function calls to the funcs structure at compile-time if possible. If the first parameter of the 
    /// function is a VkDevice then the parameter can be omitted.
    public template opDispatch (string func)
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

    /// Gets the Vulkan handle to the managed device.
    public @property inout(VkDevice) handle() inout pure nothrow @safe @nogc { return m_handle; }

    /// Gets a reference to the device-level Vulkan functions relevant to this device.
    public @property ref inout(DispatchDevice) funcs() inout pure nothrow @safe @nogc { return m_funcs; }

    /// Gets the index of the queue family retrieved for rendering.
    public @property uint32_t renderQueueFamily() inout pure nothrow @safe @nogc { return m_renderQueueFamily; }

    /// Gets the index of the queue family retrieved for compute.
    public @property uint32_t computeQueueFamily() inout pure nothrow @safe @nogc { return m_computeQueueFamily; }

    /// Gets the index of the queue family retrieved for transfers.
    public @property uint32_t transferQueueFamily() inout pure nothrow @safe @nogc { return m_transferQueueFamily; }

    /// Gets the index of the queue family retrieved for presenting swapchain images.
    public @property uint32_t presentQueueFamily() inout pure nothrow @safe @nogc { return m_presentQueueFamily; }

    /// Gets a copy of the queue handle which supports rendering capabilities.
    public @property inout(VkQueue) renderQueue() inout pure nothrow @safe @nogc { return m_renderQueue; }

    /// Gets a copy of the queue handle which supports compute capabilities.
    public @property inout(VkQueue) computeQueue() inout pure nothrow @safe @nogc { return m_computeQueue; }

    /// Gets a copy of the queue handle which supports transferring data.
    public @property inout(VkQueue) transferQueue() inout pure nothrow @safe @nogc { return m_transferQueue; }

    /// Gets a copy of the queue handle which supports presenting swapchain images.
    public @property inout(VkQueue) presentQueue() inout pure nothrow @safe @nogc { return m_presentQueue; }

    /// Checks whether the device has a queue family dedicated to rendering operations.
    public @property bool hasDedicatedRenderFamily() inout pure nothrow @safe @nogc
    { 
        return mixin (hasDedicatedFamilyCheck!(m_renderQueueFamily.stringof));
    }

    /// Checks whether the device has a queue family dedicated to compute operations.
    public @property bool hasDedicatedComputeFamily() inout pure nothrow @safe @nogc
    { 
        return mixin (hasDedicatedFamilyCheck!(m_computeQueueFamily.stringof));
    }

    /// Checks whether the device has a queue family dedicated to transfer operations.
    public @property bool hasDedicatedTransferFamily() inout pure nothrow @safe @nogc
    { 
        return mixin (hasDedicatedFamilyCheck!(m_transferQueueFamily.stringof));
    }

    /// Checks whether the device has a queue family dedicated to presenting swapchain images.
    public @property bool hasDedicatedPresentFamily() inout pure nothrow @safe @nogc
    { 
        return mixin (hasDedicatedFamilyCheck!(m_presentQueueFamily.stringof));
    }

    /// Destroys the device and returns the logical device to an uninitialised state.
    public void clear() nothrow @nogc
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

    /// Retrieves the first queue for the given queue family index.
    public VkQueue retrieveQueue (in uint32_t queueFamilyIndex)
    in
    {
        assert (m_funcs.vkGetDeviceQueue);
    }
    out (result)
    {
        assert (result != nullQueue || queueFamilyIndex == uint32_t.max);
    }
    body
    {
        if (queueFamilyIndex != uint32_t.max)
        {
            VkQueue output = nullQueue;
            m_funcs.vkGetDeviceQueue (m_handle, queueFamilyIndex, 0, &output);
            return output;
        }

        return nullQueue;
    }

    /// Determines whether the given name is a function available to the device.
    public static template isVkFunc (string name)
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

    /// Searches through the given family properties, setting suitable queue family indices for each type of queue.
    private void setQueueFamilyIndices (in ref Array!VkQueueFamilyProperties familyProperties, VkPhysicalDevice gpu,
                                        VkSurfaceKHR surface)
    {
        // Next we can choose an appropriate queue family to use based on our requirements.
        m_renderQueueFamily     = findSuitableQueueFamily (familyProperties[], VkQueueFlagBits.VK_QUEUE_GRAPHICS_BIT);
        m_computeQueueFamily    = findSuitableQueueFamily (familyProperties[], VkQueueFlagBits.VK_QUEUE_COMPUTE_BIT);
        m_transferQueueFamily   = findSuitableQueueFamily (familyProperties[], VkQueueFlagBits.VK_QUEUE_TRANSFER_BIT);

        if (surface != nullSurface)
        {
            const auto familyCount = cast (uint32_t) familyProperties.length;
            m_presentQueueFamily = findPresentableQueueFamily (familyCount, gpu, surface);
        }
    }

    /// Creates a logical device from the given GPU based on the current queue family indices.
    private void createLogicalDevice (VkPhysicalDevice gpu, ref VkDeviceCreateInfo deviceInfo, 
                                      in VkAllocationCallbacks* callbacks)
    out
    {
        assert (m_handle != nullDevice);
    }
    body
    {
        // Now we can compile information about the required queue families.
        immutable float[1] queuePriorities = [1f];
        const auto familyIndices = 
            [m_renderQueueFamily, m_computeQueueFamily, m_transferQueueFamily, m_presentQueueFamily]
                .sort()
                .uniq()
                .filter!(a => a != uint32_t.max)
                .array();

        auto queueInfos = new VkDeviceQueueCreateInfo[familyIndices.length];
        foreach (i, ref queueInfo; queueInfos)
        {
            queueInfo.sType             = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
            queueInfo.pNext             = null;
            queueInfo.flags             = 0;
            queueInfo.queueFamilyIndex  = familyIndices[i];
            queueInfo.queueCount        = 1;
            queueInfo.pQueuePriorities  = queuePriorities.ptr;
        }

        // Update the device info and create the device.
        deviceInfo.queueCreateInfoCount = cast (uint32_t) queueInfos.length;
        deviceInfo.pQueueCreateInfos    = queueInfos.ptr;

        vkCreateDevice (gpu, &deviceInfo, callbacks, &m_handle).enforceSuccess;
        m_funcs = createDispatchDeviceLevelFunctions (m_handle);
    }

    /// Retrieves a handle for each queue type which specify an index other than uint32_t.max.
    private void retrieveQueues (in ref Array!VkQueueFamilyProperties familyProperties)
    out
    {
        assert (!(m_renderQueue == nullQueue && 
                  m_computeQueue == nullQueue &&
                  m_transferQueue == nullQueue &&
                  m_presentQueue == nullQueue));
    }
    body
    {
        m_renderQueue   = retrieveQueue (m_renderQueueFamily);
        m_computeQueue  = retrieveQueue (m_computeQueueFamily);
        m_transferQueue = retrieveQueue (m_transferQueueFamily);
        m_presentQueue  = retrieveQueue (m_presentQueueFamily);
    }

    /// Returns code which will check whether the given member has a unique queue family.
    /// Params: s = Ideally a member.stringof representation of the member to check.
    private template hasDedicatedFamilyCheck (string s)
    {
        import std.meta     : AliasSeq, Filter, anySatisfy;
        import std.traits   : Select;

        static assert (anySatisfy!(isMember, testAgainst));
        template isMember (string check)
        {
            enum isMember = Select!(s == check, true, false);
        }

        template isDifferentMember (string check)
        {
            enum isDifferentMember = !isMember!(check);
        }

        template code (string test, Members...)
        {
            static if (Members.length > 0)
            {
                enum code = s ~ "!=" ~ test ~ " && " ~ code!(Members);
            }
            else
            {
                enum code = s ~ " != " ~ test;
            }
        }

        enum testAgainst = AliasSeq!
        (
             m_renderQueueFamily.stringof,
             m_computeQueueFamily.stringof,
             m_transferQueueFamily.stringof,
             m_presentQueueFamily.stringof,
             uint32_t.max.stringof
        );
        enum excludingCurrentMember  = Filter!(isDifferentMember, testAgainst);
        enum hasDedicatedFamilyCheck = code!(excludingCurrentMember);
    }
}