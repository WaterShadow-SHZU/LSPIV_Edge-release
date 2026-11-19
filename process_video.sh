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
# process_video.sh -- LSPIV_Edge 一键跑完整视频流水线
#                     （等价于 process_video.bat，但更明确一点）
#
# 流水线：视频 -> 抽帧 -> PNG 转 PGM(P5) -> 正射 -> 互相关 -> 导出 CSV
#
# 用法：
#   bash process_video.sh <视频文件> [校准目录] [-- <额外参数>]
#
# 例：
#   bash process_video.sh flow.mp4
#   bash process_video.sh flow.mp4 ./calib
#   bash process_video.sh flow.mp4 ./calib -- --every 5      # 每 5 帧取 1 帧
#   bash process_video.sh flow.mp4 ./calib -- --no-pgm-binary  # 退回 P2 文本
#
# 环境变量（可选）：
#   EXES    解算器目录      默认自动探测 tools/arm/exes_arm → exes → bin/windows
#   OUT     结果目录        默认交给 lspiv_batch.py 自动命名
#   WORKERS 并发进程数      默认由脚本/配置决定
#   PGMBIN  1=用 P5(默认)   0=用 P2 文本
# =====================================================================
set -euo pipefail

if [ $# -lt 1 ]; then
    echo "用法: bash process_video.sh <视频文件> [校准目录] [-- 额外参数...]" >&2
    echo "例:   bash process_video.sh flow.mp4 ./calib" >&2
    exit 2
fi

HERE="$(cd "$(dirname "$0")" && pwd)"
# Windows 上的 Git Bash 会把 pwd 报成 /c/... 形式，原生 python 会当成
# C:\c\... 从而找不到脚本。有 pwd -W 就换成 C:/... 形式。
# Linux / macOS 上 pwd -W 不存在，这里自动跳过，不影响板子。
if (pwd -W >/dev/null 2>&1); then
    HERE="$(cd "$(dirname "$0")" && pwd -W)"
fi

# 把路径转成绝对路径。下面会 cd 到仓库根目录，不转的话
# "flow.mp4" / "./calib" 这类相对路径会失效。
abspath() {
    case "$1" in
        /*) printf '%s\n' "$1" ;;
        *)  printf '%s\n' "$PWD/$1" ;;
    esac
}

VIDEO="$(abspath "$1")"; shift
CALIB="${HERE}/calib"
if [ $# -gt 0 ] && [ "$1" != "--" ]; then CALIB="$(abspath "$1")"; shift; fi
[ "${1:-}" = "--" ] && shift

# 解算器目录：按平台探测。仓库里同时存在 bin/windows/*.exe 与
# tools/arm/exes_arm/*.x，但 .exe 在 Linux/ARM 上跑不了，所以要挑
# 与本机后缀一致的那份，不能只看目录存不存在。
if [ -z "${EXES:-}" ]; then
    case "$(uname -s)" in
        Linux|Darwin) NATIVE=".x";   ORDER=("$HERE/tools/arm/exes_arm" "$HERE/exes" "$HERE/bin/windows") ;;
        *)            NATIVE=".exe"; ORDER=("$HERE/bin/windows" "$HERE/tools/arm/exes_arm" "$HERE/exes") ;;
    esac
    for c in "${ORDER[@]}"; do
        [ -f "$c/PIV$NATIVE" ] && { EXES="$c"; break; }
    done
    EXES="${EXES:-$HERE/tools/arm/exes_arm}"
else
    EXES="$(abspath "$EXES")"
fi
PGMBIN="${PGMBIN:-1}"

[ -f "$VIDEO" ] || { echo "ERROR: 找不到视频 $VIDEO" >&2; exit 1; }
[ -d "$EXES" ]  || { echo "ERROR: 找不到解算器目录 $EXES" >&2
                     echo "       先构建： bash tools/arm/build_arm.sh" >&2; exit 1; }
[ -d "$CALIB" ] || { echo "ERROR: 找不到校准目录 $CALIB" >&2; exit 1; }

# 统一在仓库根目录下跑：结果目录 runs/ 是相对**当前目录**解析的，
# 不 cd 的话从别处调用会把结果散落到那个目录去。
cd "$HERE"

ARGS=(video "$VIDEO" --exes "$EXES" --calib "$CALIB")
[ "$PGMBIN" = "0" ] && ARGS+=(--no-pgm-binary)
[ -n "${OUT:-}" ]     && ARGS+=(--out "$OUT")
[ -n "${WORKERS:-}" ] && ARGS+=(--workers "$WORKERS")
ARGS+=("$@")   # 追加用户自定义参数

echo "==============================================================="
echo " LSPIV_Edge 视频流水线"
echo "---------------------------------------------------------------"
echo " 视频      : $VIDEO"
echo " 校准      : $CALIB"
echo " 解算器    : $EXES"
echo " PGM 格式  : $([ "$PGMBIN" = "0" ] && echo 'P2 文本' || echo 'P5 二进制（推荐）')"
echo "==============================================================="
echo

python3 "$HERE/lspiv_batch.py" "${ARGS[@]}"

echo
echo ">>> 导出 CSV（针对最新一次运行）"
python3 "$HERE/export_results.py" || true

echo
echo "完成。结果在 runs/ 下的最新目录。"
echo "  如需指定某次运行导出： python3 export_results.py runs/<目录名>"
