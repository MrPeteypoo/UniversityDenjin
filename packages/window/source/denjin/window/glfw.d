/**
    A window system implementation which encapsulates GLFW.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: Copyright © 2017, Simon Peter Campbell
    License: MIT
*/
module denjin.window.glfw;

// Phobos.
import std.algorithm    : move;
import std.conv         : to;
import std.exception    : enforce;
import std.stdio        : stderr, writefln;
import std.string       : fromStringz, toStringz;
import std.typecons     : Flag;

// Engine.
import denjin.window.interfaces         : IWindow;
import denjin.rendering.interfaces      : IRenderer;
import denjin.rendering.vulkan.instance : Instance;
import denjin.rendering.vulkan.misc     : enforceSuccess;

// External.
import derelict.glfw3;
import erupted;

// Vulkan support.
mixin DerelictGLFW3_VulkanBind;

/// A window management system which encapsulates GLFW.
final class WindowGLFW (Assets, Scene) : IWindow!(Assets, Scene)
{
    private
    {
        bool        m_shouldClose;  /// Tracks whether the application should close, the user may have clicked the close button.
        bool        m_isVisible;    /// Tracks whether the window is currently visible or not.
        int         m_width;        /// How many pixels wide the window currently is.
        int         m_height;       /// How many pixels tall the window currently is.
        string      m_title;        /// The title of the window, as it is displayed to the user.
        GLFWwindow* m_window;       /// A pointer to a GLFW window handle.
        Renderer    m_renderer;     /// The renderer managed by the window system. GLFW supports OpenGL and Vulkan but only Vulkan is implemented right now.

        /** 
            The application-wide Vulkan instance from which devices and renderers can be created from. Realistically this
            should not be managed here because it means we can't have two GLFW windows in use at the same time. Not a
            a problem for this stage of development but it needs to be moved at some point.
        */
        Instance m_vulkan; 
    }

    /// Ensures the GLFW and Vulkan dlls are loaded and glfw is initialised.
    public static this()
    {
        DerelictGLFW3.load();
        DerelictGLFW3_loadVulkan();

        // We may be running in on a headless CI system so don't enforce a successful GLFW initialisation.
        glfwSetErrorCallback (&logGLFWError);
        glfwInit();
    }

    /// Ensures that GLFW is terminated.
    public static ~this()
    {
        glfwTerminate();
    }

    /**
        Creates a window using GLFW and attaches a basic Vulkan surface to the window, for use with a renderer.
        
        Params:
            width           = How many pixels wide the window should be.
            height          = How many pixels tall the window should be.
            isFullscreen    = Should the window cover the entire screen?
            title           = The title of the window, to be displayed by the OS.
    */
    public this (in uint width, in uint height, Flag!"isFullscreen" isFullscreen, string title)
    out
    {
        assert (m_window);
        assert (m_width > 0);
        assert (m_height > 0);
    }
    body
    {
        // Pre-conditions.
        enforce (width != 0);
        enforce (height != 0);
        enforce (glfwVulkanSupported() == GLFW_TRUE);

        // GLFW gives us a platform-independent way of retrieving the function pointer to vkGetInstanceProcAddr.
        auto vkProcAddr = cast (typeof (vkGetInstanceProcAddr)) glfwGetInstanceProcAddress (null, "vkGetInstanceProcAddr");
        enforce (vkProcAddr);

        // GLFW requires certain extensions to be able to create a surface.
        uint32_t count = void;
        const auto glfwExtensions = glfwGetRequiredInstanceExtensions (&count);
        enforce (glfwExtensions);

        // Now we can prepare for rendering.
        glfwWindowHint (GLFW_CLIENT_API, GLFW_NO_API);
        m_window = glfwCreateWindow (cast (int) width, cast (int) height, title.toStringz, null, null);
        m_vulkan = Instance (vkProcAddr, count, glfwExtensions);

        // Create the renderable surface.
        VkSurfaceKHR surface;
        glfwCreateWindowSurface (m_vulkan, m_window, null, &surface).enforceSuccess;

        // Finally we can initialise a Vulkan renderer!
        m_renderer = m_vulkan.createRenderer!(Assets, Scene)(surface);

        // And finally store the attributes of the window.
        glfwGetWindowSize (m_window, &m_width, &m_height);
        m_title = move (title);
    }

