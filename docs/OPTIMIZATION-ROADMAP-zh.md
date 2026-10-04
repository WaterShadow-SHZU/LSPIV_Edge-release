# LSPIV_Edge 优化路线与 Linux-ARM 移植评估

> **说明**：本文是开发过程中的分析与评估记录，保留了当时的原始数据与推理过程，
> 因此提到的路径可能仍是开发期的目录名（`velocimetry_solver-master/sources` 即
> 当前仓库的 `tools/solver-patches/`）。**结论部分仍然有效**；要查最新用法请看
> [ARM 部署说明](ARM-DEPLOYMENT-zh.md) 与 [性能说明](PERFORMANCE.md)。

面向三个问题：

1. 剩下的固定开销还能砍掉吗、怎么砍、能砍多少；
2. 该配什么工具链；
3. `LSPIV_Edge` 能不能上 Linux-ARM，解算器能不能编到 ARM，`Fudaa-LSPIV-Linux` 那套 x86 适配能不能变成 ARM。

先把答案放前面：

| 问题 | 结论 | 依据 |
|---|---|---|
| 固定开销还能砍吗 | **能，还剩 2.5–3×**。每对 0.140 s → 0.05–0.06 s | 第 1 节 |
| 靠什么砍 | 换二进制 P5 读图（最大）+ 批处理主程序一次性读参数、不建工作目录 | 第 1.3 节 |
| 要不要编译器 | **要**。本机没有 gfortran，要先装 | 第 2 节 |
| 解算器能编到 ARM 吗 | **能，且改动极小**：源码不依赖任何外部数值库，只需改 3 行 makefile | 第 3.1 节 |
| LSPIV_Edge 能跑在 ARM 吗 | **能**，它是纯标准库 Python；只有一个坑：可执行名硬编码 `.exe` | 第 3.2 节 |
| Linux 版 GUI 能变 ARM 吗 | **能，属于"重新打包"**：jar 里 0 个原生库，只是内置的 JDK 和启动器要换成 aarch64 | 第 3.3 节 |

---

# 一、剩下的固定开销能砍掉多少

## 1.1 现在每对 0.140 s 花在哪

| 组成 | 每对耗时 | 占 `PIV.exe` | 能砍吗 | 怎么砍 | 要编译器吗 |
|---|---|---|---|---|---|
| Python 调度层（建目录/拷贝/移结果） | 0.005 s | — | **已砍完** | 常驻工作目录 + 原地覆盖 + `os.replace` | 不用 |
| `PIV.exe` 进程启动 + gfortran/OpenMP 运行时初始化 | ~0.02 s | ~15% | 能 | 批处理主程序：一个进程跑整批，只付一次 | **要** |
| 读两张 P2 文本图、解析 2×64 万个数字 | ~0.08 s | **~60%** | 能 | 加一个二进制 P5 读取器 | **要** |
| 互相关网格计算 | ~0.022 s | ~16% | 本来就并行 | 不用动 | 不用 |
| 写 `vel_raw/piv.dat`（2.3 万字符） | ~0.01 s | ~7% | 能 | 写二进制；或合并进批处理主程序 | **要** |

拆法：T=1 与 T=12 的差值给出可并行部分（16%），单图 P2 解析 0.04 s 来自对同一张 2.5 MB PGM 的受控计时，余下是启动与写结果。绝对值有 ±30% 抖动，**看结构不要看小数**。

关键在第三行：**解算器只认 ASCII 的 PGM P2**。`sub_transf_23D.f90` 第 62 行明确检查 `p2 /= 'P2'` 就报错，读法是把 64 万个数字当文本用 `read(lw,*)` 全量解析（第 124 行）。一张 1089×591 的图，P2 是 2.56 MB 文本，同样的像素存成 P5 二进制只有 0.64 MB。**这是全流程里最大的一笔纯浪费，而且它每对要付两次。**

