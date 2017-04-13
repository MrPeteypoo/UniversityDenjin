/**
    A window system implementation which encapsulates GLFW.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: MIT
*/
module denjin.window.glfw;

// Phobos.
import std.algorithm    : move;
import std.exception    : enforce;
import std.stdio        : stderr, writeln;
import std.string       : toStringz;

// Engine.
import denjin.window.iwindow;

// External.
import derelict.glfw3;
import erupted;

// Vulkan support.
mixin DerelictGLFW3_VulkanBind;

/// A window management system which encapsulates GLFW.
final class WindowGLFW : IWindow
{
    alias Window = GLFWwindow;

    uint    m_width;    /// How many pixels wide the window currently is.
    uint    m_height;   /// How many pixels tall the window currently is.
    string  m_title;    /// The title of the window, as it is displayed to the user.
    Window* m_window;   /// A pointer to a GLFW window handle.

    public:

        /// Ensures the GLFW dll is loaded and glfw is initialised.
        static this()
        {
            DerelictGLFW3.load();
            DerelictGLFW3_loadVulkan();

            glfwSetErrorCallback (&logGLFWError);
            enforce (glfwInit() == GLFW_TRUE);

        }

        /// Ensures that GLFW is terminated.
        static ~this()
        {
            glfwTerminate();
        }

        /// Ensures the window is destroyed.
        nothrow @nogc
        ~this()
        {
            clean();
        }

        override
        void initialise (in uint width, in uint height, in bool fullscreen, in ref string title)
        {
            enforce (glfwVulkanSupported() == GLFW_TRUE);
            //auto 
        }

        override nothrow @nogc
        void clean()
        {
            if (m_window)
            {
                glfwDestroyWindow (m_window);
                m_window = null;
            }
        }

        override nothrow
        void update (float deltaTime)
        {

        }

        override nothrow
        void render (float deltaTime)
        {

        }

        @property override nothrow
        uint width() const { return m_width; }

        @property override nothrow
        uint height() const { return m_height; }

        @property override nothrow
        string title() const { return m_title; }

        @property override nothrow
        void title (string text)
        {
            assert (m_window);
            m_title = move (text);
            glfwSetWindowTitle (m_window, m_title.toStringz);
        }
}

extern (C) void logGLFWError (int error, const(char)* description) nothrow
{
    try
    {
        stderr.writeln ("GLFW (%i): %s", error, description);
    }
    catch (Exception e)
    {
    }
}


void glfw()
{
    import std.stdio;
    writeln ("GLFW");
    //DerelictGLFW3_loadVulkan();
}