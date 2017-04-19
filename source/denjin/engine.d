module denjin.engine;

// Phobos.
import std.typecons : Flag, No, Yes;

// Engine.
import denjin.window : IWindow, WindowGLFW;


struct Engine
{
    IWindow window; /// A reference to a window management system, hard coded to GLFW right now.

    void initialise()
    {
        window = new WindowGLFW (1280, 720, No.isFullscreen, "Denjin");
    }

    void run()
    {
        while (!window.shouldClose())
        {
            window.update (0f);
            window.render (0f);
        }
    }
    /*


        Until I implement the basic engine structure then this placeholder code will exist to ensure Vulkan loads when the engine is ran.
        Many thanks to https://github.com/ParticlePeter/ErupteD-GLFW for providing useful example code! 


    */
    /*void run()
    {
        // load GLFW3 functions 
        DerelictGLFW3.load;

        // load GLFW3 vulkan support functions into current scope
        DerelictGLFW3_loadVulkan();

        // initialize glfw
        glfwInit();
        
        // check if Vulkan is available on this machine
        if( !glfwVulkanSupported()) {
            writeln( "Vulkan is not supported on this Device." );
            return;
        }

        // glfw window specification
        glfwWindowHint( GLFW_CLIENT_API, GLFW_NO_API );
        GLFWwindow* window = glfwCreateWindow( 720, 480, "GLFW3 Vulkan Erupted", null, null );
        glfwSetKeyCallback( window, &keyCallback );
        //glfwMakeContextCurrent( window );

        // load global level functions with glfw
        loadGlobalLevelFunctions( cast( typeof( vkGetInstanceProcAddr ))
            glfwGetInstanceProcAddress( null, "vkGetInstanceProcAddr" ));
        
        // prepare VkInstance creation
        VkApplicationInfo appInfo = {
            pApplicationName: "Vulkan Test with GLFW3",
            apiVersion: VK_MAKE_VERSION( 1, 0, 3 ),
        };
        
        // get the extensions required for for a glfw window with vulkan surface
        uint32_t glfwRequiredExtensionsCount;
        auto glfwRequiredExtensions = glfwGetRequiredInstanceExtensions( &glfwRequiredExtensionsCount );

        // assuming that the extensions are available on this machine, but this should be checked 
        VkInstanceCreateInfo instInfo = {
            pApplicationInfo		: &appInfo,
            enabledExtensionCount	: glfwRequiredExtensionsCount,
            ppEnabledExtensionNames	: glfwRequiredExtensions,
        };
        
        // create the vulkan instance
        VkInstance instance;
        vkCreateInstance( &instInfo, null, &instance ).enforceVK;

        // destroy the instance at scope exist
        scope( exit ) {
            writeln( "Scope exit: destroying instance" );
            if( instance != VK_NULL_HANDLE ) {
                vkDestroyInstance( instance, null );
            }
        }

        // create the window surface with a VkSurfaceKHR
        VkSurfaceKHR surface; 
        glfwCreateWindowSurface( instance, window, null, &surface ).enforceVK;
        scope( exit ) {
            writeln( "Scope exit: destroying surface" );
            vkDestroySurfaceKHR( instance, surface, null );
        }

        // load instance level functions
        loadInstanceLevelFunctions( instance );
        
        // enumerate physical devices
        uint32_t numPhysDevices;
        enforceVK(vkEnumeratePhysicalDevices(instance, &numPhysDevices, null));
        if (numPhysDevices == 0) {
            stderr.writeln("No physical devices available.");
            return;
        }
        
        writeln;
        writeln("Found ", numPhysDevices, " physical device(s)\n==========================");
        writeln;
        
        // acquire physical devices
        auto physDevices = new VkPhysicalDevice[](numPhysDevices);
        vkEnumeratePhysicalDevices(instance, &numPhysDevices, physDevices.ptr).enforceVK;
        
        // print information about physical devices
        foreach(i, physDevice; physDevices) {
            VkPhysicalDeviceProperties properties;
            vkGetPhysicalDeviceProperties(physDevice, &properties);
            writeln("Physical device ", i, ": ", properties.deviceName.ptr.fromStringz);
            writeln("API Version: ", VK_VERSION_MAJOR(properties.apiVersion), ".", VK_VERSION_MINOR(properties.apiVersion), ".", VK_VERSION_PATCH(properties.apiVersion));
            writeln("Driver Version: ", properties.driverVersion);
            writeln("Device type: ", properties.deviceType);
            writeln;
        }

        // for simplicity the first found physical device will be used

        // enumerate queues of first physical device
        uint32_t numQueues;
        vkGetPhysicalDeviceQueueFamilyProperties(physDevices[0], &numQueues, null);
        assert(numQueues >= 1);

        auto queueFamilyProperties = new VkQueueFamilyProperties[](numQueues);
        vkGetPhysicalDeviceQueueFamilyProperties(physDevices[0], &numQueues, queueFamilyProperties.ptr);
        assert(numQueues >= 1);	// numQueues can be different than the first time

        // find print information about queue families and find graphics queue family index
        uint32_t graphicsQueueFamilyIndex = uint32_t.max;
        foreach(i, const ref properties; queueFamilyProperties) {
            writeln("Queue Family ", i);
            writeln("\tQueues in Family         : ", properties.queueCount);
            writeln("\tQueue timestampValidBits : ", properties.timestampValidBits);

            if (properties.queueFlags & VK_QUEUE_GRAPHICS_BIT) {
                writeln("\tVK_QUEUE_GRAPHICS_BIT");
                if (graphicsQueueFamilyIndex == uint32_t.max) {
                    graphicsQueueFamilyIndex = cast( uint32_t )i;
                }
            }

            if (properties.queueFlags & VK_QUEUE_COMPUTE_BIT)
                writeln("\tVK_QUEUE_COMPUTE_BIT");

            if (properties.queueFlags & VK_QUEUE_TRANSFER_BIT)
                writeln("\tVK_QUEUE_TRANSFER_BIT");

            if (properties.queueFlags & VK_QUEUE_SPARSE_BINDING_BIT)
                writeln("\tVK_QUEUE_SPARSE_BINDING_BIT");

            writeln;
        }

        // if no graphics queue family was found use the first available queue family
        if (graphicsQueueFamilyIndex == uint32_t.max)  {
            writeln("VK_QUEUE_GRAPHICS_BIT not found. Using queue family index 0");
            graphicsQueueFamilyIndex = 0;
        } else {
            writeln("VK_QUEUE_GRAPHICS_BIT found at queue family index ", graphicsQueueFamilyIndex);
        }

        writeln;

        // prepare VkDeviceQueueCreateInfo for logical device creation
        float[1] queuePriorities = [ 1.0f ];
        VkDeviceQueueCreateInfo queueCreateInfo = {
            queueCount			: 1,
            pQueuePriorities 	: queuePriorities.ptr,
            queueFamilyIndex	: graphicsQueueFamilyIndex,
        };

        // prepare logical device creation
        VkDeviceCreateInfo deviceCreateInfo = {
            queueCreateInfoCount	: 1,
            pQueueCreateInfos		: &queueCreateInfo,
        };

        // create the logical device
        VkDevice device;
        enforceVK(vkCreateDevice(physDevices[0], &deviceCreateInfo, null, &device));
        writeln("Logical device created");

        // destroy the device at scope exist
        scope(exit) {
            writeln( "Scope exit: draining work and destroying logical device");
            if( device != VK_NULL_HANDLE ) {
                vkDeviceWaitIdle(device);
                vkDestroyDevice(device, null);
            }
        }

        // load all Vulkan functions for the device
        loadDeviceLevelFunctions(device);

        // alternatively load all Vulkan functions for all devices
        //EruptedLoader.loadDeviceLevelFunctions(instance);

        // get the graphics queue to submit command buffers
        VkQueue queue;
        vkGetDeviceQueue(device, graphicsQueueFamilyIndex, 0, &queue);
        writeln("Graphics queue retrieved");

        // produce some mind-blowing visuals
        //...

        while( !glfwWindowShouldClose( window )) {
            glfwSwapBuffers(window);
            glfwPollEvents();
        }

        writeln;
    }*/
}
/*private void enforceVK(VkResult res) {
	enforce(res == VkResult.VK_SUCCESS, res.to!string);
}
private extern (C) void keyCallback (GLFWwindow* window, int key, int, int action, int) nothrow @nogc
{
    if (key == GLFW_KEY_ESCAPE && action == GLFW_PRESS)
    {
        glfwSetWindowShouldClose (window, GLFW_TRUE);
    }
}*/

void main()
{
    auto engine = Engine();
    engine.initialise();
    engine.run();
}