> 顺带一个旁证：上游自己在 `solver_appli.f90` 第 624–677 行写了一个 `convert_P2` 子程序，专门用多核把 P5 转成 P2——**他们知道 P5 更好，但下游只吃 P2，所以只能先转一遍**。

## 1.2 已经拿到的：0.29 s → 0.140 s

这一层不需要编译器，已经在 `lspiv_batch.py` 里做完（详见 `MULTICORE-ANALYSIS-zh.md` 第 2.1 节）：

- 每对图像原本要删掉上一次次的工作目录，而**这台机器上删一个文件固定要 0.10 s**（与文件大小无关）。一次 934 对的运行要删近 2800 个文件/目录，折合每对 0.145 s。
- 改成每进程一个常驻工作目录、原地覆盖图像、用改名移出结果后，每对从 0.29 s 降到 0.140 s；48 对的批处理扩展性也从 8 进程 3.7× 变成 12 进程 5.4×。
- 视频路径里 `normalize_pgm` 原来是纯 Python 逐字节分词，一张图 0.33 s，改成按行的 C 级实现后 0.040 s（8.3×），输出逐字节相同。

## 1.3 还能拿的：再 2.5–3×

按上游 `solver_appli.f90` 的做法重写一个批处理 PIV 主程序，顺带换 P5 读图：

| 改动 | 每对省下 | 说明 |
|---|---|---|
| 一个进程跑整批图像对，`!$omp parallel do` 开在图像对循环上 | ~0.025 s | 进程启动 + 运行时初始化摊销到零；每对仍用 `ncore=1` 调用 `sub_PIV` |
| `PIV_param.dat` / `grid.dat` 只读一次 | 可忽略 | 顺手 |
| 新增 `read_PGM_P5`，图片按二进制读 | **~0.075 s** | 读盘量 2.56 MB → 0.64 MB，且不再逐字符解析 |
| 主程序自己按 `NNNN.pgm` 命名读图 | ~0.005 s | 不再需要工作目录，Python 侧只剩启动与汇总 |
| 输出二进制或直接汇总 | ~0.005 s | 可选 |

净结果：每对 **0.140 s → 0.05–0.06 s**，一张 935 帧的视频从约 1 分钟量级压到 20 秒量级（12 核并发）。

**收益排序**：P5 读图 ≫ 进程摊销 > 其余。如果只想做一件事，就做 P5 读图。

另外顺手能修的两个解算器缺陷（`sub_PIV.f90`，见分析文档第 5 节）不影响流速，但修完 `vel_raw` 的第 6–8 列才可复现——如果你以后想拿这几个量做质量控制，必须先修。

## 1.4 一个不是 CPU 的瓶颈：磁盘

935 帧的一次完整运行目录是 **12.2 GB**，因为同一条流水线上同一批画面被存了三遍：

| 目录 | 内容 | 体积 |
|---|---|---|
| `frames/` | ffmpeg 抽出的 PNG（1920×1080） | ~3.2 GB |
| `img_pgm/` | 转成的 P2 文本图 | ~2.4 GB |
| `img_transf/` | 正射后的 P2 文本图 | ~2.4 GB |
| `runs/tmp/` | 解算器工作目录 | ~40 MB |

换成 P5 后 `img_pgm` 和 `img_transf` 各降到 ~0.6 GB。真要上外业设备，这是比 CPU 更早撞到的墙。

---

# 二、推荐什么工具链

## 2.1 Windows（本机编译）

**首选 MSYS2（UCRT64 环境）**，一个包管理器把 gfortran、make、cmake 都给齐：

```bash
# 装完 MSYS2 后在 "MSYS2 UCRT64" 终端里
pacman -S mingw-w64-ucrt-x86_64-gcc-fortran make
```

**备选 winlibs**（免安装 zip，解压即用，里面已含 gfortran 和 `mingw32-make`），适合不想装 MSYS2 的情况。

两个选择都行，**不要**用 MSVC（源码是 gfortran 方言 + OpenMP），**不要**指望 WSL 编出来的二进制给 Windows 用（那是 Linux 二进制）。

