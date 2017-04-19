/**
    A basic interface to window management systems.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: MIT
*/
module denjin.window.iwindow;

/// An interface to be implemented by window management systems.
interface IWindow
{
    /// Requests that the window performs any required updates.
    /// Params: deltaTime = The number of seconds since the last update.
    nothrow
    void update (float deltaTime);

    /// Requests that a frame be rendered by the GPU.
    /// Params: deltaTime = The number of seconds since the last update.
    nothrow
    void render (float deltaTime);

    /// Checks if the window has been told to close by the user.
    @property nothrow
    bool shouldClose();

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