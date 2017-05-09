/**
    Contains implementation-agnostic interfaces required for window management systems.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: Copyright © 2017, Simon Peter Campbell
    License: MIT
*/
module denjin.window.interfaces;

// Engine.
import denjin.rendering.interfaces  : IRenderer;
import denjin.rendering.traits      : isAssets, isScene;

/** 
    An interface to be implemented by window management systems. Window systems are in charge of initialising rendering
    systems as they are often tightly coupled.

    Params:
        Assets  = An asset management system which a renderer will load resources from.
        Scene   = A scene management system which a renderer can use to render frames with.

    See_Also:
        isAssets, isScene
*/
interface IWindow (Assets, Scene)
    if (isAssets!Assets && isScene!Scene)
{
    /// The asset and scene management systems are used to specify the renderer interface.
    alias Renderer = IRenderer!(Assets, Scene);

    /// Requests that the window get rid of every resource it owns and close if necessary.
    void clear() nothrow;

    /// Requests that the window performs any required updates.
    /// Params: deltaTime = The number of seconds since the last update.
    void update (float deltaTime);

    /// Gets a reference to the currently owned renderer.
    @property inout(Renderer) renderer() inout pure nothrow @safe @nogc;

    /// Checks if the window has been told to close by the user.
    @property bool shouldClose() const nothrow;

    /// Checks whether the window is currently visible on the users screen.
    @property bool isVisible() const nothrow;

    /// Gets how many pixels wide the window is.
    @property uint width() const nothrow;

    /// Gets how many pixels tall the window is.
    @property uint height() const nothrow;

    /// Gets the title of the window, as it is displayed by the OS.
    @property string title() const nothrow;

    /// Sets the title of the window, as it is displayed by the OS.
    @property void title (string text) nothrow;
}