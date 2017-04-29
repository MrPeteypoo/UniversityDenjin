@echo off

REM Firstly we must check if we can even compile the shaders.
where /q glslangValidator.exe
if errorlevel 1 (
    exit 0
)

REM We are able to compile shaders, loop through shader module name/file pairs and build those that don't exist.
REM Unfortunately dub doesn't always run the script from the correct directory. As a result we have to cd to the
REM directory storing the batch file.
setlocal enabledelayedexpansion 
set currentDir=%cd%
set batchDir=%~dp0
set batchFileName=%~n0
set output=%currentDir%\content\all\shaders\
set shaderDir=%batchDir%..\shaders\

set shaders[0].Name=testVert.spv
set shaders[0].Files=test.vert
set shaders[1].Name=testFrag.spv
set shaders[1].Files=test.frag
set lastIndex=1

if not exist %output% mkdir %output%
cd %shaderDir%
for /l %%n in (0, 1, %lastIndex%) do (
    if not exist %output%!shaders[%%n].Name! (
        echo:Compiling shader: !shaders[%%n].Name!
        glslangValidator -H -t -o %output%!shaders[%%n].Name! !shaders[%%n].Files! > %output%!shaders[%%n].Name!.log
    )
)

cd %currentDir%