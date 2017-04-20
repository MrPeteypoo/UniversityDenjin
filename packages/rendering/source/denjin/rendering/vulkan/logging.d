/**
    A collection of miscellaneous vulkan-related functionality.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: MIT
*/
module denjin.rendering.vulkan.logging;

// Phobos.
import std.conv     : to;
import std.stdio    : write, writeln;
import std.string   : fromStringz;
import std.traits   : isNumeric;

// Engine.
import denjin.rendering.vulkan.misc : vulkanVersionString;

// External.
import erupted.types : VkLayerProperties, VkPhysicalDeviceLimits, VkPhysicalDeviceProperties;

/// Iterates through a collection, printing the properties of each layer.
void logLayerProperties (Container) (auto ref Container layerProperties)
{
    foreach (ref layer; layerProperties)
    {
        static assert (is (typeof (layer) == VkLayerProperties));
        writeln ("Supported Layer: ");
        writeln ("\t", "Layer Name: ", layer.layerName.ptr.fromStringz);
        writeln ("\t", "Spec Version: ", layer.specVersion.vulkanVersionString);
        writeln ("\t", "Implementation Version: ", layer.implementationVersion.vulkanVersionString);
        writeln ("\t", "Layer Description: ", layer.description.ptr.fromStringz);
        writeln;
    }
}

/// Iterates through a collection, printing the properties of each physical device.
void logPhysicalDeviceProperties (Container) (auto ref Container physicalDevicesProperties)
{
    foreach (ref device; physicalDevicesProperties)
    {
        static assert (is (typeof (device) == VkPhysicalDeviceProperties));
        writeln ("Vulkan Device:");
        writeln ("\t", "API Version: ", device.apiVersion.vulkanVersionString);
        writeln ("\t", "Driver Version: ", device.driverVersion.vulkanVersionString);
        writeln ("\t", "Vendor ID: ", device.vendorID);
        writeln ("\t", "Device ID: ", device.deviceID);
        writeln ("\t", "Device Type: ", device.deviceType.to!string);
        writeln ("\t", "Device Name: ", device.deviceName.ptr.fromStringz);
        write ("\t", "Pipeline Cache UUID: ");
        foreach (i; device.pipelineCacheUUID)
        {
            write (i);
        }
        write("\n");

        writeln ("\t", "Limits:");
        foreach (member; __traits (allMembers, VkPhysicalDeviceLimits))
        {
            alias Type = typeof (__traits (getMember, device.limits, member));
            static if (isNumeric!Type)
            {
                const auto value = mixin ("device.limits." ~ member);
                writeln ("\t\t", member, ": ", value);
            }
        }
        writeln;
    }
}