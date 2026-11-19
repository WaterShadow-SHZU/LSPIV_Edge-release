# Changelog

Notable changes to `LSPIV_Edge`. Dates are in `YYYY-MM-DD`.

---

## [Unreleased] — first public release

Initial open-source release. The tool was developed as an internal batch driver for
Fudaa-LSPIV and is published here in a cleaned-up, self-contained form.

Original work — the Python batch driver, shell and batch scripts, original build
scripts, tests, and documentation — is released under the GNU General Public
License, version 3 or any later version (SPDX `GPL-3.0-or-later`; see `LICENSE`).
The Fortran solver in `tools/solver-patches/` and the prebuilt Windows binaries in
`bin/windows/` remain under the GNU Lesser General Public License, version 3.
FFmpeg is not bundled. The Fudaa-LSPIV GUI is not included and remains GPL-2.0.
Acknowledgements name EDF, INRAE, and DeltaCAD, the official Fudaa-LSPIV pages,
and the 2014 software citation together with the 2016 practical guide.
`kdtree2.f90` remains under the Academic Free License 1.1; the text is
`tools/solver-patches/LICENSE.kdtree2-AFL-1.1`.

### Added

- **Multi-frame export** (`export_results.py`, export schema 2) — besides the unchanged
  legacy `vel_raw.csv` / `vel_real.csv`, every export now also writes
  `export/vel_series.csv`, `export/frames_manifest.json` and
  `export/physics_twin_series.csv` (one `frame_id` per `vel_real` file, prefers `vel_real`,
  falls back to `vel_raw`). `--legacy-only` restores schema-1 behaviour;
  `--capabilities` prints a JSON feature probe without touching any data.
  Regression tests in `tests/` (`python3 -m unittest discover -s tests`).

- **Batch driver** (`lspiv_batch.py`) — runs the full chain without the GUI:
  video → frames → PGM → orthorectification → cross-correlation → CSV.
  Subcommands: `video`, `piv`, `vel-real`, `bench`, `make-coeff`.
- **Parallel frame conversion** — splits the frame list into up to 8 chunks and runs
  that many `ffmpeg` processes concurrently, each writing P5 directly via
  `-c:v pgm`. 935 frames: **~172 s → ~16 s**. Three-tier fallback for ffmpeg builds
  without the `pgm` encoder; all tiers verified byte-identical.
- **P5 binary PGM support in the solver** — the upstream ASCII ("P2") reader cost
  ~14.85 s per image pair. Auto-detecting P5/P2 readers cut that to **~0.25 s** (~59×),
  with byte-identical output. Both image-reading entry points patched.
- **`bench` subcommand** — measures process/thread scaling on your own machine and
  recommends `--workers`.
- **ARM build system** (`tools/arm/`) — native build on the target board, with a
  **pre-build patch guard** that refuses to compile a solver that cannot read P5
  images.
- **Windows build script** (`tools/build_windows.bat`) — rebuilds the solver from
  source with MSYS2/UCRT64.
- **Prebuilt Windows solver binaries** (`bin/windows/`). FFmpeg and ffprobe must be
  installed separately and available on `PATH`.
- **Documentation** — user guide (Chinese), solver patch rationale, build instructions,
  performance analysis, ARM deployment notes.

### Fixed

- **`sub_PIV.f90` non-reproducibility** — two uninitialised-variable defects made
  `vel_raw` columns 6–8 vary between runs and with thread count. Now identical across
  repeat runs and 1-vs-4 threads (0 difference, all 9 columns). Velocity columns were
  never affected.
- **`sub_lspiv_parameter.f90` crash on even `Bi`** — the solver opens `PIV_param.dat`
  read-only, then tries to rewrite it while self-correcting an even interpolation
  window. Upstream dies with `Fortran runtime error: Cannot write to file opened for
  READ`. The sample calibration shipped with the Fudaa GUI (`Bi = 20`) triggers this.
  Fixed in the source (`action='readwrite'`) and in the driver (forces an odd value
  once, before any worker starts, avoiding a multi-process write race).
- **`normalize_pgm` parsing overhead** — a fast path for row-aligned P2 data was gated
  behind a flag, so it was skipped for P2 input and the slow general parser ran
  instead. It consumed **62 % of transform time**. Ungating it: 0.335 → 0.070 s/frame,
  byte-identical.
- **Hardcoded `.exe` solver name** — one call site bypassed the platform-aware
  `solver_exe()` helper. Worked on Windows, failed on every ARM board. Fixed.

### Known limitations

- **`PIV_param.dat` layout is fixed.** `lire_PIV_param` hard-codes its read sequence,
  so it requires the file layout the Fudaa GUI produces *for this workflow*. Older
  layouts — including the one inside Fudaa's own `channel_test_case` example, which has
  10 extra lines — are **not** parsed and fail with
  `Bad integer for item 1 in list input` at `sub_lspiv_parameter.f90:144`.
  Regenerate the calibration from a current GUI session, or see
  [SOLVER-PATCHES.md](docs/SOLVER-PATCHES.md) for the layout the reader expects.
- **`transf_a` sporadically reports `exit=2`** under heavy CPU contention (e.g. very
  high `--workers`). Failures show empty stdout/stderr and a different frame each run,
  which is the signature of the process being killed externally. Not observed in
  normal runs. If you hit it, reduce `--workers`.
- End-to-end runs require a video and site calibration, which are not included.
- **Calibration still requires the GUI once per site.** This tool automates the
  repeat work, not the parameter decision.

---

## Notes on versioning

Up to the first public release this project had no version numbers; it was tracked by
date. From here on, the intent is:

- **Major** — a change that alters numerical output, or breaks a config/file format
- **Minor** — new capability, backwards compatible
- **Patch** — fixes with no behavioural change

Anything that changes results will be called out loudly in this file, because for this
tool a changed number is a changed measurement.
