# ARM 部署说明（香橙派 / 树莓派）

本文介绍如何在 ARM 板上构建解算器并处理视频。仓库已包含补丁源码、ARM makefile 和构建脚本。

---

## 0. 决策与前提

| 项目 | 取值 | 说明 |
|---|---|---|
| **构建方式** | **在目标板上原生编译** | 不需要交叉工具链；板子联网 `apt install` 即可 |
| **参考硬件** | Orange Pi 4 Pro（Allwinner A733） | 2×A76 + 6×A55；`--workers` 从 2 起步实测 |
| **GUI** | **不装** | 板上只做边缘计算；校准在电脑上做好，把文件拷过来 |

### 二进制兼容性与设备差异

构建脚本使用 `-mcpu=native` 针对编译时的 CPU 优化。建议在目标板上编译并运行。
若要把二进制移到另一型号的板子，指令集可能不兼容；可在目标设备上重编，或使用通用编译选项：

```bash
make fudaa_linux ARCHFLAGS=''
```

| 因素 | 为什么相关 | 建议 |
|---|---|---|
| `--workers` 并发数 | 取决于 CPU 核心数和大小核结构 | 从 2 开始，用 `bench` 测试 |
| 磁盘 | 每对图像会产生较多读写 | 建议使用 M.2 NVMe SSD |
| 散热 | 持续满载可能导致降频 | 长批处理时做好散热 |

### 参考板：Orange Pi 4 Pro

| 项目 | 参数 |
|---|---|
| SoC | Allwinner A733 |
| CPU | **2× Cortex-A76 + 6× Cortex-A55**，最高 2.0 GHz |
| 内存 | 最高 16 GB LPDDR5 |
| 存储 | eMMC / **M.2 M-Key（PCIe 3.0，支持 NVMe）** / TF 卡 |

该板有 2 个 Cortex-A76 大核和 6 个 Cortex-A55 小核。一次 935 帧的运行会产生十几 GB
中间文件，建议使用 NVMe SSD。并发性能受大小核结构影响，可从 `--workers 2` 开始，
再运行 `bench --sweep 1,2,4,6,8` 测试。

---

## 1. 要拷哪些东西到板子

将本仓库（`LSPIV_Edge`）和校准文件复制到板上即可。解算器源码已包含在仓库中。

> 下文以 `~/LSPIV_Edge/` 为部署目录；部署在其他目录时，按板上实际路径替换。

| # | 拷什么 | 为什么 | 体积 |
|---|---|---|---|
| 1 | **整个 `LSPIV_Edge` 仓库** | 主程序 + 补丁源码 + ARM 构建脚本，全在里面 | 含 Windows 解算器 |
| 2 | **你的校准文件**（电脑上用 GUI 做好的那 5 个） | 正射/网格/PIV 参数，缺了跑不了 | 极小 |
| 3 | *（可选）* 视频文件 | 有就一起拷，没有就在板子上现录 | 看视频大小 |

> 也可以只复制必需文件。`bin/windows/` 中的预编译解算器是 Windows 专用的，
> 板子上用不到（`.exe` 不能在 ARM Linux 上运行）。
> 用 `git clone` 的话可以加 `--depth 1` 减少体积。

**不要拷的**：

| 不要拷 | 原因 |
|---|---|
| `runs/` | 板上会重新生成；935 帧一次十几 GB，拷过去纯属浪费 |
| `bin/windows/` | Windows 解算器 `.exe`，ARM 上跑不了，会重新编 `.x` |
| `.venv/` | Windows 版 Python 虚拟环境，Linux 上无效；本项目**不需要任何第三方库** |

### 拷贝方式

```bash
# 方式一：git（板子能联网时）
git clone --depth 1 https://github.com/GvntherLvtjens/LSPIV_Edge-release.git ~/LSPIV_Edge

# 方式二：rsync（可断点续传，能排除大目录）
rsync -av --exclude 'runs/' --exclude 'bin/windows/' --exclude '.venv/' \
      --exclude '__pycache__/' \
      LSPIV_Edge/   pi@<板子IP>:~/LSPIV_Edge/

# 方式三：U 盘
```

> 传输前可加 `--dry-run` 检查文件列表，确认排除了不需要的目录后再执行。

---

## 2. 在板子上：编译 + 自检

