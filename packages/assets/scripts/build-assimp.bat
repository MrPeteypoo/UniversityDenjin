@echo off
REM Unfortunately dub doesn't always run the script from the correct directory. As a result we have to cd to the
REM directory storing the batch file.
set currentDir=%cd%
set batchDir=%~dp0
set batchFileName=%~n0

set arch=%DUB_ARCH%
set folder=win-%arch%
set assimp=%batchDir%..\..\..\external\assimp
set output=content\%folder%
set outputFile=%output%\assimp.dll
set generator=""

if exist %currentDir%\%outputFile% (
    exit 0
)

if %arch% == x86 (
    set generator="Visual Studio 14 2015"
) else if %arch% == x86_64 (
    set generator="Visual Studio 14 2015 Win64"
) else (
    echo:Incorrect Arch parameter given: %arch%.
    call :exit_script
)

REM cd %batchDir%

if not exist %assimp%\CMakeLists.txt (
    echo:Couldn't find external\assimp\CMakeLists.txt, Assimp will not be built.
    echo:%assimp%
    exit 0
)

echo: 
echo:=================================
echo:Starting %batchFileName%...
echo:=================================
echo: 

if not exist .temp\ mkdir .temp
if not exist .temp\%folder% mkdir .temp\%folder%
if not exist .temp\%folder%\assimp mkdir .temp\%folder%\assimp
if not exist %output% mkdir %output%
if not exist %batchDir%..\%output% mkdir %batchDir%..\%output%

cd .temp\%folder%\assimp

echo:Running CMake on Assimp with generator: %generator%...
cmake %assimp% -DBUILD_SHARED_LIBS=ON -DBUILD_TESTING=OFF -DASSIMP_BUILD_TESTS=OFF -G %generator% 1> nul

echo:Attempting to build Assimp...
cmake --build . --config Release 1> nul

echo:Copying assimp.dll for %folder%...
xcopy /y /i code\Release\assimp-vc140-mt.dll ..\..\..\%output% > nul
ren ..\..\..\%output%\assimp-vc140-mt.dll assimp.dll > nul
xcopy /y /i code\Release\assimp-vc140-mt.dll %batchDir%..\%output% > nul
ren %batchDir%..\%output%\assimp-vc140-mt.dll assimp.dll > nul
call :exit_script

REM Ensure we go back to the previous directory.
:exit_script
cd %currentDir%
echo: 
echo:=================================
echo:Exiting %batchFileName%...
echo:=================================
echo: 
exit 0