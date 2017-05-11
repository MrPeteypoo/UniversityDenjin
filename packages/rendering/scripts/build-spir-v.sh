#!/bin/bash
# Check to see if we can even compile the shaders.
hash glslangValidator 2>/dev/null || exit 0

# Unfortunately dub doesn't always run the script from the correct working directory, as such we need to cd to the
# current script directory and return to the previous upon exit.
currentDir=`pwd`
shDir="${0%/*}/"
shFileName="${0##*/}"
output="$currentDir/content/all/shaders/"
shaderDir="$shDir/../shaders/"

shaderNames[0]="testVert.spv"
shaderFiles[0]="test.vert"
shaderNames[1]="testFrag.spv"
shaderFiles[1]="test.frag"
shaderNames[2]="geometry.spv"
shaderFiles[2]="geometry.vert"
shaderNames[3]="forward.spv"
shaderFiles[3]="forward.frag"

cd $shaderDir
mkdir -p $output

length=${#shaderNames[@]}
for (( i=0; i < ${length}; i++ )); do
    name="${shaderNames[$i]}"
    outName="$output$name"
    if [ ! -e $outName ]; then
        echo "Compiling shader: $name"
        glslangValidator -H -t -o $outName ${shaderFiles[$i]} > "$outName.log"
    fi;
done
cd $currentDir