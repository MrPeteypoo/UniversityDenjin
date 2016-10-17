module denjin.engine;
import derelict.glfw3.glfw3;
import std.exception;



struct Engine
{
    void run()
    {
        DerelictGLFW3.load();
        scope (exit) DerelictGLFW3.unload();

        enforce (glfwInit(), "GLFW failed to initialise.");
        scope (exit) glfwTerminate();

        GLFWwindow* window = glfwCreateWindow (640, 480, "Denjin", null, null);        
        enforce (window, "Failed to create a window.");
        scope (exit) glfwDestroyWindow(window);

        glfwSetKeyCallback (window, &keyCallback);
        glfwMakeContextCurrent(window);

        while (!glfwWindowShouldClose (window))
        {
            glfwSwapBuffers(window);
            glfwPollEvents();
        }
    }
}

private extern (C) void keyCallback (GLFWwindow* window, int key, int, int action, int) nothrow @nogc
{
    if (key == GLFW_KEY_ESCAPE && action == GLFW_PRESS)
    {
        glfwSetWindowShouldClose (window, GLFW_TRUE);
    }
}