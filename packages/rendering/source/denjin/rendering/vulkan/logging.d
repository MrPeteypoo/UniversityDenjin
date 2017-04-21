/**
    A collection of miscellaneous vulkan-related functionality.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: MIT
*/
module denjin.rendering.vulkan.logging;

// Phobos.
import std.conv         : to;
import std.exception    : enforce;
import std.stdio        : write, writeln;
import std.string       : fromStringz;
import std.traits       : isNumeric, Unqual;

// Engine.
import denjin.rendering.vulkan.misc : vulkanVersionString;

// External.
import erupted.types :  VkExtensionProperties, VkLayerProperties, VkPhysicalDeviceLimits, VkPhysicalDeviceProperties, 
                        VkQueueFamilyProperties, VK_QUEUE_COMPUTE_BIT, VK_QUEUE_GRAPHICS_BIT, 
                        VK_QUEUE_SPARSE_BINDING_BIT, VK_QUEUE_TRANSFER_BIT;

/// Iterates through a collection, printing the properties of each layer.
void logLayerProperties (Container) (in ref Container layerProperties)
{
    foreach (ref layer; layerProperties)
    {
        static assert (is (Unqual!(typeof (layer)) == VkLayerProperties));
        writeln ("Supported Layer: ");
        writeln ("\t", "Layer Name: ", layer.layerName.ptr.fromStringz);
        writeln ("\t", "Spec Version: ", layer.specVersion.vulkanVersionString);
        writeln ("\t", "Implementation Version: ", layer.implementationVersion.vulkanVersionString);
        writeln ("\t", "Layer Description: ", layer.description.ptr.fromStringz);
        writeln;
    }
}

/// Iterates through a collection, printing the properties of each extension.
/// Params: type = "Instance" or "Device"
void logExtensionProperties (Container) (string type, in ref Container extensionProperties)
{
    foreach (ref extension; extensionProperties)
    {
        static assert (is (Unqual!(typeof (extension)) == VkExtensionProperties));
        writeln ("Supported ", type, " Extension: ");
        writeln ("\t", "Extension Name: ", extension.extensionName.ptr.fromStringz);
        writeln ("\t", "Spec Version: ", extension.specVersion.vulkanVersionString);
        writeln;
    }
}

/// Iterates through a collection, printing the properties of each physical device.
void logPhysicalDeviceProperties(Container, Container2) 
                                (in ref Container physicalDevicesProperties, in ref Container2 devExtProps)
{
    enforce (physicalDevicesProperties.length == devExtProps.length);
    size_t i;
    foreach (ref device; physicalDevicesProperties)
    {
        static assert (is (Unqual!(typeof (device)) == VkPhysicalDeviceProperties));
        writeln ("Vulkan Device:");
        writeln ("\t", "API Version: ", device.apiVersion.vulkanVersionString);
        writeln ("\t", "Driver Version: ", device.driverVersion.vulkanVersionString);
        writeln ("\t", "Vendor ID: ", device.vendorID);
        writeln ("\t", "Device ID: ", device.deviceID);
        writeln ("\t", "Device Type: ", device.deviceType.to!string);
        writeln ("\t", "Device Name: ", device.deviceName.ptr.fromStringz);
        write ("\t", "Pipeline Cache UUID: ");
        foreach (num; device.pipelineCacheUUID)
        {
            write (num);
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
        logExtensionProperties ("Device", devExtProps[i]);
        ++i;
    }
}

/// Iterates through a collection, printing the properties of each queue family.
void logQueueFamilyProperties (Container) (in ref Container queueFamilyProperties)
{
    foreach (ref queueFamily; queueFamilyProperties)
    {
        static assert (is (Unqual!(typeof (queueFamily)) == VkQueueFamilyProperties));
        writeln ("Queue Family: ");
        writeln ("\t", "Supports Graphics: ", (queueFamily.queueFlags & VK_QUEUE_GRAPHICS_BIT) > 0);
        writeln ("\t", "Supports Compute: ", (queueFamily.queueFlags & VK_QUEUE_COMPUTE_BIT) > 0);
        writeln ("\t", "Supports Transfer: ", (queueFamily.queueFlags & VK_QUEUE_TRANSFER_BIT) > 0);
        writeln ("\t", "Supports Sparse Binding: ", (queueFamily.queueFlags & VK_QUEUE_SPARSE_BINDING_BIT) > 0);
        writeln ("\t", "Queue Count: ", queueFamily.queueCount);
        writeln ("\t", "Timestamp Valid Bits: ", queueFamily.timestampValidBits);
        writeln ("\t", "Min Image Transfer Granularity: ", "(", queueFamily.minImageTransferGranularity.width, ", ",
            queueFamily.minImageTransferGranularity.height, ", ",
            queueFamily.minImageTransferGranularity.depth, ")");
        writeln;
    }
}