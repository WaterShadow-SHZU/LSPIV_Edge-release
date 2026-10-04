#!/usr/bin/env bash
# =====================================================================
# build_arm.sh -- 在 ARM (aarch64 / armv7) 设备上构建 LSPIV 解算器
#
# 作用：把 tools/solver-patches 里**已修补**的解算器源码编成 `.x` 二进制，
#       集中放到一个输出目录，供 lspiv_batch.py --exes <目录> 使用。
#
# 用法（在树莓派 / 香橙派上，普通用户即可）：
#     bash tools/arm/build_arm.sh                     # 默认编 fudaa_linux 目标
#     bash tools/arm/build_arm.sh station             # 编 station 目标
#     bash tools/arm/build_arm.sh fudaa_linux ~/out   # 指定目标与输出目录
#
# 前提：sudo apt install -y gfortran make
#
# 重要：本脚本只编**已修补**的源码。源码里必须带着 P5 读图和 Bi 修复，
#       否则编出来的解算器读不了 lspiv_batch.py 默认生成的 P5 二进制图，
#       正射阶段会以 transf_a exit=24 全线失败。编译前会校验补丁标记，
#       缺失就直接中止，不让板子跑到一半才炸。
# =====================================================================
set -euo pipefail

TARGET="${1:-fudaa_linux}"
OUTDIR="${2:-$(cd "$(dirname "$0")" && pwd)/exes_arm}"

# ---- 定位源码目录（允许脚本从任意位置调用）---------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CANDIDATES=(
    "$SCRIPT_DIR/../solver-patches"                       # 本仓库标准位置
    "$SCRIPT_DIR/solver-patches"
    "$SCRIPT_DIR/../velocimetry_solver-master/sources"    # 兼容上游源码树
    "$SCRIPT_DIR/../../velocimetry_solver-master/sources"
    "$SCRIPT_DIR/sources"
    "$HOME/velocimetry_solver-master/sources"
)
SRCDIR=""
for c in "${CANDIDATES[@]}"; do
    if [ -f "$c/PIV.f90" ]; then SRCDIR="$(cd "$c" && pwd)"; break; fi
done
if [ -z "$SRCDIR" ]; then
    echo "ERROR: 找不到解算器源码目录（含 PIV.f90）。" >&2
    echo "       本仓库的源码在 tools/solver-patches/。" >&2
    echo "       请用第 2 个参数指定路径，或改本脚本的 CANDIDATES 列表。" >&2
    exit 1
fi

echo "==============================================================="
echo " LSPIV ARM 构建"
echo "---------------------------------------------------------------"
echo " 目标      : $TARGET"
echo " 源码目录  : $SRCDIR"
echo " 输出目录  : $OUTDIR"
echo " 宿主架构  : $(uname -m)"
echo "==============================================================="

# ---- 工具链检查 -------------------------------------------------------
if ! command -v gfortran >/dev/null 2>&1; then
    echo "ERROR: 找不到 gfortran。请先执行：" >&2
    echo "         sudo apt update && sudo apt install -y gfortran make" >&2
    exit 1
fi
if ! command -v make >/dev/null 2>&1; then
    echo "ERROR: 找不到 make。请安装： sudo apt install -y make" >&2
    exit 1
fi
echo "gfortran : $(gfortran --version | head -n1)"
echo "make     : $(make --version | head -n1)"
echo

# ---- 补丁校验 ---------------------------------------------------------
# 为什么必须有这一步：lspiv_batch.py 默认写 P5（二进制）图，而上游原版
# 解算器只认 P2（文本）图。曾经因为 ARM 侧编译的是未修补的上游源码，
# 板子上正射阶段 100% 失败（transf_a exit=24）。这里在编译之前就把
# 4 处关键补丁逐个验一遍，缺任何一处就退出。
echo ">>> 校验源码补丁（P5 读图 / Bi 修复）"
PATCH_FAIL=0
require_marker() {
    file="$1"; needle="$2"; desc="$3"
    if [ ! -f "$SRCDIR/$file" ]; then
        echo "    [X] 缺少源文件 $file（$desc）"
        PATCH_FAIL=1
    elif grep -qF -- "$needle" "$SRCDIR/$file"; then
        echo "    [OK] $file  --  $desc"
    else
        echo "    [X] $file 缺少补丁标记：$needle  （$desc）"
        PATCH_FAIL=1
    fi
}
require_marker "sub_PIV.f90"             "read_pgm_any"                       "P5 读图（PIV）"
require_marker "sub_transf_23D.f90"      "read_pgm_any_transf"                "P5 读图（transf_a）"
require_marker "transf_23D.f90"          "read_PGM_P2 => read_pgm_any_transf" "读图指针已切到新函数"
require_marker "sub_lspiv_parameter.f90" "action='readwrite'"                 "PIV_param.dat 可读写（Bi 自愈）"
if [ "$PATCH_FAIL" -ne 0 ]; then
    echo >&2
    echo "ERROR: 这份源码不是已修补版本，继续编译会产出读不了 P5 图的解算器。" >&2
    echo "       请使用本仓库 tools/solver-patches/ 里的源码。" >&2
    echo "       若确实要用上游原版，必须改跑 P2 模式（慢约 59 倍）：" >&2
    echo "         python3 lspiv_batch.py video ... --no-pgm-binary" >&2
    echo "         或 PGMBIN=0 bash process_video.sh ..." >&2
    exit 1