**不需要 cmake**：`cmake` 只用来编 `sources/stab_img`（FlowPic 的图像稳定化模块，产出 `exesurf`）。`LSPIV_Edge` 只用 `PIV.exe` / `transf_a.exe` / `vel_transf.exe` / `filter.exe` / `vel_scal.exe`，这些都是纯 Fortran，直接调 gfortran 就行。

**建议直接手写编译命令，别走 makefile**——makefile 里带了交叉工具链（`x86_64-w64-mingw32-gfortran`）、`uname -n`、硬编码的 `libgfortran.so.5` 路径，在本机原生编译时反而要绕。等价的一行命令：

```bash
# 在 tools/solver-patches 下执行
gfortran -cpp -Dopenmp -fopenmp -O3 -fimplicit-none -static -no-pie \
         -ffpe-summary=invalid,zero,overflow \
         errors.f90 sub_lspiv_parameter.f90 sub_PIV.f90 PIV.f90 -o PIV.exe

gfortran -cpp -Dopenmp -fopenmp -O3 -fimplicit-none -static -no-pie \
         errors.f90 sub_lspiv_parameter.f90 sub_transf_23D.f90 transf_23D.f90 -o transf_a.exe

gfortran -cpp -Dopenmp -fopenmp -O3 -fimplicit-none -static -no-pie \
         errors.f90 sub_lspiv_parameter.f90 sub_vel_transf.f90 vel_transf.f90 -o vel_transf.exe
```

要点：
- **源文件顺序不能乱**：`errors.f90`（定义 `errors` 模块）和 `sub_lspiv_parameter.f90`（定义 `lspiv_parameter` 里的目录名、参数文件名常量）必须排在使用它们的文件之前。这与 makefile 里 `SRC_utils` 的位置一致。
- `-static` 让 mingw 把 libgfortran/libgcc 静态链进去，**不用附带任何 DLL**，和你现在 `exes/` 里那套一样（现成 exe 是 1.3–1.4 MB，静态链的迹象）。
- `-Dopenmp -fopenmp` 决定它认不认第一个命令行参数当线程数。**漏了这个开关，编出来的就是单核版，而且不报错**。
- 保留 `-march=x86-64 -mtune=generic`（makefile 的默认）更保险：如果你要打包发给别人的机器，用 `-march=native` 可能在老 CPU 上非法指令。
- 只想要"和现在完全一样的行为"就先编 `PIV.exe` 和 `transf_a.exe` 两个，用 `--exes` 指到一个新目录试，别直接覆盖 `exes/`。

**验证方法**（一定要做）：

```bat
py -3 lspiv_batch.py piv --exes <新目录> --calib <校准> --img-transf <img_transf> --out runs\_verify --pairs 1:4
```

然后把 `runs\_verify\vel_raw\piv0001.dat` 与旧 `exes` 跑出来的同名文件逐列比对——**前 5 列应逐位相同**，第 6–8 列本来就不确定（第 1.3 节那个缺陷）。列对不上就说明编译选项（尤其是 `-O3` 浮点重排）或源码版本不一致。

## 2.2 Linux / ARM 上编译

比 Windows 简单：

```bash
sudo apt install gfortran make          # 树莓派 OS / Ubuntu ARM
# 然后同一行命令，去掉 -static（Linux 的 ld 会正确找到 libgfortran）
gfortran -cpp -Dopenmp -fopenmp -O3 -fimplicit-none -no-pie \
         errors.f90 sub_lspiv_parameter.f90 sub_PIV.f90 PIV.f90 -o PIV.x
```

输出名要和 GUI / 发布包一致：Linux 版是 `.x` 后缀（`PIV.x`、`transf_a.x`…），Windows 版才是 `.exe`。

