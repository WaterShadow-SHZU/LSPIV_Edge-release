# Public release checklist

The repository may be published after the remaining checks below are complete.
This checklist covers the current working tree; it does not certify earlier Git
history or replace a legal review.

## Source and third-party components

- [x] Original work — the Python batch driver, shell and batch scripts, original
  build scripts, tests, and documentation — is licensed under the GNU GPL v3 or
  any later version (`LICENSE`; SPDX `GPL-3.0-or-later`).
- [x] Modified INRAE `Image_Velocimetry_Solver` sources, `tools/arm/makefile`, and
  the prebuilt Windows solver binaries are identified as LGPL-3.0 in `NOTICE`;
  source and license texts are included (`LICENSE.upstream`, `COPYING.LGPL`,
  `COPYING.GPL`, and `upstream-original/`).
- [x] FFmpeg and ffprobe binaries and their DLLs are not distributed in this
  repository. Users install them separately and must follow the terms of their
  chosen build.
- [x] Fudaa-LSPIV GUI files are not included. That GUI remains separate software
  under GPL-2.0.
- [x] `tools/solver-patches/kdtree2.f90` remains under the Academic Free
  License 1.1. The official text is
  `tools/solver-patches/LICENSE.kdtree2-AFL-1.1`. The root `LICENSE` covers
  original work and does not apply to `kdtree2.f90`. `NOTICE` records this.
- [ ] Before adding external code or binaries, record the source, exact version,
  applicable license, required notices, and corresponding source obligations.

## Data and history

- [x] Site-specific calibration files are not included; `calib/*.dat` is ignored.
- [x] Measurement videos and run outputs are not included.
- [x] Repository history begins with a cleaned snapshot and does not include
  earlier private history.
- [ ] Confirm that every example, screenshot, benchmark input, and output added
  for release is authorized for public distribution and does not identify a
  private site or person.

## Final review

- [ ] Review the exact commit and generated release archives, not only the
  working tree.
- [ ] Confirm all external binary licenses and notices are available to users.
- [ ] Obtain appropriate legal review for license questions before distribution.
