module denjin.engine;

// Phobos.
import std.typecons : Flag, No, Yes;

// Engine.
import denjin.window    : IWindow, WindowGLFW;
import denjin.rendering : IRenderer;

/// An incredibly basic "Engine" structure, this holds the different game systems and manages initialisation/shutdown.
struct Engine
{
    IWindow     window;     /// A reference to a window management system, hard coded to GLFW right now.
    IRenderer   renderer;   /// A reference to a rendering system, this is created by the window system.

    /// Ensure we graciously shut down.
    public void clear() nothrow
    {
        // Window system "own" rendering systems so we can ignore that.
        window.clear();
    }

    /// Construct each required system and prepare for running.
    void initialise()
    {
        // Create/retrieve the systems.
        window      = new WindowGLFW (1280, 720, No.isFullscreen, "Denjin");
        renderer    = window.renderer;

        // Extra initialisationa as required.
        renderer.load();
    }

    /// Starts the game loop.
    void run()
    {
        while (!window.shouldClose())
        {
            window.update (0f);
            renderer.update (0f);

            if (window.isVisible)
            {
                renderer.render();
            }
        }
    }
}