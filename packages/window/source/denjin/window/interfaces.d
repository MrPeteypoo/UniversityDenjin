/**
    Contains implementation-agnostic interfaces required for window management systems.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: MIT
*/
module denjin.window.interfaces;

/// An interface to be implemented by window management systems.
interface IWindow
{
    /// Requests that the window get rid of every resource it owns and close if necessary.
    void clear() nothrow;

    /// Requests that the window performs any required updates.
    /// Params: deltaTime = The number of seconds since the last update.
    void update (float deltaTime) nothrow;

    /// Requests that a frame be rendered by the GPU.
    /// Params: deltaTime = The number of seconds since the last update.
    void render (float deltaTime) nothrow;

    /// Checks if the window has been told to close by the user.
    @property bool shouldClose() nothrow;

    /// Gets how many pixels wide the window is.
    @property uint width() const nothrow;

    /// Gets how many pixels tall the window is.
    @property uint height() const nothrow;

    /// Gets the title of the window, as it is displayed by the OS.
    @property string title() const nothrow;

    /// Sets the title of the window, as it is displayed by the OS.
    @property void title (string text) nothrow;
}