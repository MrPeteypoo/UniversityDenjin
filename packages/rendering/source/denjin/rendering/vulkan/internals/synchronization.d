/**
    Contains structures of synchronisation objects used by the renderer.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: Copyright © 2017, Simon Peter Campbell
    License: MIT
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
import erupted.types : uint64_t, VkAllocationCallbacks, VkFence, VkSemaphore, VK_FENCE_CREATE_SIGNALED_BIT, VK_TRUE;

/**
    Contains the synchronisation objects required to avoid race conditions.

    Semaphores and fences are used to indicate that different stages of have been performed to prevent data races and 
    undefined behaviour with the multi-threaded API.
*/
struct Syncs
{
    VkSemaphore imageAvailable  = nullSemaphore;    /// Indicates that an image has become available from the presentation engine and writing to it can begin.
    VkSemaphore frameComplete   = nullSemaphore;    /// Indicates that rendering of a frame is complete, no more data will be written to anything.

    size_t      fenceIndex;     /// The index to use when using a fence for a frame.   
    VkFence[]   renderFences;   /// Used to track the completion status of multiple previous frames.

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

        // Ensure each fence has been signalled before we destroy them.
        waitForFences (device);
        imageAvailable.safelyDestroyVK (semaphoreFunc, device, imageAvailable, callbacks);
        frameComplete.safelyDestroyVK (semaphoreFunc, device, frameComplete, callbacks);
        renderFences.each!((ref f) => f.safelyDestroyVK (fenceFunc, device, f, callbacks));
    }

    /// Adjusts the fence index using the given frame count and the number of stored fences.
    public size_t advanceFenceIndex (in size_t frameCount) pure nothrow @safe @nogc
    {
        return fenceIndex = frameCount % renderFences.length;
    }

    /// Attempts to wait for all stored fences to be signalled. The given timeout will be specified for each fence.
    public void waitForFences (ref Device device, in uint64_t timeout = uint64_t.max) nothrow @nogc
    in
    {
        assert (device != nullDevice);
    }
    body
    {
        renderFences.each!((ref VkFence f)
        {
            if (f != nullFence) device.vkWaitForFences (1, &f, VK_TRUE, timeout);
        });
    }
}