注意两点：
- **删掉 `-march=x86-64`**。aarch64 上的 gfortran 不认识这个值会直接报错；想要本机优化就用 `-mcpu=native`，想保持可移植就什么都不写。
- **不需要**手工拷 `libgfortran.so.5`（makefile 第 182 行那句是给"打包发到别的机器"用的）。要打包到没有 gfortran 的板子上，就拷 `/lib/aarch64-linux-gnu/libgfortran.so.5`，或者在链接时加 `-static-libgfortran`。

---

# 三、Linux-ARM 可行性

## 3.1 解算器能编到 ARM 吗：能，改动极小

把 `tools/solver-patches/` 下所有 `.f90` 的依赖扫了一遍：

| 用到的模块 | 来源 | 是否可移植 |
|---|---|---|
| `iso_fortran_env` | Fortran 标准库 | 是 |
| `omp_lib` | OpenMP 运行时（gfortran 自带） | 是 |
| `lspiv_parameter`、`mod_PIV`、`mod_transf_23D`、`errors` … | 仓库自带源码 | 是 |
| `kdtree2_module` | 仓库自带 `kdtree2.f90`（55 KB 纯 Fortran） | 是 |
| BLAS / LAPACK / FFTW / HDF5 / NetCDF | — | **一个都不用** |

也就是说：**纯标准 Fortran + OpenMP，没有任何外部数值库依赖**。这是移植最理想的情形——同一个源码、同一个编译器（gfortran）、同一套 OpenMP，只是换个目标架构。

要改的地方（全部在 `sources/makefile`）：

| 行号 | 现在 | ARM 上要改成 | 原因 |
|---|---|---|---|
| 112 / 115 / 120 / 123 | `-march=x86-64 -mtune=generic` | `-mcpu=native` 或删掉 | aarch64 的 gfortran 不认 `x86-64` |
| 92–98 | 依次找 `gfortran-10` / `-9` / `-8` | 加一行兜底到 `gfortran` | Debian/Ubuntu 的包就叫 `gfortran`，没有版本号后缀 |
| 141 / 182 | `cp /lib/x86_64-linux-gnu/libgfortran.so.5` | `/lib/aarch64-linux-gnu/...`，或直接删掉 | 只影响"打包分发"，不影响编译 |

另外 `-no-pie`、`-ffpe-summary=...` 在 aarch64 上都正常。`-static` 在 Linux 目标里本来就没用（只有 Windows 目标用 `WLFLAGS`）。

**性能预期要放平**：解算器是标量计算 + 大量文本 I/O，不吃 NEON。树莓派 5 的 Cortex-A76 单核大约是桌面大核的 1/3–1/2，4 核并发大致等于一台老双核笔记本。**一帧 1089×591 的 P2 解析在 ARM 上会更慢**（内存带宽低），所以第 1.3 节那个 P5 改造在 ARM 上的收益比在 PC 上更大，不是更小。

> 关于 makefile 的三个构建目标，别选错：
> - `make station` → `exe_station/`：产出 `PIV` / `transf_a` / `filter` / `moy_ec` / `Q_compute` / `ortho_plan` / `verif_ortho` / `gen_mask`（**无后缀**），且带 `-Dversion_station`——**这批二进制把工作目录当命令行参数**（`PIV <outputs目录> <工作目录> <线程数>`，见 `PIV.f90` 第 60–63 行、`transf_23D.f90` 第 65–67 行、`filter.f90` 第 45–48 行）。不需要 cmake。
> - `make fudaa_linux` → `exe_fudaa_linux/*.x` + `lib_fudaa_linux/*.so`：**这才是 GUI 用的那套**，命令行约定和 Windows 版一致（第一个参数=线程数）。要替 GUI 换 aarch64 解算器，就编这个目标。
> - `make appli` → `exe_appli/solver_appli`（FlowPic 批处理程序），需要 cmake 先编 `stab_img`。
>
> `station` 那套的"目录当参数"其实正是做批处理驱动最方便的接口，但它和 GUI 不兼容（同一份 `PIV.exe` 只能是一种约定）。**决定要不要走 station 之前先想清楚：这批二进制是给脚本用，还是要同时给 GUI 用。**

