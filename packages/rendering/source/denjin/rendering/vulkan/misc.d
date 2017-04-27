/**
    A collection of miscellaneous vulkan-related functionality.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: MIT
*/
module denjin.rendering.vulkan.misc;

// Phobos.
import core.stdc.string     : strcmp;
import std.container.array  : Array;
import std.conv             : to;
import std.exception        : enforce;
import std.range.primitives : isRandomAccessRange;
import std.traits           : isBuiltinType, isFunctionPointer, isPointer, Unqual;

// Engine.
import denjin.rendering.vulkan.device   : Device;
import denjin.rendering.vulkan.logging  : logQueueFamilyProperties;
import denjin.rendering.vulkan.nulls;

// External.
import erupted.functions :  vkGetPhysicalDeviceSurfaceSupportKHR, vkGetPhysicalDeviceQueueFamilyProperties;
import erupted.types;


/// Throws an exception if the error code of a Vulkan function indicates failure.
/// Params: code = The Vulkan error code that was generated.
void enforceSuccess (in VkResult code) pure @safe
{
    enforce (code == VK_SUCCESS, code.to!string);
}

/// Given a physical device, this function will enumerate the available queue families and return them in a container.
Array!VkQueueFamilyProperties enumerateQueueFamilyProperties (VkPhysicalDevice gpu)
{
    auto array = Array!VkQueueFamilyProperties();
    uint32_t count = void;
    vkGetPhysicalDeviceQueueFamilyProperties (gpu, &count, null);

    array.length = count;
    vkGetPhysicalDeviceQueueFamilyProperties (gpu, &count, &array.front());

    logQueueFamilyProperties (array[]);
    return array;
}

/// Attempts to find a suitable queue family index by iterating over the given family properties and doing two things.
/// Firstly, it will look for a queue family which is dedicated to the requirements described. Secondly, if a dedicated
/// queue family doesn't exist then it will look for one which is more general purpose but still fulfils the 
/// requirements. 
/// Params:
///     familyProperties    = The family properties available to a physical device.
///     flags               = The requirements of the different family queues.
/// Returns: An index value if successful, uint32_t.max if not.
uint32_t findSuitableQueueFamily (Range)(auto ref Range familyProperties, in VkQueueFlags flags)
    if (isRandomAccessRange!Range && is (Unqual!(typeof (familyProperties[0])) == VkQueueFamilyProperties))
{
    // We only need to keep track of the fallback as we can return early when we find a dedicate queue family.
    uint32_t fallback       = uint32_t.max;
    VkQueueFlags current    = void;

    foreach (i; 0..cast (uint32_t) familyProperties.length)
    {
        current = familyProperties[i].queueFlags;

        // The flags will be exactly the same if the queue family is dedicated to the given task.
        if ((current | flags) == flags)
        {
            return i;
        }

        // To find general purpose families we only need to check whether the flags exist in the queue family.
        else if ((current & flags) == flags)
        {
            fallback = i;
        }
    }
    return fallback;
}

/// Attempts to find the first queue family which supports presenting swapchain images to the screen.
/// Params: 
///     queueFamilyCount    = The total number of queue families on the given physical device.
///     gpu                 = The physical device which will be used to present.
///     surface             = The surface which will be presented to.
/// Returns: An index value if a suitable queue family is found, uint32_t.max if not.
uint32_t findPresentableQueueFamily (in uint32_t queueFamilyCount, VkPhysicalDevice gpu, VkSurfaceKHR surface)
in
{
    assert (gpu != nullPhysDevice);
    assert (surface != nullSurface);
}
body
{
    VkBool32 isPresentable = void;
    foreach (i; 0..queueFamilyCount)
    {
        vkGetPhysicalDeviceSurfaceSupportKHR (gpu, i, surface, &isPresentable).enforceSuccess;
        
        if (isPresentable)
        {
            return i;
        }
    }
    return uint32_t.max;
}

/// Attempts to find the index of the memory type in the given properties which matches the requirements given. 
/// Params:
///     typeBits            = This value will likely come from a call to vkGetImageMemoryRequirements.
///     requiredProperties  = The visibility flags required for the resource.
/// Returns: The index of the memory type meeting the given requirements. uint32_t.max if unsuccessful.
uint32_t memoryTypeIndex (in ref VkPhysicalDeviceMemoryProperties properties, in uint32_t typeBits,
                          in VkMemoryPropertyFlags requiredProperties) pure nothrow @safe @nogc
{
    foreach (i; 0..properties.memoryTypeCount)
    {
        // First we check if current memory type is a potential candidate.
        if ((typeBits & (1 << i)) > 0)
        {
            // Now we must check if the memory type supports the required access properties.
            if ((properties.memoryTypes[i].propertyFlags & requiredProperties) == requiredProperties)
            {
                return i;
            }
        }
    }

    // Indicate failure.
    return uint32_t.max;
}

/// Checks if the given Vulkan handle needs destroying, if so then the given function pointer will be used to destroy
/// the object. A check will be performed to see if the given function pointer is valid, if it isn't valid an assertion
/// will occur.
/// Params:
///     handle      = The VK handle to be destroyed if necessary.
///     destoryFunc = The function to use to destroy the handle.
///     params      = Parameters to be passed to the destroy function.
auto safelyDestroyVK (Handle, Func, T...) (ref Handle handle, in Func destroyFunc, auto ref T params)
    if ((isBuiltinType!Handle || isPointer!Handle) && isFunctionPointer!Func)
{
    import std.functional   : forward;
    import std.traits       : ReturnType;

    // The handle may not need destroying.
    enum nullH = nullHandle!Handle;
    if (handle != nullH)
    {
        // We must ensure the function is valid to avoid null-pointer deferencing.
        if (destroyFunc)
        {
            // Ensure we set the handle to null.
            scope (exit) handle = nullH;
            return destroyFunc (forward!params);
        }
    }

    // Return a blank object if we didn't need or were unable to call the function.
    alias returnType = ReturnType!Func;
    static if (!is (returnType == void))
    {
        return returnType.init;
    }
}

/// Returns a string representation of a packed Vulkan version number. The string will be separated using full stops.
string vulkanVersionString (in uint32_t versionNumber) pure nothrow
{
    return  VK_VERSION_MAJOR (versionNumber).to!string ~ "." ~
            VK_VERSION_MINOR (versionNumber).to!string ~ "." ~
            VK_VERSION_PATCH (versionNumber).to!string;
}