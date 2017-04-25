/**
    Contains structures of synchronisation objects used by the renderer.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: MIT
*/
module denjin.rendering.vulkan.internals.synchronization;

// Phobos.
import std.algorithm.iteration : each;

// Engine.
import denjin.rendering.vulkan.device   : Device;
import denjin.rendering.vulkan.misc     : enforceSuccess, safelyDestroyVK;
import denjin.rendering.vulkan.nulls    : nullDevice, nullFence, nullSemaphore;
import denjin.rendering.vulkan.objects  : createFence, createSemaphore;

// External.
import erupted.types : VkAllocationCallbacks, VkFence, VkSemaphore, VK_FENCE_CREATE_SIGNALED_BIT;

/// Contains semaphores and fences which are used to indicate that different stages of have been performed to prevent
/// data races and undefined behaviour with the multi-threaded API.
struct Syncs
{
    VkSemaphore imageAvailable  = nullSemaphore;    /// Indicates that an image has become available from the presentation engine and writing to it can begin.
    VkSemaphore frameComplete   = nullSemaphore;    /// Indicates that rendering of a frame is complete, no more data will be written to anything.

    size_t      fenceIndex;     /// The index to use when using a fence for a frame.   
    VkFence[]   renderFences;   /// Used to track the completion status of multiple previous frames.

    /// Initialises all semaphore and fence objects ready for use.
    public void create (ref Device device, in size_t fenceCount = 3, in VkAllocationCallbacks* callbacks = null)
    in
    {
        assert (device != nullDevice);
    }
    out
    {
        assert (imageAvailable != nullSemaphore);
        assert (frameComplete != nullSemaphore);
    }
    body
    {
        clear (device);
        imageAvailable.createSemaphore (device, callbacks).enforceSuccess;
        frameComplete.createSemaphore (device, callbacks).enforceSuccess;

        enum fenceFlags = VK_FENCE_CREATE_SIGNALED_BIT;
        renderFences.length = fenceCount;
        renderFences.each!((ref f) => f.createFence (device, fenceFlags, callbacks).enforceSuccess);
    }

    /// Destroys all semaphore and fence objects, returning the object to an uninitialised state.
    public void clear (ref Device device, in VkAllocationCallbacks* callbacks = null) nothrow @nogc
    in
    {
        assert (device != nullDevice);
    }
    body
    {
        immutable semaphoreFunc = device.vkDestroySemaphore;
        immutable fenceFunc     = device.vkDestroyFence;

        imageAvailable.safelyDestroyVK (semaphoreFunc, device, imageAvailable, callbacks);
        frameComplete.safelyDestroyVK (semaphoreFunc, device, frameComplete, callbacks);
        renderFences.each!((ref f) => f.safelyDestroyVK (fenceFunc, device, f, callbacks));
    }

    /// Adjusts the fence index using the given frame count and the number of stored fences.
    public size_t advanceFenceIndex (in size_t frameCount) pure nothrow @safe @nogc
    {
        return fenceIndex = frameCount % renderFences.length;
    }

    /// Returns the fence which should be used to indicate whether render work has completed for a past frame.
    public @property inout(VkFence) renderFence() inout pure nothrow @safe @nogc
    in
    {
        assert (fenceIndex < renderFences.length);
    }
    body
    {
        return renderFences[fenceIndex];
    }
}