fi
echo

# ---- 准备构建树：复制源码 + 换上 ARM makefile -------------------------
# 复制到 build_arm/ 再构建：要在源码树里换掉 makefile，直接在原地做会
# 留下 *.mod / *.o / makefile.upstream.bak 这些构建垃圾。
# 注意：BUILDROOT 在 tools/arm/ 下，够上层 makefile 找到它的 ../exe_* 目录。
BUILDROOT="$SCRIPT_DIR/build_arm"
rm -rf "$BUILDROOT"
mkdir -p "$BUILDROOT"
cp -a "$SRCDIR/." "$BUILDROOT/"

# 备份上游 makefile，放入 ARM 版
if [ -f "$BUILDROOT/makefile" ]; then
    mv "$BUILDROOT/makefile" "$BUILDROOT/makefile.upstream.bak"
fi
cp "$SCRIPT_DIR/makefile" "$BUILDROOT/makefile"

# makefile 期望的 exe/lib 目录（EXEDIR=./../exe，相对 sources）
mkdir -p "$BUILDROOT/../exe_${TARGET}" "$BUILDROOT/../lib_${TARGET}"

# stab_img 是 cmake 产物，fudaa_linux / appli 目标会拷它；
# 没有就造个占位，免得 cp 失败中断构建。
if [ ! -f "$BUILDROOT/stab_img/src/exesurf" ]; then
    mkdir -p "$BUILDROOT/stab_img/src"
    printf '#!/bin/sh\necho "stab_img 未构建（需要 cmake），占位。" >&2\nexit 1\n' \
        > "$BUILDROOT/stab_img/src/exesurf"
    chmod +x "$BUILDROOT/stab_img/src/exesurf"
    echo "[提示] stab_img 缺失，已放占位脚本（本工具不用它）。"
fi

# ---- 构建 -------------------------------------------------------------
cd "$BUILDROOT"
echo
echo ">>> make $TARGET"
make "$TARGET" || {
    echo
    echo "构建失败。排查建议：" >&2
    echo "  1) 确认 gfortran 版本：gfortran --version（Debian 12/Ubuntu 24 是 12/13，够用）" >&2
    echo "  2) 单文件试编看真实报错：" >&2
    echo "     gfortran -cpp -Dopenmp -fopenmp -O3 -fimplicit-none -no-pie \\" >&2
    echo "       errors.f90 sub_lspiv_parameter.f90 sub_PIV.f90 PIV.f90 -o /tmp/PIV.x" >&2
    echo "  3) 若报 -march/-mcpu 相关错误，改用 make $TARGET ARCHFLAGS=''" >&2
    exit 1
}

# ---- 收集产物 ---------------------------------------------------------
mkdir -p "$OUTDIR"
FOUND=0
for d in "$BUILDROOT/../exe_${TARGET}" "$BUILDROOT/../lib_${TARGET}"; do
    [ -d "$d" ] || continue
    for f in "$d"/*; do
        [ -f "$f" ] || continue
        case "$(basename "$f")" in
            libgfortran.so.5|stab_image) continue ;;
        esac
        cp -f "$f" "$OUTDIR/"
        FOUND=$((FOUND+1))
    done
done
if [ -d "$BUILDROOT/../lib_${TARGET}" ]; then
    cp -f "$BUILDROOT/../lib_${TARGET}"/*.so "$OUTDIR/" 2>/dev/null || true
fi

echo
echo "==============================================================="
echo " 构建完成：$FOUND 个产物 -> $OUTDIR"
echo "---------------------------------------------------------------"
ls -1 "$OUTDIR" 2>/dev/null || true
echo "==============================================================="
echo
echo "下一步验证（先在板上跑 2 对，确认能出结果）："
echo "  python3 lspiv_batch.py piv --exes '$OUTDIR' --calib <校准> \\"
echo "      --img-transf <img_transf> --pairs 1:2"
echo
echo "确认无误后跑完整流水线："
echo "  python3 lspiv_batch.py video --exes '$OUTDIR' --video <视频> --calib <校准>"
echo
