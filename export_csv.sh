#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 LSPIV_Edge contributors
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
# =====================================================================
# export_csv.sh -- 把一次运行结果导出成 CSV
#                  （等价于 export_csv.bat）
#
# 用法：
#   bash export_csv.sh                # 交互/自动选最新一次运行
#   bash export_csv.sh runs/xxx       # 指定某次运行目录
# =====================================================================
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# 同 process_video.sh：Windows 的 Git Bash 会把 pwd 报成 /c/... 形式。
if (pwd -W >/dev/null 2>&1); then
    HERE="$(cd "$(dirname "$0")" && pwd -W)"
fi

RUN="${1:-}"
# export_results.py 把 runs/ 当作**相对当前目录**解析，所以先切到仓库根目录；
# 用户给的运行目录则先转成绝对路径，免得 cd 之后失效。
if [ -n "$RUN" ]; then
    case "$RUN" in
        /*) ;;
        *)  RUN="$PWD/$RUN" ;;
    esac
fi
cd "$HERE"

if [ -n "$RUN" ]; then
    python3 "$HERE/export_results.py" "$RUN"
else
    python3 "$HERE/export_results.py"
fi