## 3.2 LSPIV_Edge 能跑在 ARM 上吗：能，只需一个平台补丁

`lspiv_batch.py` 只使用 Python 标准库（`argparse`、`concurrent.futures`、`json`、`os`、`re`、`shutil`、`subprocess`、`sys`、`tempfile`、`time`、`pathlib` 和 `typing`），不依赖 numpy、scipy、opencv 或 PIL。在 aarch64 上运行不需要编译 Python 扩展，安装 Python 3.8 或更新版本即可。

本节记录移植过程中的旧问题。当前版本已按平台选择解算器后缀（Windows 为 `.exe`，Linux 为 `.x`），
并优先从解算器目录、再从 `PATH` 查找 `ffmpeg` 和 `ffprobe`。

当时发现可执行文件名被硬编码成 `.exe`，涉及：

| 硬编码的名字 | 用途 |
|---|---|
| `PIV.exe` | 逐对互相关 |
| `transf_a.exe` | 正射变换 |
| `vel_transf.exe` | 瞬时结果 → 真实流速 |
| `filter.exe` | 时域滤波（可选） |
| `vel_scal.exe` | 标量流速（可选） |
| `ortho_plan.exe` | 生成 `coeff.dat` |
| `ffmpeg` / `ffprobe` | 抽帧与读尺寸；程序优先查解算器目录，再查 `PATH` |

而 Linux 版解算器是 `.x` 后缀。有意思的是，**GUI 自己早就处理了这件事**：`PivExeLauncher.java` 第 258 行

```java
private static final String EXE_EXT=FuLib.isWindows()?".exe":".x";
```

也就是说这不是"Linux 支持不了"，只是本工具漏了这个分支。

当时的临时验证方案是在 Linux 上把 `.x` 二进制改名为 `.exe` 软链接：

```bash
mkdir -p ~/lspiv-exes
cd ~/lspiv-exes
for n in PIV transf_a vel_transf filter vel_scal ortho_plan; do ln -sf "$BUILD/$n.x" "$n.exe"; done
py -3 lspiv_batch.py piv --exes ~/lspiv-exes --calib ... --img-transf ...
```

现在无需为 ffmpeg 建软链接；程序会从 `PATH` 查找它们。解算器也会自动识别 `.x` 和 `.exe`。

还有三处 Windows 专用但**不在核心链路上**的东西：

| 文件 | 状态 |
|---|---|
| `setup_once.bat`、`process_video.bat`、`export_csv.bat`、`pack_portable.bat` | 纯 Windows 批处理，需要写 `.sh` 等价物 → **已落地**：`process_video.sh` / `export_csv.sh` 已交付；`setup_once` / `pack_portable` 两个薄壳已移除（最新状态见《ARM 部署说明》） |
| `runs/` 下的路径 | 用的是 `pathlib`，跨平台，没问题 |
| `config.json` 的相对路径解析 | 基于 `Path(__file__).parent`，跨平台，没问题 |

FFmpeg 不随本仓库分发。Windows 上安装 FFmpeg 并将 `ffmpeg`、`ffprobe` 加入 `PATH`；Linux/ARM 上可使用发行版提供的包，例如 `sudo apt install ffmpeg`。

## 3.3 Linux 版 GUI 能变成 ARM 吗：能，但属于"重新打包"而不是"改代码"

先把 `Fudaa-LSPIV-Linux` 的现状点清楚（`fudaa-lspiv-1.11.3-linux-x64`，jpackage 打包的 app-image）：

