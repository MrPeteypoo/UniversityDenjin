/**
    A basic interface to window management systems.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: MIT
*/
module denjin.window.iwindow;

/// An interface to be implemented by window management systems.
interface IWindow
{
    /// Triggers initialisation of the window system with the given parameters.
    void initialise (in uint width, in uint height, in bool fullscreen, in ref string title) @safe;

    /// Requests that the window performs any required updates.
    /// Params: deltaTime = The number of seconds since the last update.
    void update (float deltaTime) nothrow;

    /// Requests that a frame be rendered by the GPU.
    /// Params: deltaTime = The number of seconds since the last update.
    void render (float deltaTime) nothrow;

    /// Gets how many pixels wide the window is.
    @property uint width() const pure nothrow @safe @nogc;

    /// Gets how many pixels tall the window is.
    @property uint height() const pure nothrow @safe @nogc;

    /// Gets the title of the window, as it is displayed by the OS.
    @property string title() const pure nothrow @safe @nogc;

    /// Sets the title of the window, as it is displayed by the OS.
    @property void title (in ref string text) nothrow @safe @nogc;
}