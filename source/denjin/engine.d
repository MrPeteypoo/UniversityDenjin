/**
    Core engine functionality, an entry point for client-applications that want to use the engine.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: Copyright © 2017, Simon Peter Campbell
    License: MIT
*/
module denjin.engine;

// Phobos.
import core.memory  : GC;
import std.datetime : Clock, ClockType, SysTime;
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
    import denjin.scene     : Scene;
}

/// An incredibly basic "Engine" structure, this holds the different game systems and manages initialisation/shutdown.
struct Engine
{
    alias Window    = IWindow!(Assets, Scene);
    alias Renderer  = Window.Renderer;

    Assets*     assets;     /// A pointer to Denjins asset management system.
    Window      window;     /// A reference to a window management system, hard coded to GLFW right now.
    Renderer    renderer;   /// A reference to a rendering system, this is created by the window system.
    Scene*      scene;      /// A pointer to Denjins scene management system.
    SysTime     time;       /// Helps keep track of the time between frames.

    /// Construct each required system and prepare for running.
    void initialise()
    {
        // Ensure we destroy resources straight away.
        scope (failure) clear;
        scope (success) GC.collect;

        // Create/retrieve the systems.
        assets      = new Assets ("THIS PARAM DOES NOTHING");
        window      = new WindowGLFW!(Assets, Scene)(1280, 720, No.isFullscreen, "Denjin");
        renderer    = window.renderer;
        scene       = new Scene ("THIS PARAM DOES NOTHING");

        // Extra initialisationa as required.
        renderer.load (*assets, *scene);
    }

    /// Ensure we graciously shut down.
    void clear() nothrow
    {
        try
        {
            scope (exit)
            {
                assets      = null;
                window      = null;
                renderer    = null;
                scene       = null;
            }

            // Window system "own" rendering systems so we can ignore that.
            if (window)
            {
                window.clear;
            }
            if (assets)
            {
                assets.clear;
            }
        }
        catch (Throwable)
        {
        }
    }

    /// Starts the game loop.
    void run()
    in
    {
        assert (assets);
        assert (window);
        assert (renderer);
        assert (scene);
    }
    body
    {
        time = Clock.currTime!(ClockType.precise);
        while (!window.shouldClose())
        {
            auto currentTime    = Clock.currTime!(ClockType.precise);
            auto difference     = currentTime - time;
            auto nanoSeconds    = difference.total!"nsecs";
            auto seconds        = nanoSeconds / 1_000_000_000.0;
            auto delta          = cast (float) seconds;

            window.update (delta);
            renderer.update (delta);
            scene.update (delta);

            if (window.isVisible)
            {
                renderer.render (*scene);
            }

            time = currentTime;
        }
    }
}