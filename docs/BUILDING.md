# Building from source

Everything here builds with `gfortran`. There is **no dependency on Intel MKL, OpenMPI,
BLAS/LAPACK, FFTW, HDF5 or NetCDF** — the solver is plain Fortran 90 plus OpenMP, which
is why it cross-compiles and runs on small ARM boards without fuss.

---

## Windows (x86-64)

`bin/windows/` contains prebuilt solver binaries built from these sources. Rebuild if
you change the Fortran, or want to verify the binaries match the source. FFmpeg and
ffprobe are separate requirements and are not included.

### Prerequisites

[MSYS2](https://www.msys2.org/), installed to `C:\msys64` (the default). In the
**UCRT64** shell, install the toolchain:

```bash
pacman -S mingw-w64-ucrt-x86_64-gcc-fortran make
```

That gives you `gfortran` (16.x at the time of writing) and `make` under
`C:\msys64\ucrt64\bin\`.

For video processing, install FFmpeg and make both `ffmpeg` and `ffprobe`
available on `PATH`. They are not included in this repository.

### Build

```bat
tools\build_windows.bat
```

If MSYS2 lives elsewhere, point it there first:

```bat
set MSYS2_ROOT=D:\msys64
tools\build_windows.bat
```

Output lands in `bin\rebuild\`. The compiler log is `tools\build_windows.log`.

### Using the rebuilt binaries

Copy the 6 `.exe` from `bin\rebuild\` over the same-named files in `bin\windows\`.
The solver is linked `-static` and does not need Fortran runtime DLLs.

### Compiler flags, and why

```
-cpp -Dopenmp -fopenmp -O3 -fimplicit-none -static -no-pie
```

| Flag | Purpose |
|---|---|
| `-cpp` | Enable the C preprocessor — the sources use `#ifdef openmp` |
| `-Dopenmp` | Define the OpenMP symbol so the parallel code paths compile in |
| `-fopenmp` | Link the OpenMP runtime |
| `-O3` | Full optimisation (this is a numerically heavy inner loop) |
| `-fimplicit-none` | Reject undeclared variables — catches typos as errors instead of silent bugs |
| `-static` | No external Fortran runtime DLL — makes the binaries self-contained |
| `-no-pie` | Simpler binary layout on Windows |

> **Source file order matters.** `errors.f90` and `sub_lspiv_parameter.f90` define
> modules and must be compiled **before** the files that `use` them. The build script
> handles this; if you compile by hand, keep that order.

### One-liner example

```bash
cd tools/solver-patches
gfortran -cpp -Dopenmp -fopenmp -O3 -fimplicit-none -static -no-pie \
    errors.f90 sub_lspiv_parameter.f90 sub_PIV.f90 PIV.f90 -o PIV.exe
```

---

## ARM boards (Raspberry Pi / Orange Pi / etc.)

Cross-compilation is deliberately **not** used. Build natively on the board — it takes
1–3 minutes and avoids the entire class of "the cross-toolchain produced a binary the
kernel won't run" problems.

### Prerequisites

```bash
sudo apt update
sudo apt install -y gfortran make python3 ffmpeg
```

`python3` runs the driver; `ffmpeg` extracts frames. Install `ffmpeg` and `ffprobe`
from your distribution. The driver looks for them on `PATH`.

> **ffmpeg version note.** The parallel frame-conversion path uses ffmpeg's built-in
> `pgm` encoder with `-c:v pgm`. Every mainstream Debian/Ubuntu build has it. If yours
> somehow doesn't, the driver automatically falls back to two slower paths, so the run
> still completes — it just takes longer. See [PERFORMANCE.md](PERFORMANCE.md).

### Build

```bash
bash tools/arm/build_arm.sh
```

The script:

1. **Verifies the patches are present** — 4 marker checks. Refuses to build a solver
   that would fail on P5 images. This guard exists because a stale source tree
   once produced a board that failed on 100 % of frames; failing loudly at build time
   is far better than failing halfway through a field run.
2. Copies the sources to a scratch tree (`tools/arm/build_arm/`) so your source
   directory stays clean — no `.mod` files, no clobbered `makefile`.
3. Swaps in the ARM `makefile` (the upstream one hardcodes Windows paths).
4. Runs `make fudaa_linux`, collecting binaries into `tools/arm/exes_arm/`.

Expected output:

```
>>> 校验源码补丁（P5 读图 / Bi 修复）
    [OK] sub_PIV.f90  --  P5 读图（PIV）
    [OK] sub_transf_23D.f90  --  P5 读图（transf_a）
    [OK] transf_23D.f90  --  读图指针已切到新函数
    [OK] sub_lspiv_parameter.f90  --  PIV_param.dat 可读写（Bi 自愈）
...
构建完成：N 个产物 -> .../tools/arm/exes_arm
```

### Options

```bash
bash tools/arm/build_arm.sh                      # default: fudaa_linux target
bash tools/arm/build_arm.sh station              # 'station' target
bash tools/arm/build_arm.sh fudaa_linux ~/out    # custom output directory
```

### If the build fails

| Symptom | Fix |
|---|---|
| `ERROR: 找不到 gfortran` | `sudo apt install -y gfortran` |
| `-march` / `-mcpu` related errors | `make fudaa_linux ARCHFLAGS=''` |
| `stab_img` related messages | Harmless — a placeholder is substituted; the driver doesn't use it |
| A `[X]` line in the patch check | Wrong source tree. Use `tools/solver-patches/` from this repo |

The ARM `makefile` differs from upstream in three places, each annotated with an
`[ARM-n]` comment so you can find them.

---

## Verifying the build

Don't trust a build until it has solved at least two real pairs. On the board:

```bash
# If you have an image set (img_transf/) and calibration:
python3 lspiv_batch.py piv \
    --exes ./tools/arm/exes_arm \
    --calib ./calib \
    --img-transf ./img_transf \
    --pairs 1:2
```

Then the full pipeline:

```bash
bash process_video.sh your_video.mp4
```

Compare repeat runs on the same video and calibration; the velocity values should
agree to floating-point round-off.

---

## Cross-compiling (why we don't)

It is possible to cross-compile for aarch64 from x86-64, but it requires a full
sysroot with the target's `libgfortran`, plus careful handling of `-march` flags.
Given that a native build takes 1–3 minutes on the target board itself, the
cross-toolchain's maintenance cost buys nothing for this project. If you're building a
fleet of boards, cross-compilation may become worth it — but start native.
