# Solver patches — what we changed, and why

The Fortran solver in this repository is a **modified** copy of INRAE's
`Image_Velocimetry_Solver` (LGPL-3.0). We changed **4 of 33 source files**.

This document explains each change so that anyone — a reviewer, a future maintainer,
or someone trying to upstream the fix — can understand and reproduce it.

> **Quick orientation.** The solver produces 6 executables. Only two of them read
> images, and those two have **completely separate** image-reading functions in
> **separate files**. Changing one and forgetting the other is the single easiest
> mistake to make here; it produces a confusing `transf_a exit=24` error.

| Executable | Role | Image reader lives in | Function |
|---|---|---|---|
| `PIV.exe` | cross-correlation | `sub_PIV.f90` | `read_pgm_any` |
| `transf_a.exe` | orthorectification | `sub_transf_23D.f90` | `read_pgm_any_transf` |

---

## Patch 1 — P5 binary PGM support (the big one)

**Files:** `sub_PIV.f90`, `sub_transf_23D.f90`, `transf_23D.f90`

### The problem

`.pgm` images can be stored two ways:

| Form | Magic | Layout | Size (1089×591) | Read cost |
|---|---|---|---|---|
| **P2** | `P2` | ASCII — every pixel as decimal text | ~2.5 MB | **14.85 s / pair** |
| **P5** | `P5` | Binary — raw bytes | ~0.64 MB | **0.25 s / pair** |

Upstream only understands **P2**. The pixels are identical; P2 just spends most of its
time converting 640 000 numbers to text and back.

Since `lspiv_batch.py` generates the images itself, it can write them either way —
so the 59× penalty bought nothing.

### The fix

Both readers now **detect the format from the file's magic bytes** and handle either:

```fortran
! Read the 2-char magic, then branch.
!   "P2" -> existing ASCII path (kept, so old image sets still work)
!   "P5" -> new binary path
! Anything else -> error out rather than misparse.
```

`transf_23D.f90` also had to change: it passed a function pointer that pointed directly
at the old P2-only reader. It now points at the new auto-detecting one.

### Why it's safe

- **Auto-detection, not a mode switch.** The magic bytes decide. Feeding a P2 image
  still takes the P2 path, unchanged.
- **Verified byte-identical output.** The same image set converted to both P2 and P5
  produces **byte-for-byte identical** orthorectification and velocity output.
  Verification: `tools/solver-patches/` + the checks described in `docs/BUILDING.md`.
- **Old data still works.** Existing P2 image sets from previous runs are read as before.

> **If you revert this patch**, you must also tell the driver to emit P2:
> `--no-pgm-binary` (or `"pgm_binary": false` in `config.json`). Otherwise every
> orthorectification frame fails with `transf_a exit=24; output missing/empty`.

---

## Patch 2 — two uninitialised-variable defects (`sub_PIV.f90`)

**Files:** `sub_PIV.f90`

### The problem

Upstream's `sub_PIV.f90` has two variables that are not reset per grid point:

1. `sigma_m`, `sigma_n`, `aire` are never initialised for grid points that fall
   outside the valid region (~30 % of points in a typical run).
2. `summ_c`, `esperance_m`, `esperance_n` are initialised **outside** the grid loop
   instead of inside it, so values leak from one point into the next.

### Impact

These affect **columns 6–8 of `vel_raw` only** — the diagnostic columns
(`sigma_m`, `sigma_n`, `aire`).

**The velocity itself is unaffected.** Columns 1–5, and therefore all of `vel_real`
and every exported CSV value, do not read these variables. The practical symptom was
that `vel_raw` columns 6–8 changed between runs and depended on thread count, which
made regression-testing impossible.

### The fix

- Initialise `sigma_m` / `sigma_n` / `aire` to 0 before the loop.
- Move the `summ_c` / `esperance_m` / `esperance_n` assignments inside the loop.

### Verification

| Test | Result |
|---|---|
| Same input, run twice | **0 difference across all 9 columns** |
| Same input, 1 thread vs 4 threads | **0 difference across all 9 columns** |
| Columns 1–5 vs unpatched build | Numerically equivalent (max relative difference 1.3e-15, i.e. floating-point round-off) |

---

## Patch 3 — `PIV_param.dat` crash on even `Bi` (`sub_lspiv_parameter.f90`)

**Files:** `sub_lspiv_parameter.f90`

### The problem

`PIV_param.dat` line 2 holds `Bi`, the interpolation window size, which **must be odd**.
Upstream defends against an even value by auto-correcting it — incrementing `Bi` by 1
and writing the file back.

But the file is opened like this:

```fortran
open(newunit=lw, file=trim(param_file), status='old')   ! read-only!
```

...and the self-heal then tries to write to it. The run dies with:

```
Fortran runtime error: Cannot write to file opened for READ
```

→ `PIV.exe` exits with code 2, and the whole batch fails.

This is not an edge case: the sample calibration shipped with the Fudaa GUI uses
`Bi = 20`, which is even. So the tool crashed on the default example.

### The fix, in two places

1. **Source** — added `action='readwrite'` to the `open()` call, so the self-heal
   can actually write.
2. **Driver** — `lspiv_batch.py` normalises `Bi` to an odd value **once, before any
   worker starts** (`normalize_piv_param_bi()`).

The driver-side fix matters for more than convenience: the solver's self-heal happens
inside every worker process, so with parallel workers several processes could race to
rewrite the same file. Fixing it up front removes the race entirely.

---

## Reproducing the diff

`tools/solver-patches/upstream-original/` holds the **unmodified** versions of all 4
changed files. To see every change:

```bash
cd tools/solver-patches
for f in sub_PIV.f90 sub_transf_23D.f90 transf_23D.f90 sub_lspiv_parameter.f90; do
    echo "===== $f ====="
    diff -u "upstream-original/$f" "$f"
done
```

Or, if you have the upstream repository cloned:

```bash
git clone https://gitlab.irstea.fr/image_velocimetry/velocimetry_solver.git upstream
diff -ru upstream/sources tools/solver-patches
```

The durable project page is
https://riverhydraulics.riverly.inrae.fr/eng/tools/measurement-software/fudaa-lspiv.
`gitlab.irstea.fr` is scheduled to close on 30 June 2026.

---

## Verification commands

The build script verifies all patch markers before compiling, and refuses to proceed
if any are missing:

```bash
bash tools/arm/build_arm.sh
# expect:
#     [OK] sub_PIV.f90             -- P5 读图（PIV）
#     [OK] sub_transf_23D.f90      -- P5 读图（transf_a）
#     [OK] transf_23D.f90          -- 读图指针已切到新函数
#     [OK] sub_lspiv_parameter.f90 -- PIV_param.dat 可读写（Bi 自愈）
```

To confirm your build reproduces the reference numbers, run the worked example in
[`examples/`](../examples/) and compare against its recorded output.

---

## Upstreaming

These fixes would benefit upstream. Patch 3 in particular is a straightforward bug
(the default calibration crashes the solver), and Patch 2 is unambiguously a defect.

Patch 1 is a genuine feature change — upstream may prefer to keep P2-only for
compatibility, or may prefer a different implementation (e.g. an explicit flag rather
than magic-byte detection). If you approach upstream, note that the auto-detecting
approach was chosen precisely so that **existing P2 workflows are untouched**, which
should make it easy to accept.

Neither patch has been submitted upstream at the time of writing.