```bash
# 1) 安装工具链
sudo apt update
sudo apt install -y gfortran make python3 ffmpeg

# 2) 进目录
cd ~/LSPIV_Edge

# 3) 编译解算器（约 1–3 分钟）
bash tools/arm/build_arm.sh
#   先打印补丁校验：看到 4 行 [OK] 才算通过；
#   出现 [X] 脚本会中止并说明原因（见 docs/SOLVER-PATCHES.md）
#   → 产出 tools/arm/exes_arm/PIV.x transf_a.x vel_transf.x filter.x vel_scal.x ortho_plan.x

# 4) 环境自检
python3 -c 'import sys;print("python3 =", "%d.%d.%d"%sys.version_info[:3])'
command -v ffmpeg ffprobe || echo "[X] 缺 ffmpeg/ffprobe"
for n in PIV transf_a vel_transf filter vel_scal ortho_plan; do
    [ -f "./tools/arm/exes_arm/$n.x" ] && echo "  [OK] $n.x" || echo "  [X] 缺 $n.x"
done
[ -f ./config.json ] || cp ./config.example.json ./config.json
```

以下检查均通过后继续：Python ≥3.8、可找到 `ffmpeg` 和 `ffprobe`、6 个 `.x` 文件齐全、
且已生成 `config.json`。

> `ffmpeg` 和 `ffprobe` 使用发行版提供的版本（`apt install ffmpeg`）。驱动会从
> `PATH` 查找它们。
>
> **ffmpeg 版本**：并行转图用的 `-c:v pgm` 是 ffmpeg 内置编码器，
> Debian/Ubuntu 的包都有。万一没有，驱动会自动退回两条较慢的路径，
> **只是慢一点，不会失败**（详见 [PERFORMANCE.md](PERFORMANCE.md)）。

---

## 3. 运行处理流程

### 3.1 运行 2 对样例

先运行两对图像，确认解算器能够正常处理后再运行完整视频。

```bash
python3 lspiv_batch.py piv \
    --exes ./tools/arm/exes_arm \
    --calib ./calib \
    --img-transf ./runs/<某次运行>/img_transf \
    --pairs 1:2
```

### 3.2 测试并发数

```bash
python3 lspiv_batch.py bench \
    --calib ./calib \
    --img-transf ./runs/<某次运行>/img_transf \
    --pairs 1:24 --sweep 1,2,4,6,8
```

命令会报告各并发数的耗时和建议值。可将选定值写入 `config.json` 的 `workers` 字段。

### 3.3 跑完整流水线

```bash
bash process_video.sh your_video.mp4
# 或每 5 帧取 1 帧（更快，适合先看效果）：
bash process_video.sh your_video.mp4 ./calib -- --every 5
```

> 板上使用 `.sh` 脚本；`.bat` 是 Windows 批处理格式，不能在 Linux 上运行。
> Linux 桌面通常不会像 Windows 一样将拖入脚本图标的视频作为参数传入，建议从命令行运行。
>
> `process_video.sh` 可以从**任意目录**调用：脚本会先把视频路径转成绝对路径，
> 再切到仓库根目录执行，所以结果固定落在仓库的 `runs/` 里，不会散到别处。

### 3.4 环境变量速查

| 变量 | 默认 | 作用 |
|---|---|---|
| `EXES` | 自动探测 `tools/arm/exes_arm` | 解算器目录 |
| `OUT` | 自动命名（仓库内 `runs/<视频名>_<时间戳>`） | 结果目录 |
| `WORKERS` | 由 `config.json` 决定 | 并发进程数 |
| `PGMBIN` | `1`（P5） | `0` = 退回 P2 文本（慢约 59 倍） |

`EXES` 的自动探测会**按平台挑后缀**：Linux/ARM 上找 `PIV.x`，Windows 上找
`PIV.exe`。所以仓库里的 Windows 解算器 `.exe` 不会被 ARM Linux 误选。

### 3.5 可选：桌面快捷方式

如果不想每次敲命令行，可以做一个桌面快捷方式：把下面内容存成
`~/Desktop/lspiv.desktop`，`chmod +x` 后再信任一次，之后把视频拖到这个图标上即可。

```ini
[Desktop Entry]
Type=Application
Name=LSPIV 跑视频
Terminal=true
Exec=bash -c 'bash "$HOME/LSPIV_Edge/process_video.sh" "$1"; echo; read -p "按回车关闭"', --
```

> 快捷方式调用的仍是 `process_video.sh`。测试时可直接从命令行运行，便于查看错误信息。

---

## 4. 驱动侧为 ARM 做的改动

除了 Fortran 补丁（见 [SOLVER-PATCHES.md](SOLVER-PATCHES.md)），Python 驱动也有三处
是与跨平台/ARM 直接相关的：

### 4.1 解算器后缀自动解析（`solver_exe()`）

```python
EXE_EXT = ".exe" if os.name == "nt" else ".x"
```

Windows 上是 `PIV.exe`，ARM/Linux 上是 `PIV.x`。**所有**解算器调用都走
`solver_exe(exes, name)`，不允许硬编码后缀。

> `run_transforms()` 曾使用硬编码路径 `exes / "transf_a.exe"`，导致 ARM 上无法运行。
> 现在解算器路径统一由 `solver_exe()` 生成。

