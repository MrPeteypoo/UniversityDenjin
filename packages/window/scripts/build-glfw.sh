#!/bin/bash

# Unfortunately dub doesn't always run the script from the correct working directory, as such we need to cd to the
# current script directory and return to the previous upon exit.
currentDir=`pwd`
shDir="${0%/*}/"
shFileName="${0##*/}"

arch="$DUB_ARCH"
folder="linux-$arch"
glfw="$shDir/../../../external/glfw"
output="content/$folder"
outputFile="$output/libglfw3.so"
extraCMakeFlags=""

if [ -e "$currentDir/$outputFile" ]; then
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

#cd $shDir

if [ "$arch" == "x86" ]; then
    extraCMakeFlags="-DCMAKE_C_COMPILER_ARG1=-m32"
elif [ "$arch" != "x86_64" ]; then
    echo "Invalid Arch paramter given: $arch."
    exit_script
fi;

if [ ! -e "$glfw/CMakeLists.txt" ]; then
    echo "Couldn't find external/glfw/CMakeLists.txt, GLFW will not be built."
    exit 0
fi;

echo ""
echo "================================="
echo "Starting $shFileName..."
echo "================================="
echo ""

mkdir -p $output
mkdir -p $shDir../$output
mkdir -p .temp/$folder
cd .temp/$folder

echo "Running CMake on GLFW..."
cmake $glfw -DBUILD_SHARED_LIBS=ON -DGLFW_BUILD_EXAMPLES=OFF -DGLFW_BUILD_TESTS=OFF -DGLFW_BUILD_DOCS=OFF -DCMAKE_BUILD_TYPE=Release $extraCMakeFlags > /dev/null
echo ""

echo "Attempting to build GLFW..."
cmake --build . --target glfw > /dev/null
echo ""

echo "Copying libglfw.so for $folder..."
cp -u src/libglfw.so ../../$outputFile > /dev/null
cp -u src/libglfw.so "$shDir../$outputFile" > /dev/null

exit_script
