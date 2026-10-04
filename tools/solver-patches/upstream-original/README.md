# 上游原始文件备份（`../sources/` 的对照件）

这个目录保存的是 `../sources/` 里**被我们改过的 4 个文件的原版**。
它们取自上游开源代码（INRAE `Image_Velocimetry_Solver`），一字未改。

## 为什么要留着

`../sources/` 现在是**已经打好补丁**的版本——板子上编译（`arm/build_arm.sh`）用的就是它。
这里留一份原版，是为了：

1. 任何时候都能回答"我们到底改了什么"；
2. 需要退回纯上游行为时，把这里的文件拷回 `../sources/` 即可。

## 4 个文件分别改了什么

| 文件 | 原版的问题 | 我们的修改 |
|---|---|---|
| `sub_PIV.f90` | 只认 P2 文本图；另有两处统计量初始化缺陷 | 增加 P5 二进制读图；修 `sigma_m`/`sigma_n`/`aire` 未初始化、`summ_c`/`esperance_m`/`esperance_n` 未按点重置 |
| `sub_transf_23D.f90` | 只认 P2 文本图 | 增加 P5/P2 自适应读图（不修则 `transf_a` 报 `exit=24`） |
| `transf_23D.f90` | 读图指针指向只认 P2 的函数 | 改指向新的自适应读图函数 |
| `sub_lspiv_parameter.f90` | 以**只读**方式打开 `PIV_param.dat`，却又试图改写它 | 改成可读写（`Bi` 为偶数时会崩在只读句柄上） |

> 前三个是同一件事的两半：**P5 读图必须两个可执行文件都改**——
> `PIV` 的读图函数在 `sub_PIV.f90`，`transf_a` 的在 `sub_transf_23D.f90`。
> 只改一个，就会出现"PIV 能跑、正射全挂"或者相反。

## 怎么退回原版

```bash
cd ..                                   # 进到 velocimetry_solver-master/
cp sources_upstream_2024/*.f90 sources/
```

退回后**必须**改用 P2 文本模式，否则 `transf_a` 会因为读到 P5 而失败：

```bash
# 命令行
python3 lspiv_batch.py video <视频> --calib <校准> --no-pgm-binary
# 或壳脚本
PGMBIN=0 bash process_video.sh <视频> <校准>
```

退回纯上游的代价是**慢约 59 倍**（P2 文本每对约 14.85 s，P5 约 0.25 s），
所以这只用于对照排查，不要用于日常作业。