### 4.2 `ffmpeg` 回退

`resolve_media_tools()` 先找 `exes/ffmpeg`；找不到就退回系统 `PATH` 里的 `ffmpeg`。
驱动从系统 `PATH` 查找 `ffmpeg` 和 `ffprobe`，无需复制 Windows 版。

### 4.3 `PIV_param.dat` 的 `Bi` 归一化

开跑前一次性把 `Bi` 改成奇数，消除多进程竞态（上游缺陷，见
[SOLVER-PATCHES.md](SOLVER-PATCHES.md) 的 Patch 3）。

### 4.4 解算器目录的自动探测（`resolve_exes()`）

`--exes` 显式给了就用给的；否则读 `config.json` 的 `exes_dir`；**该目录不存在时**
再按平台探测仓库自带的两种布局：

| 平台 | 探测顺序 | 认哪个后缀 |
|---|---|---|
| Windows | `bin/windows` → `tools/arm/exes_arm` → `exes` | `PIV.exe` |
| Linux / ARM | `tools/arm/exes_arm` → `exes` → `bin/windows` | `PIV.x` |

判定用的是**本机后缀**，不是"目录存不存在"。**这点很关键**：仓库里同时带着
`bin/windows/*.exe`，如果只判断目录存在，板上就会选中那堆 `.exe`，然后在跑了
几分钟之后才失败。按后缀判定可以直接避开。

因此 `config.json` 里**不需要**再写 `exes_dir` 了（`config.example.json` 已移除该键），
新克隆下来开箱即用。

---

## 5. 性能预期

### 5.1 性能参考

解算器是**标量计算 + 大量 I/O**，不吃 NEON 向量化。
Cortex-A76 单核大约是桌面大核的 1/3–1/2。

ARM 内存带宽较低，P5 格式在 ARM 上的收益可能高于 PC。本仓库默认使用 P5。

**Orange Pi 4 Pro 的合理预期**：2 个大核大致提供 0.6–1.0 个桌面核的算力。
规划吞吐时可按约一台双核笔记本的计算能力估算，不应按 8 核线性估算。

### 5.2 第二阶段并发数不受 `--workers` 影响

`convert_frames()` 自己按 `min(CPU 核数, 8)` 切段跑并行 ffmpeg；
`--workers` 只管正射 / PIV 那两段。板上报 8 核就会同时起 8 个 ffmpeg 解 PNG，
对内存带宽压力不小。

**若实测这一段反而变慢**，把它降下来：改 `lspiv_batch.py` 里的
`CONVERT_PARTS_CAP`（默认 8，可改为 4 测试）。三层输出**逐字节相同**，因此改并发数
**不影响结果**。

### 5.3 外业部署真正的瓶颈不是 CPU

| 风险 | 数字 | 对策 |
|---|---|---|
| **磁盘** | 935 帧一次运行产出 **十几 GB** | **接 M.2 NVMe SSD**；或跑完立刻导出 CSV 并清中间产物 |
| **散热** | 持续满载会降频 | 长批处理加散热片 |
| **I/O 带宽** | 比 CPU 更早撞墙 | 坚持用 P5（默认已是） |

改用 P5 后，`img_pgm/` 和 `img_transf/` 各从约 2.4 GB 降到约 0.6 GB。

---

## 6. 外业跑完后的清理

板上只留结果，清掉中间产物：

```bash
cd ~/LSPIV_Edge/runs/<本次运行>
python3 ../../export_results.py .       # 先确保 CSV 已导出
rm -rf frames/ img_pgm/ img_transf/      # 结果在 vel_raw/ vel_real/ export/
```

这三者合计约占一次运行的 **90% 以上**体积。

---

## 7. 板上目录长这样

```
~/LSPIV_Edge/
├── lspiv_batch.py            ← 主程序（跨平台：.exe / .x 自动解析 + ffmpeg 回退）
├── process_video.sh          ← 一键流水线
├── export_csv.sh / export_results.py
├── calib/                    ← 你的校准文件
├── config.json               ← 在这里设 workers
├── runs/                     ← 结果
└── tools/
    ├── arm/
    │   ├── makefile          ← ARM 版 makefile（3 处 [ARM-n] 标注）
    │   ├── build_arm.sh      ← 构建脚本（含编译前补丁校验）
    │   └── exes_arm/         ← 构建产物（板上生成）
    └── solver-patches/       ← 已打补丁的源码
```

---

## 8. 部署检查

- 在目标板上运行 `bash tools/arm/build_arm.sh`，确认补丁校验全部通过。
- 按第 2 节完成环境自检，确认 Python、`ffmpeg`、`ffprobe` 和 6 个解算器均可用。
- 建议使用 M.2 NVMe SSD。`--workers` 的取值应在目标板上运行 `bench` 后确定。
