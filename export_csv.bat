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
cd /d "%~dp0"
set "RUN=%~1"
if defined RUN (
  py -3 export_results.py "%RUN%"
) else (
  py -3 export_results.py
)
pause
