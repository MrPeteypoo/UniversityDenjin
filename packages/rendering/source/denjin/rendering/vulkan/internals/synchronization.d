/**
    Contains structures of synchronisation objects used by the renderer.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: Copyright © 2017, Simon Peter Campbell
    License: MIT
*/
module denjin.rendering.vulkan.internals.synchronization;

// Phobos.
import std.algorithm.iteration  : each;
import std.traits               : hasMember;

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
    /// Common resources required by every "virtual" frame.
    struct VirtualFrame
    {
        VkSemaphore imageAvailable  = nullSemaphore;    /// Indicates that an image has become available from the presentation engine and writing to it can begin.
        VkSemaphore frameComplete   = nullSemaphore;    /// Indicates that rendering of a frame is complete, no more data will be written to anything.
        VkFence     renderComplete  = nullFence;        /// Tracks whether the render queue has finished being processed.
    }

    VirtualFrame[]  frames;     /// Fences and semaphores for each virtual frame in the renderer.
    size_t          frameIndex; /// The index of the frame to use for retrieving resources.

    /// Returns a member from VirtualFrame for the current frame index.
    public auto ref opDispatch (string member)() @property
        if (hasMember!(VirtualFrame, member))
    in
    {
        assert (frameIndex < frames.length);
    }
    body
    {
        enum target = "frames[frameIndex]." ~ member;
        return mixin (target);
    }

    /// Initialises all semaphore and fence objects ready for use.
    public void create (ref Device device, in size_t virtualFrames, in VkAllocationCallbacks* callbacks = null)
    in
    {
        assert (device != nullDevice);
        assert (virtualFrames > 0);
        assert (frames.length == 0);
    }
    body
    {
        scope (failure) clear (device);
        frames.length = virtualFrames;
        
        foreach (ref frame; frames)
        {
            frame.imageAvailable.createSemaphore (device, callbacks).enforceSuccess;
            frame.frameComplete.createSemaphore (device, callbacks).enforceSuccess;

            enum fenceFlags = VK_FENCE_CREATE_SIGNALED_BIT;
            frame.renderComplete.createFence (device, fenceFlags, callbacks).enforceSuccess;
        }
    }

    /// Destroys all semaphore and fence objects, returning the object to an uninitialised state.
    public void clear (ref Device device, in VkAllocationCallbacks* callbacks = null) nothrow @nogc
    in
    {
        assert (device != nullDevice);
    }
    body
    {
        // Ensure each fence has been signalled before we destroy them.
        waitForFences (device);

        // Now destroy each object.
        immutable semaphoreFunc = device.vkDestroySemaphore;
        immutable fenceFunc     = device.vkDestroyFence;

        foreach (ref frame; frames)
        {
            with (frame)
            {
                imageAvailable.safelyDestroyVK (semaphoreFunc, device, imageAvailable, callbacks);
                frameComplete.safelyDestroyVK (semaphoreFunc, device, frameComplete, callbacks);
                renderComplete.safelyDestroyVK (fenceFunc, device, renderComplete, callbacks);
            }
        }
    }

    /// Attempts to wait for all stored fences to be signalled. The given timeout will be specified for each fence.
    public void waitForFences (ref Device device, in uint64_t timeout = uint64_t.max) nothrow @nogc
    in
    {
        assert (device != nullDevice);
    }
    body
    {
        foreach (ref frame; frames)
        {
            auto fence = frame.renderComplete;
            if (fence != nullFence)
            {
                device.vkWaitForFences (1, &fence, VK_TRUE, timeout);
            }
        }
    }
}