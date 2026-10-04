# Public release checklist

The repository may be published after the remaining checks below are complete.
This checklist covers the current working tree; it does not certify earlier Git
history or replace a legal review.

## Source and third-party components

- [x] The project code is licensed under MIT (`LICENSE`).
- [x] Modified INRAE `Image_Velocimetry_Solver` sources and the prebuilt Windows
  solver binaries are identified as LGPL-3.0 in `NOTICE`; source and license texts
  are included.
- [x] FFmpeg and ffprobe binaries and their DLLs are not distributed in this
  repository. Users install them separately and must follow the terms of their
  chosen build.
- [x] Fudaa-LSPIV GUI files are not included.
- [ ] Before adding external code or binaries, record the source, exact version,
  applicable license, required notices, and corresponding source obligations.

## Data and history

- [x] Site-specific calibration files are not included; `calib/*.dat` is ignored.
- [x] Measurement videos and run outputs are not included.
- [x] The repository is a single snapshot commit; it carries no earlier Git
  history.
- [ ] Confirm that every example, screenshot, benchmark input, and output added
  for release is authorized for public distribution and does not identify a
  private site or person.

## Final review

- [ ] Review the exact commit and generated release archives, not only the
  working tree.
- [ ] Confirm all external binary licenses and notices are available to users.
- [ ] Obtain appropriate legal review for license questions before distribution.