```
Fudaa-LSPIV-Linux/
├── fudaa-lspiv.sh                     启动脚本
├── exes/                              ← 解算器（x86_64 ELF）
│   ├── PIV.x, transf_a.x, filter.x, vel_scal.x, vel_transf.x,
│   │   ortho_plan.x, verif_ortho.x, gen_img_ref.x, moy_*.x, Q_compute.x,
│   │   bathy_compute.x, manual_vel.x, stab_img.x
│   ├── ffmpeg.x, ffprobe.x            各 63 MB（x86_64 静态）
│   └── libgfortran.so.5               x86_64
└── appli/
    ├── bin/appli                      18 KB 原生启动器（ELF x86_64）
    └── lib/
        ├── libapplauncher.so          x86_64
        ├── app/fudaa-lspiv.jar        69.6 MB
        └── runtime/                   Ubuntu 的 JDK 11.0.19，OS_ARCH=x86_64
```

关键发现：**`fudaa-lspiv.jar` 里一个原生库都没有**（33593 个 `.class`，0 个 `.so` / `.dll`）。而且：

| 检查项 | 结果 |
|---|---|
| `org/eclipse/swt`（SWT，需要平台原生库） | 0 个类 |
| `com/jogamp` + `javax/media/opengl`（JOGL，3D 原生库） | 0 个类 |
| `com/sun/jna`（JNA） | 0 个类 |
| `org/fudaa`（本软件自己的代码） | 4905 个类 |
| 字节码版本 | `Build-Jdk-Spec: 11` |

**结论：GUI 是纯 Java Swing/AWT，没有第三方原生依赖。** 需要平台相关的那部分（AWT/Swing 的窗口系统绑定）在 JDK 自己身上，而 JDK 有官方的 aarch64 构建。所以移植 GUI 要做的只是替换"外面那圈壳"：

| 要做什么 | 具体做法 |
|---|---|
| 换 JDK | 装 aarch64 的 JDK/JRE 11（Temurin、Zulu 或 `openjdk-11-jre`）。`runtime/release` 里 `JAVA_VERSION="11.0.19"`，用 11 最稳，17 一般也能跑 |
| 换启动方式 | 现有的 `bin/appli` + `libapplauncher.so` 是 x86_64，直接跑不了。两条路：① 在 aarch64 上用 `jpackage`（JDK 14+ 自带）重新生成启动器；② **绕过启动器**，直接 `java -cp fudaa-lspiv.jar org.fudaa.fudaa.piv.Piv`（`appli.cfg` 里就是 classpath + mainclass，没有额外参数） |
| 换解算器 | 用第 3.1 节的方法编 `make fudaa_linux`（`.x` 后缀那套），替换 `exes/` 下对应的文件；`libgfortran.so.5` 也换成 aarch64 的 |
| 换 ffmpeg | 用发行版的 `ffmpeg` / `ffprobe`，按 `EXE_EXT` 约定命名成 `ffmpeg.x` / `ffprobe.x`（或软链接），因为 GUI 是拼 `exePath + "/" + "ffmpeg" + ".x"` 去找的 |

工作量：**一个重新打包项目，不是一个开发项目**。没有任何一行 Java 需要改。风险点在 ①`jpackage` 重打包在 ARM 上的可用性（绕过去就没有这个问题）、②GUI 在某些 ARM 桌面环境下缺 GTK 依赖（headless 监测不需要 GUI，这个风险可以完全回避）。

## 3.4 三种落地形态

| 形态 | 需要什么 | 适合 |
|---|---|---|
| **A. 无 GUI，只跑 LSPIV_Edge** | aarch64 的 `.x` 解算器 + Python + ffmpeg + 第 3.2 节的 `.exe` 后缀补丁 | **外业监测、无人值守**。首选 |
| B. 形态 A + 现有 GUI | 再加 aarch64 JDK + 启动器重打包 | 现场要有人工校正正射/网格、或要可视化看结果 |
| C. 只搬 LSPIV_Edge，不编解算器 | — | **不可行**。`exes/` 里是 x86_64 ELF，ARM 上跑不起来；必须有 aarch64 版解算器 |

如果外业场景是"架好相机、录一段、自动出流速"，形态 A 就够了，而且能省掉整个 GUI 重打包的不确定性。GUI 只在"需要现场调网格、看轨迹图、手动剔除坏点"时才值得搬。

