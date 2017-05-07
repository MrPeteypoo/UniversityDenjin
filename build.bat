@echo off
set command=%1
set build=%2
set arch=%3
set compiler=%4
set buildFlag=
set archFlag=
set compilerFlag=

if "%command%" == "" (
    set command=build
)
if "%command%" == "rebuild" (
    set command=build --force
)
if not "%build%" == "" (
    set buildFlag="--build=%build%"
)
if not "%arch%" == "" (
    set archFlag="--arch=%arch%"
)
if not "%compiler%" == "" (
    set compilerFlag="--compiler=%compiler%"
)

dub %command% %buildFlag% %archFlag% %compilerFlag% --quiet || exit /b 1
dub %command% denjin:assets %buildFlag% %archFlag% %compilerFlag% --quiet || exit /b 1
dub %command% denjin:maths %buildFlag% %archFlag% %compilerFlag% --quiet || exit /b 1
dub %command% denjin:misc %buildFlag% %archFlag% %compilerFlag% --quiet || exit /b 1
dub %command% denjin:rendering %buildFlag% %archFlag% %compilerFlag% --quiet || exit /b 1
dub %command% denjin:scene %buildFlag% %archFlag% %compilerFlag% --quiet || exit /b 1
dub %command% denjin:window %buildFlag% %archFlag% %compilerFlag% --quiet || exit /b 1
