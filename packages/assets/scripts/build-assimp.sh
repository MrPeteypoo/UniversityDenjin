#!/bin/bash

# Unfortunately dub doesn't always run the script from the correct working directory, as such we need to cd to the
# current script directory and return to the previous upon exit.
currentDir=`pwd`
shDir="${0%/*}/"
shFileName="${0##*/}"

arch="$DUB_ARCH"
folder="linux-$arch"
assimp="$shDir/../../../external/assimp"
output="content/$folder"
outputFile="$output/libassimp.so.3"
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
    extraCMakeFlags='-DCMAKE_C_FLAGS=-m32 -DCMAKE_CXX_FLAGS=-m32 -DCMAKE_SHARED_LINKER_FLAGS=-m32'
elif [ "$arch" != "x86_64" ]; then
    echo "Invalid Arch paramter given: $arch."
    exit_script
fi;

if [ ! -e "$assimp/CMakeLists.txt" ]; then
    echo "Couldn't find external/assimp/CMakeLists.txt, assimp will not be built."
    exit 0
fi;

echo ""
echo "================================="
echo "Starting $shFileName..."
echo "================================="
echo ""

mkdir -p $output
mkdir -p $shDir../$output
mkdir -p .temp/$folder/assimp
cd .temp/$folder/assimp

echo "Running CMake on assimp..."
cmake $assimp -DBUILD_SHARED_LIBS=ON -DBUILD_TESTING=OFF -DASSIMP_BUILD_TESTS=OFF -DCMAKE_BUILD_TYPE=Release $extraCMakeFlags > /dev/null

echo "Attempting to build assimp..."
cmake --build . > /dev/null

echo "Copying libassimp.so.3 for $folder..."
cp -u code/libassimp.so.3 ../../../$output > /dev/null
cp -u code/libassimp.so.3 "$shDir../$output" > /dev/null

exit_script
