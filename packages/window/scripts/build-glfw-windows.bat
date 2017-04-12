@echo off
REM Unfortunately dub doesn't always run the script from the correct directory. As a result we have to cd to the
REM directory storing the batch file.
set currentDir=%cd%
set batchDir=%~dp0
set batchFileName=%~n0

set arch=%1
set folder=win-%arch%
set glfw=external\glfw
set output=content\%folder%
set outputFile=%output%%glfw3.dll%
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

echo: 
echo:=================================
echo:Starting %batchFileName%...
echo:=================================
echo: 

REM cd %batchDir%

if not exist %glfw%\CMakeLists.txt (
    echo:Couldn't find external\glfw\CMakeLists.txt, makes sure you run 'git submodule update --init --recursive'
    call :exit_script
)

if not exist .temp mkdir .temp
if not exist .temp\%folder% mkdir .temp\%folder%
if not exist %output% mkdir %output%

cd .temp\%folder%

echo:Running CMake on GLFW with generator: %generator%...
cmake ..\..\%glfw% -DBUILD_SHARED_LIBS=ON -DGLFW_BUILD_EXAMPLES=OFF -DGLFW_BUILD_TESTS=OFF -DGLFW_BUILD_DOCS=OFF -G %generator% > nul
echo: 

echo:Attempting to build GLFW...
cmake --build . --target glfw --config Release > null
echo: 

echo:Copying glfw3.dll for %folder%...
xcopy /Y src\Release\glfw3.dll ..\..\%output%\ > null
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