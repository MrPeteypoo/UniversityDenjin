#!/bin/bash

# Unfortunately dub doesn't always run the script from the correct working directory, as such we need to cd to the
# current script directory and return to the previous upon exit.
currentDir=`pwd`
shDir="${0%/*}"
shFileName="${0##*/}"

arch="$1"
folder="linux-$arch"
glfw="../external/glfw"
output="../content/$folder"
outputFile="$output/libglfw3.so"
extraCMakeFlags=""

if [ -e "$shDir/$outputFile" ]; then
    exit 0
fi;

exit_script ()
{
    cd $currentDir
    echo ""
    echo "================================="
    echo "Exiting $shFileName..."
    echo "================================="
    echo "" 
    exit 0
}

echo ""
echo "================================="
echo "Starting $shFileName..."
echo "================================="
echo ""

cd $shDir

if [ "$arch" == "x86" ]; then
    extraCMakeFlags="-DCMAKE_C_COMPILER_ARG1=-m32"
elif [ "$arch" != "x86_64" ]; then
    echo "Invalid Arch paramter given: $arch."
    exit_script
fi;

if [ ! -e "$glfw/CMakeLists.txt" ]; then
    echo "Couldn't find external/glfw/CMakeLists.txt, makes sure you run 'git submodule update --init --recursive'"
    exit_script
fi;

mkdir -p $output
mkdir -p ../.temp/$folder
cd ../.temp/$folder

echo "Running CMake on GLFW..."
cmake ../$glfw -DBUILD_SHARED_LIBS=ON -DGLFW_BUILD_EXAMPLES=OFF -DGLFW_BUILD_TESTS=OFF -DGLFW_BUILD_DOCS=OFF -DCMAKE_BUILD_TYPE=Release $extraCMakeFlags > /dev/null
echo ""

echo "Attempting to build GLFW..."
cmake --build . --target glfw > /dev/null
echo ""

echo "Copying libglfw.so for $folder..."
cp src/libglfw.so ../$outputFile > /dev/null

exit_script