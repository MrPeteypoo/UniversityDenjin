@echo off
REM Unfortunately dub doesn't always run the script from the correct directory. As a result we have to cd to the
REM directory storing the batch file.
set currentDir=%cd%
set batchDir=%~dp0
cd %batchDir%

set batchFileName=%~n0
set arch=%1
set folder=win%arch%
set glfw=..\external\glfw
set output=..\content\%folder%
set generator=""

echo: 
echo:=================================
echo:Starting %batchFileName%...
echo:=================================
echo: 

if %arch% == 32 (
    set generator="Visual Studio 14 2015"
) else if %arch% == 64 (
    set generator="Visual Studio 14 2015 Win64"
) else (
    echo:Incorrect Arch parameter given: %arch%
    cd %currentDir%
    exit /B 0
)

if not exist ..\temp mkdir ..\temp
if not exist ..\temp\%folder% mkdir ..\temp\%folder%
if not exist %output% mkdir %output%

cd ..\temp\%folder%

echo:Running CMake on GLFW with generator: %generator%...
cmake ..\%glfw% -DBUILD_SHARED_LIBS=ON -DGLFW_BUILD_EXAMPLES=OFF -DGLFW_BUILD_TESTS=OFF -DGLFW_BUILD_DOCS=OFF -G %generator% > nul
echo: 

echo:Attempting to build GLFW...
cmake --build . --target glfw --config Release > null
echo: 

echo:Copying glfw3.dll for %folder%...
xcopy /Y src\Release\glfw3.dll ..\%output% > null

REM Ensure we go back to the previous directory.
cd %currentDir%

echo: 
echo:=================================
echo:%batchFileName% finished...
echo:=================================
echo: 