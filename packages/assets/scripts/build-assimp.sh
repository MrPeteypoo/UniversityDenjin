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
    extraCMakeFlags='-DCMAKE_C_FLAGS=-m32 -DCMAKE_CXX_FLAGS=-m32 -DCMAKE_SHARED_LINKER_FLAGS=-m32
                     -DASSIMP_BUILD_3DS_IMPORTER=OFF -DASSIMP_BUILD_3D_IMPORTER=OFF -DASSIMP_BUILD_3MF_IMPORTER=OFF
                     -DASSIMP_BUILD_AC_IMPORTER=OFF -DASSIMP_BUILD_ASE_IMPORTER=OFF -DASSIMP_BUILD_B3D_IMPORTER=OFF
                     -DASSIMP_BUILD_BLEND_IMPORTER=OFF -DASSIMP_BUILD_BVH_IMPORTER=OFF -DASSIMP_BUILD_COB_IMPORTER=OFF
                     -DASSIMP_BUILD_CSM_IMPORTER=OFF -DASSIMP_BUILD_DXF_IMPORTER=OFF -DASSIMP_BUILD_FBX_IMPORTER=OFF
                     -DASSIMP_BUILD_GLTF_IMPORTER=OFF -DASSIMP_BUILD_HMP_IMPORTER=OFF -DASSIMP_BUILD_IFC_IMPORTER=OFF 
                     -DASSIMP_BUILD_IRRMESH_IMPORTER=OFF -DASSIMP_BUILD_IRR_IMPORTER=OFF -DASSIMP_BUILD_LWO_IMPORTER=OFF 
                     -DASSIMP_BUILD_LWS_IMPORTER=OFF -DASSIMP_BUILD_MD2_IMPORTER=OFF -DASSIMP_BUILD_MD3_IMPORTER=OFF 
                     -DASSIMP_BUILD_MD5_IMPORTER=OFF -DASSIMP_BUILD_MDC_IMPORTER=OFF -DASSIMP_BUILD_MDL_IMPORTER=OFF
                     -DASSIMP_BUILD_MS3D_IMPORTER=OFF -DASSIMP_BUILD_NDO_IMPORTER=OFF -DASSIMP_BUILD_NFF_IMPORTER=OFF 
                     -DASSIMP_BUILD_OBJ_IMPORTER=OFF -DASSIMP_BUILD_OFF_IMPORTER=OFF -DASSIMP_BUILD_OGRE_IMPORTER=OFF 
                     -DASSIMP_BUILD_PLY_IMPORTER=OFF -DASSIMP_BUILD_Q3D_IMPORTER=OFF -DASSIMP_BUILD_Q3BSP_IMPORTER=OFF
                     -DASSIMP_BUILD_RAW_IMPORTER=OFF -DASSIMP_BUILD_SIB_IMPORTER=OFF -DASSIMP_BUILD_SMD_IMPORTER=OFF
                     -DASSIMP_BUILD_STL_IMPORTER=OFF -DASSIMP_BUILD_TERRAGEN_IMPORTER=OFF -DASSIMP_BUILD_XGL_IMPORTER=OFF 
                     -DASSIMP_BUILD_X_IMPORTER=OFF -DASSIMP_BUILD_OPENGEX_IMPORTER=OFF -DASSIMP_BUILD_ASSBIN_IMPORTER=OFF
                     -DASSIMP_BUILD_ASSXML_IMPORTER=OFF'
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
cmake $assimp -DBUILD_SHARED_LIBS=ON -DBUILD_TESTING=OFF -DCMAKE_BUILD_TYPE=Release $extraCMakeFlags > /dev/null

echo "Attempting to build assimp..."
cmake --build . > /dev/null

echo "Copying libassimp.so.3 for $folder..."
ls -lhr code
cp -u code/libassimp.so.3 ../../../$output > /dev/null
cp -u code/libassimp.so.3 "$shDir../$output" > /dev/null

exit_script
