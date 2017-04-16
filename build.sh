#!/bin/bash

command="$1"
build="$2"
arch="$3"
compiler="$4"
buildFlag=""
archFlag=""
compilerFlag=""

if [ "$command" == "" ]; then
    command="build"
fi
if [ "$command" == "rebuild" ]; then
    command="build --force"
fi
if [ "$build" != "" ]; then
    buildFlag="--build=$build"
fi
if [ "$arch" != "" ]; then
    archFlag="--arch=$arch"
fi
if [ "$compiler" != "" ]; then
    compilerFlag="--compiler=$compiler"
fi

dub $command $buildFlag $archFlag $compilerFlag
dub $command denjin:maths $buildFlag $archFlag $compilerFlag
dub $command denjin:misc $buildFlag $archFlag $compilerFlag
dub $command denjin:renderer $buildFlag $archFlag $compilerFlag
dub $command denjin:window $buildFlag $archFlag $compilerFlag