@echo off
cd /d "%~dp0"
set "RUN=%~1"
if defined RUN (
  py -3 export_results.py "%RUN%"
) else (
  py -3 export_results.py
)
pause