    /// Ensures the window is destroyed and the renderer stops running.
    public override void clear() nothrow
    {
        if (m_window)
        {
            glfwDestroyWindow (m_window);
            m_window = null;
        }

        m_renderer.clear();
        m_vulkan.clear();
    }

    /// Tells glfw to poll events.
    public override void update (float deltaTime)
    in
    {
        assert (m_window);
        assert (m_renderer);
    }
    body
    {
        // Ensure the window never stops being responsive.
        glfwPollEvents();

        // Check whether the user wants the application to close.
        m_shouldClose = glfwWindowShouldClose (m_window) == GLFW_TRUE;

        // Check whether the window size has changed in case we need to inform the renderer.
        int width = void, height = void;
        glfwGetWindowSize (m_window, &width, &height);

        // Don't waste time resetting the renderer if the window isn't visible.
        m_isVisible = width != 0 && height != 0;
        if (m_isVisible && (width != m_width || height != m_height))
        {
            m_renderer.reset (cast (uint) width, cast (uint) height);

            // Only update the dimensions if the latest visible dimensions are different.
            m_width     = width;
            m_height    = height;
        }
    }

    public override @property inout(Renderer) renderer() inout pure nothrow @safe @nogc { return m_renderer; }
    public override @property bool shouldClose() const nothrow pure @safe @nogc { return m_shouldClose; }
    public override @property bool isVisible() const nothrow pure @safe @nogc { return m_isVisible; }
    public override @property uint width() const nothrow pure @safe @nogc { return cast(uint) m_width; }
    public override @property uint height() const nothrow pure @safe @nogc { return cast(uint) m_height; }
    public override @property string title() const nothrow pure @safe @nogc { return m_title; }
    public override @property void title (string text) nothrow
    in
    {
        assert (m_window);
    }
    body 
    {
        m_title = move (text);
        glfwSetWindowTitle (m_window, m_title.toStringz);
    }
}

/// A C-accessible callback which writes errors generated by GLFW to stderr.
extern (C) nothrow 
private void logGLFWError (int error, const(char)* description)
{
    try
    {
        string errorString = errorNumberToString (error);
        stderr.writefln ("GLFW Error (%s): %s", errorString, description.fromStringz);
    }
    catch (Exception e)
    {
    }
}

/** 
    Takes an integer error value and attempts to convert it to a string representation of the error code.
    Params: error = An error value to be converted.
    Returns: Either the string representation of the enum that the error corresponds to, or a string of the error code.
*/
pure nothrow @safe
private string errorNumberToString (int error)
{
    // The derelict library seems to be missing an enum!
    static if (!__traits (compiles, GLFW_NO_WINDOW_CONTEXT == error))
    {
        enum GLFW_NO_WINDOW_CONTEXT = 0x0001000A;
    }

    switch (error)
    {
        case GLFW_NOT_INITIALIZED:
            return "GLFW_NOT_INITIALIZED";
        case GLFW_NO_CURRENT_CONTEXT:
            return "GLFW_NO_CURRENT_CONTEXT";
        case GLFW_INVALID_ENUM:
            return "GLFW_INVALID_ENUM";
        case GLFW_INVALID_VALUE:
            return "GLFW_INVALID_VALUE";
        case GLFW_OUT_OF_MEMORY:
            return "GLFW_OUT_OF_MEMORY";
        case GLFW_API_UNAVAILABLE:
            return "GLFW_API_UNAVAILABLE";
        case GLFW_VERSION_UNAVAILABLE:
            return "GLFW_VERSION_UNAVAILABLE";
        case GLFW_PLATFORM_ERROR:
            return "GLFW_PLATFORM_ERROR";
        case GLFW_FORMAT_UNAVAILABLE:
            return "GLFW_FORMAT_UNAVAILABLE";
        case GLFW_NO_WINDOW_CONTEXT:
            return "GLFW_NO_WINDOW_CONTEXT";
        default:
            return error.to!string;
    }
}