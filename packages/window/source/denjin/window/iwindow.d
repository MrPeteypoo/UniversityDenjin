/**
    A basic interface to window management systems.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: MIT
*/
module denjin.window.iwindow;

/// An interface to be implemented by window management systems.
interface IWindow
{
    /// Requests initialisation of the window system with the given parameters.
    void initialise (in uint width, in uint height, in bool fullscreen, in ref string title)
    in
    {
        assert (width != 0);
        assert (height != 0);
    }

    /// Requests the window free any resources and return to a clean state.
    nothrow @nogc
    void clean();

    /// Requests that the window performs any required updates.
    /// Params: deltaTime = The number of seconds since the last update.
    nothrow
    void update (float deltaTime);

    /// Requests that a frame be rendered by the GPU.
    /// Params: deltaTime = The number of seconds since the last update.
    nothrow
    void render (float deltaTime);

    /// Gets how many pixels wide the window is.
    @property nothrow
    uint width() const;

    /// Gets how many pixels tall the window is.
    @property nothrow
    uint height() const;

    /// Gets the title of the window, as it is displayed by the OS.
    @property nothrow
    string title() const;

    /// Sets the title of the window, as it is displayed by the OS.
    @property nothrow
    void title (string text);
}