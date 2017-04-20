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
import std.typecons     : Flag, No, Yes;

// Engine.
import denjin.window.iwindow            : IWindow;
import denjin.rendering.vulkan.loader   : VulkanLoader;
import denjin.rendering.vulkan.misc     : enforceSuccess;

// External.
import derelict.glfw3;
import erupted;

// Vulkan support.
mixin DerelictGLFW3_VulkanBind;

/// A window management system which encapsulates GLFW.
final class WindowGLFW : IWindow
{
    alias ProcAddress = typeof (vkGetInstanceProcAddr);

    uint            m_width;        /// How many pixels wide the window currently is.
    uint            m_height;       /// How many pixels tall the window currently is.
    string          m_title;        /// The title of the window, as it is displayed to the user.
    GLFWwindow*     m_window;       /// A pointer to a GLFW window handle.
    ProcAddress     m_vkInstance;   /// A pointer to a function to create a Vulkan instance.
    VulkanLoader    m_loader;       /// Creates and manages the Vulkan instance/device for the window.

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
        m_vkInstance = cast (typeof (vkGetInstanceProcAddr)) glfwGetInstanceProcAddress (null, "vkGetInstanceProcAddr");
        enforce (m_vkInstance != null);

        // GLFW requires certain extensions to be able to create a surface.
        uint32_t count = void;
        const auto glfwExtensions = glfwGetRequiredInstanceExtensions (&count);
        enforce (glfwExtensions != null);

        // Now we can prepare for rendering.
        m_loader.load (m_vkInstance, count, glfwExtensions);
        
        // Create the window.
        glfwWindowHint (GLFW_CLIENT_API, GLFW_NO_API);
        m_window = glfwCreateWindow (cast (int) width, cast (int) height, title.toStringz, null, null);

        // Create the renderable surface.
        glfwCreateWindowSurface (m_loader.instance, m_window, null, &m_loader.surface()).enforceSuccess;

        // And finally store the attributes of the window.
        int finalWidth = void, finalHeight = void;
        glfwGetWindowSize (m_window, &finalWidth, &finalHeight);

        m_width     = cast (uint) finalWidth;
        m_height    = cast (uint) finalHeight;
        m_title     = move (title);
    }

    nothrow @nogc
    ~this()
    {
        clear();
    }

    /// Ensures the window is destroyed.
    override nothrow @nogc
    public void clear()
    {
        if (m_window)
        {
            glfwDestroyWindow (m_window);
            m_window = null;
        }

        m_loader.clear();
    }

    /// Tells glfw to poll events.
    override nothrow
    public void update (float deltaTime)
    {
        glfwPollEvents();
    }

    override nothrow
    public void render (float deltaTime)
    {
    }

    @property override nothrow
    public bool shouldClose()
    in
    {
        assert (m_window);
    }
    body
    {
        return glfwWindowShouldClose (m_window) == GLFW_TRUE;
    }

    @property override nothrow
    public uint width() const { return m_width; }

    @property override nothrow
    public uint height() const { return m_height; }

    @property override nothrow
    public string title() const { return m_title; }

    @property override nothrow
    public void title (string text)
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