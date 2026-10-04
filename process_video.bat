@echo off
setlocal
cd /d "%~dp0"
set "VIDEO=%~1"
if not defined VIDEO set /p "VIDEO=Drag a video onto this window and press Enter, or type the video path: "
if not defined VIDEO (
  echo Usage: drag a video onto process_video.bat, or run: process_video.bat video.mp4
  pause
  exit /b 1
)
set "VIDEO=%VIDEO:"=%"
echo Processing: %VIDEO%
py -3 lspiv_batch.py "%VIDEO%"
echo.
if errorlevel 1 (echo FAILED. Check the tmp folder under runs.) else (echo Done. See the new folder under runs.)
pause
endlocal
