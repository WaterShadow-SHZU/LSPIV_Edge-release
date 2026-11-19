@echo off
REM SPDX-License-Identifier: GPL-3.0-or-later
REM Copyright (C) 2026 LSPIV_Edge contributors
REM
REM This program is free software: you can redistribute it and/or modify
REM it under the terms of the GNU General Public License as published by
REM the Free Software Foundation, either version 3 of the License, or
REM (at your option) any later version.
REM
REM This program is distributed in the hope that it will be useful,
REM but WITHOUT ANY WARRANTY; without even the implied warranty of
REM MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
REM GNU General Public License for more details.
REM
REM You should have received a copy of the GNU General Public License
REM along with this program.  If not, see <https://www.gnu.org/licenses/>.
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
