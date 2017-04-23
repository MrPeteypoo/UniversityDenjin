/**
    A window system implementation which encapsulates GLFW.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: MIT
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
final class WindowGLFW : IWindow
{
    private
    {
        uint        m_width;    /// How many pixels wide the window currently is.
        uint        m_height;   /// How many pixels tall the window currently is.
        string      m_title;    /// The title of the window, as it is displayed to the user.
        GLFWwindow* m_window;   /// A pointer to a GLFW window handle.
        IRenderer   m_renderer; /// The renderer managed by the window system. GLFW supports OpenGL and Vulkan but only Vulkan is implemented right now.

        /// The application-wide Vulkan instance from which devices and renderers can be created from. Realistically this
        /// should not be managed here because it means we can't have two GLFW windows in use at the same time. Not a
        /// a problem for this stage of development but it needs to be moved at some point.
        Instance m_vulkan; 
    }

    /// Ensures the GLFW and Vulkan dlls are loaded and glfw is initialised.
    public static this()
    {
        DerelictGLFW3.load();
        DerelictGLFW3_loadVulkan();

        glfwSetErrorCallback (&logGLFWError);
        enforce (glfwInit() == GLFW_TRUE);   
    }

    /// Ensures that GLFW is terminated.
    public static ~this()
    {
        glfwTerminate();
    }

    /// Creates a window using GLFW and attaches a basic Vulkan surface to the window, for use with a renderer.
    /// Params:
    ///     width       = How many pixels wide the window should be.
    ///     height      = How many pixels tall the window should be.
    ///     fullscreen  = Should the window cover the entire screen?
    ///     title       = The title of the window, to be displayed by the OS.
    public this (in uint width, in uint height, Flag!"isFullscreen" isFullscreen, string title)
    out
    {
        assert (m_window);
        assert (m_width != 0);
        assert (m_height != 0);
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
        m_renderer = m_vulkan.createRenderer (surface);

        // And finally store the attributes of the window.
        int finalWidth = void, finalHeight = void;
        glfwGetWindowSize (m_window, &finalWidth, &finalHeight);

        m_width     = cast (uint) finalWidth;
        m_height    = cast (uint) finalHeight;
        m_title     = move (title);
    }

    ~this() nothrow
    {
        clear();
    }

    /// Ensures the window is destroyed.
    public override void clear() nothrow
    {
        if (m_window)
        {
            glfwDestroyWindow (m_window);
            m_window = null;
        }

        m_vulkan.clear();
    }

    /// Tells glfw to poll events.
    public override void update (float deltaTime) nothrow
    {
        glfwPollEvents();
    }

    public override void render (float deltaTime) nothrow
    {
    }
    
    public @property override bool shouldClose() nothrow
    in
    {
        assert (m_window);
    }
    body
    {
        return glfwWindowShouldClose (m_window) == GLFW_TRUE;
    }

    public override @property uint width() const nothrow { return m_width; }
    public override @property uint height() const nothrow { return m_height; }
    public override @property string title() const nothrow { return m_title; }
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

/// Takes an integer error value and attempts to convert it to a string representation of the error code.
/// Params: error = An error value to be converted.
/// Returns: Either the string representation of the enum that the error corresponds to, or a string of the error code.
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