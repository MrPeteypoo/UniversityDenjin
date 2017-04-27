/**
    Vulkan contains dispatchable and non-dispatchable object handles. The type of handle an object uses is not obvious.
    The difference is representing by some handle types being represented by pointer aliaes and others by ulong. Vulkan
    provides VK_NULL_HANDLE which represents null in C but in D there are different type safety rules. As such we have
    VK_NULL_HANDLE for dispatchable handles and VK_NULL_ND_HANDLE for non-dispatchable handles. This module provides
    enums and a template which returns the correct null handle value for the given type.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: MIT
*/
module denjin.rendering.vulkan.nulls;

// Phobos.
import std.traits : isBuiltinType, isPointer;

// External.
import erupted.types : VkDebugReportCallbackEXT, VkCommandBuffer, VkCommandPool, VkDevice, VkDeviceMemory, VkFence, 
                       VkFramebuffer, VkImage, VkImageView, VkInstance, VkPhysicalDevice, VkQueue, VkRenderPass, 
                       VkSemaphore, VkSurfaceKHR, VkSwapchainKHR;

/// Gets the correct null handle to use when checking if a VK handle is null.
/// Params: T = The type to retrieve the null handle for.
template nullHandle (T)
    if (isBuiltinType!T || isPointer!T)
{
    import erupted.types : VK_NULL_HANDLE, VK_NULL_ND_HANDLE;

    enum handle = T.init;
    static if (__traits (compiles, handle == VK_NULL_HANDLE))
    {
        enum nullHandle = VK_NULL_HANDLE;
    }

    else static if (__traits (compiles, handle == VK_NULL_ND_HANDLE))
    {
        enum nullHandle = VK_NULL_ND_HANDLE;
    }

    else
    {
        static assert (false, "No Vulkan null handle for type: " ~ T.stringof);
    }
}

enum nullCMDBuffer      = nullHandle!VkCommandBuffer;
enum nullDebug          = nullHandle!VkDebugReportCallbackEXT;
enum nullDevice         = nullHandle!VkDevice;
enum nullFence          = nullHandle!VkFence;
enum nullFramebuffer    = nullHandle!VkFramebuffer;
enum nullImage          = nullHandle!VkImage;
enum nullImageView      = nullHandle!VkImageView;
enum nullInstance       = nullHandle!VkInstance;
enum nullMemory         = nullHandle!VkDeviceMemory;
enum nullPass           = nullHandle!VkRenderPass;
enum nullPhysDevice     = nullHandle!VkPhysicalDevice;
enum nullPool           = nullHandle!VkCommandPool;
enum nullQueue          = nullHandle!VkQueue;
enum nullSemaphore      = nullHandle!VkSemaphore;
enum nullSurface        = nullHandle!VkSurfaceKHR;
enum nullSwapchain      = nullHandle!VkSwapchainKHR;