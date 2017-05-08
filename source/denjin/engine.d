/**
    Core engine functionality, an entry point for client-applications that want to use the engine.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: Copyright © 2017, Simon Peter Campbell
    License: MIT
*/
module denjin.engine;

// Phobos.
import std.typecons : Flag, No, Yes;

// Engine.
version (unittest)
{
    import denjin;
}
else
{
    import denjin.assets    : Assets;
    import denjin.window    : IWindow, WindowGLFW;
    import denjin.rendering : IRenderer;
}

/// An incredibly basic "Engine" structure, this holds the different game systems and manages initialisation/shutdown.
struct Engine
{
    struct TempA { }
    alias Window    = IWindow!(TempA, TempA);
    alias Renderer  = Window.Renderer;

    Assets*     assets;     /// A pointer to Denjins asset management system.
    Window      window;     /// A reference to a window management system, hard coded to GLFW right now.
    Renderer    renderer;   /// A reference to a rendering system, this is created by the window system.

    /// Construct each required system and prepare for running.
    void initialise()
    {
        // Create/retrieve the systems.
        window      = new WindowGLFW!(TempA, TempA)(1280, 720, No.isFullscreen, "Denjin");
        renderer    = window.renderer;
        assets      = new Assets ("THIS PARAM DOES NOTHING");

        // Extra initialisationa as required.
        auto temp = TempA();
        renderer.load (temp, temp);
    }

    /// Ensure we graciously shut down.
    void clear() nothrow
    {
        // Window system "own" rendering systems so we can ignore that.
        if (window)
        {
            window.clear();
        }

        // Don't clear the assets system if it hasn't been initialised.
        if (assets)
        {
            delete assets;
            assets = null;
        }
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
                auto temp = TempA();
                renderer.render (temp);
            }
        }
    }
}