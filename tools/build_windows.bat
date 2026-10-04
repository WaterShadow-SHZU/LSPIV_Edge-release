@echo off
REM ===========================================================================
REM  build_windows.bat -- Rebuild the patched LSPIV solver for Windows (x86-64)
REM
REM  Produces into bin\rebuild\:
REM     PIV.exe  transf_a.exe  ortho_plan.exe  vel_transf.exe
REM     filter.exe  vel_scal.exe
REM
REM  Requirements:
REM     1. MSYS2 installed, default location C:\msys64
REM     2. In the MSYS2 UCRT64 shell, run:  pacman -S mingw-w64-ucrt-x86_64-gcc-fortran make
REM        (that package provides gfortran 16.x; the exact version does not matter)
REM
REM  If MSYS2 lives elsewhere, set MSYS2_ROOT before running:
REM     set MSYS2_ROOT=D:\msys64
REM
REM  Usage:  double-click, or run from cmd:   tools\build_windows.bat
REM ===========================================================================
setlocal
cd /d "%~dp0.."

if not defined MSYS2_ROOT set "MSYS2_ROOT=C:\msys64"
set "FC=%MSYS2_ROOT%\ucrt64\bin\gfortran.exe"

if not exist "%FC%" (
  echo.
  echo [ERROR] gfortran not found at: %FC%
  echo         Install MSYS2, then in the UCRT64 shell run:
  echo             pacman -S mingw-w64-ucrt-x86_64-gcc-fortran make
  echo         Or point MSYS2_ROOT at your install, e.g.  set MSYS2_ROOT=D:\msys64
  echo.
  pause
  exit /b 1
)

set "SRC=%~dp0solver-patches"
set "OUT=%~dp0..\bin\rebuild"
set "LOG=%~dp0build_windows.log"

if not exist "%OUT%" mkdir "%OUT%"
if exist "%LOG%" del "%LOG%"

REM The two files below must be compiled BEFORE the others (module definitions).
set "UTILS=errors.f90 sub_lspiv_parameter.f90"

REM -cpp        : allow C-style preprocessing (the sources use #ifdef openmp)
REM -Dopenmp    : enable the OpenMP code paths
REM -fopenmp    : link the OpenMP runtime
REM -O3         : optimisation
REM -fimplicit-none : reject undeclared variables (catches typos)
REM -static     : no external DLL dependency for the Fortran runtime
REM -no-pie     : simplify the linked binary layout on Windows
set "FLAGS=-cpp -Dopenmp -fopenmp -O3 -fimplicit-none -static -no-pie"

cd /d "%SRC%"

echo === PIV.exe === >> "%LOG%"
"%FC%" %FLAGS% %UTILS% sub_PIV.f90 PIV.f90 -o "%OUT%\PIV.exe" >> "%LOG%" 2>&1
if errorlevel 1 echo FAILED PIV.exe >> "%LOG%"

echo === transf_a.exe === >> "%LOG%"
"%FC%" %FLAGS% %UTILS% sub_transf_23D.f90 transf_23D.f90 -o "%OUT%\transf_a.exe" >> "%LOG%" 2>&1
if errorlevel 1 echo FAILED transf_a.exe >> "%LOG%"

echo === vel_transf.exe === >> "%LOG%"
"%FC%" %FLAGS% %UTILS% sub_vel_transf.f90 vel_transf.f90 -o "%OUT%\vel_transf.exe" >> "%LOG%" 2>&1
if errorlevel 1 echo FAILED vel_transf.exe >> "%LOG%"

echo === filter.exe === >> "%LOG%"
"%FC%" %FLAGS% %UTILS% kdtree2.f90 sub_filter.f90 filter.f90 -o "%OUT%\filter.exe" >> "%LOG%" 2>&1
if errorlevel 1 echo FAILED filter.exe >> "%LOG%"

echo === vel_scal.exe === >> "%LOG%"
"%FC%" %FLAGS% %UTILS% sub_vel_scal.f90 vel_scal.f90 -o "%OUT%\vel_scal.exe" >> "%LOG%" 2>&1
if errorlevel 1 echo FAILED vel_scal.exe >> "%LOG%"

echo === ortho_plan.exe === >> "%LOG%"
"%FC%" %FLAGS% %UTILS% sub_ortho_plan_23D.f90 ortho_plan_23D.f90 -o "%OUT%\ortho_plan.exe" >> "%LOG%" 2>&1
if errorlevel 1 echo FAILED ortho_plan.exe >> "%LOG%"

echo BUILD DONE >> "%LOG%"
dir /b "%OUT%" >> "%LOG%"

echo.
echo Build log: %LOG%
echo Output   : %OUT%
echo.
echo To use the freshly built binaries, copy the 6 .exe from bin\rebuild\
echo over the same-named files in bin\windows\.
echo.
pause
endlocal