## 3.5 板子与核数建议

| 平台 | 核心 | `--cpu-budget` 建议 |
|---|---|---|
| 树莓派 4 | 4×A72 | 4 |
| 树莓派 5 | 4×A76（无大小核） | 4 |
| 香橙派 5 / RK3588 | 4×A76 + 4×A55 | **先按 4 起步**，再 `bench` 定 |
| x86 小主机 / N100 | 4 大核（E 核） | 4 |

原因就是你 PC 上已经验证过的那件事：**多出来的核如果是小核，边际收益很小**。本机 6→8→12 进程的边际是 +0.68× → +0.33×，12 核只拿到 5.4×。ARM 板上的大核本来就少，更要把预算花在大核上。

另外外业部署有两件事比核数更要紧：
- **I/O 带宽**：解算器读的是文本 PGM，ARM 上这一步的收益占比更高，**P5 改造比换板子值**。
- **磁盘与散热**：一次 935 帧运行约占 12.2 GB（第 1.4 节），eMMC/TF 卡的容量和写入速度可能成为限制。建议使用 USB SSD，或在运行结束后导出 CSV 并清理 `frames/`、`img_pgm/`。持续满载时 ARM 板可能降频，长时间批处理建议加散热片。

## 3.6 落地步骤（建议顺序）

1. **PC 上装 MSYS2 的 gfortran**，用第 2.1 节的一行命令编 `PIV.exe` + `transf_a.exe`，用 `--exes` 指到新目录跑 4 对，和现有结果比前 5 列 → 确认工具链可靠。
2. **验证 P5 改造的收益**：加一个 `read_PGM_P5`（`sub_transf_23D.f90` 第 29 行的过程指针换指向，第 141 行的 `write_PGM_P2` 旁边加个 P5 版本），Python 侧 `write_p2` 加一个二进制分支。跑 `bench` 看每对耗时是否从 0.140 s 掉到 0.06 s 量级。**这一步收益最大，先做这一步。**
3. **批处理主程序**（可选）：按 `solver_appli.f90` 的骨架写，一次性读参数、并行图像对循环、不建工作目录。这一步收益是每对再省 0.03 s，工作量比第 2 步大，可以后做。
4. **ARM 解算器**：在目标板上 `apt install gfortran`，用第 2.2 节的命令编出 `.x`，先在板上跑 `piv --pairs 1:2` 确认能出结果。
5. **LSPIV_Edge 跨平台补丁**：把 `.exe` / `.x` 后缀解析集中到一处，Windows 行为不变。
6. **端到端**：板上跑一条完整 video 流水线，量出每帧实际耗时，再决定要不要上形态 B（GUI）。

第 1、2 步不依赖任何 ARM 硬件，**建议先在 PC 上做完**——它们既是 ARM 方案的前置，本身也能立刻把你现在的 1 分钟压到 30 秒以内。

---

# 附录：makefile 三处改动（ARM 用）

```make
# 第 92-98 行：编译器探测，补一个无版本号的兜底
FC	= gfortran-10
ifeq (,$(shell which gfortran-10))
	FC	= gfortran-9
	ifeq (,$(shell which gfortran-9))
		FC	= gfortran-8
		ifeq (,$(shell which gfortran-8))
			FC	= gfortran        # ← 加上这层
		endif
	endif
endif

# 第 112 / 115 / 120 / 123 行：把 -march=x86-64 -mtune=generic
#   换成 -mcpu=native（或整段删掉），四处都要改

# 第 141 / 182 行：只在需要"打包发到没有 gfortran 的机器"时才需要
cp /lib/aarch64-linux-gnu/libgfortran.so.5 $(EXEDIR)_$(cible2)/     # ← 路径换成 aarch64
```

不改 makefile 也可以：用第 2.2 节那几行 `gfortran` 命令直接编译，效果一样，而且不用处理 `uname -n`、`$(pwd)` 那些在部分环境里会出问题的写法。
