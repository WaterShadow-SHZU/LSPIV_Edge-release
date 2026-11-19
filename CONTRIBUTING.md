# Contributing

Thanks for considering a contribution. This tool is used for real hydrology field
measurements, so correctness matters more than features — a wrong velocity number is
worse than a missing one.

---

## Ways to help

| | |
|---|---|
| **Bug reports** | Especially: a run that fails, or results that look wrong |
| **New examples** | Reproducible cases with data cleared for public release — see [examples/README.md](examples/README.md) |
| **ARM board reports** | Which board, how many cores, what `bench` says, what `--workers` you settled on |
| **Solver patches** | Upstream fixes in `tools/solver-patches/` |
| **Docs** | Clarifications, translations, corrections |

---

## Developing

**No build step, no dependencies.** The Python is standard-library only.

```bash
git clone https://github.com/WaterShadow-SHZU/LSPIV_Edge-release.git
cd LSPIV_Edge-release
python3 lspiv_batch.py --help
```

For the Fortran solver, see [docs/BUILDING.md](docs/BUILDING.md).

### Testing your change

Run the regression tests (stdlib `unittest`, no dependencies):

```bash
python3 -m unittest discover -s tests -v
```

Before opening a PR, please also do at least this:

```bash
# 1. Syntax
python3 -m py_compile lspiv_batch.py export_results.py preview_results.py
bash -n process_video.sh && bash -n export_csv.sh && bash -n tools/arm/build_arm.sh

# 2. Patch markers still present (if you touched the solver)
bash tools/arm/build_arm.sh    # expect 4x [OK]

# 3. Real run — nothing beats an end-to-end check
bash process_video.sh <a-short-video> ./calib
python3 export_results.py
```

**If your change could alter numerical output**, say so explicitly in the PR and
include a before/after comparison. The project's core invariant is that optimisations
must be **byte-identical**; verify that claim, don't assume it.

---

## The one rule that matters

> **Optimisations must not change results.**

Every speedup in this repository was verified byte-identical against the previous
implementation:

- P5 vs P2 image input → identical output
- Three frame-conversion fallback tiers → identical output
- Parallel vs serial conversion → identical output

If your change cannot satisfy this, it needs to be opt-in and documented.

---

## Changing the solver

`tools/solver-patches/` is a **modified copy of upstream code** (INRAE's
`Image_Velocimetry_Solver`, LGPL-3.0). Two obligations follow:

1. **Document the change** in [docs/SOLVER-PATCHES.md](docs/SOLVER-PATCHES.md) — what
   the upstream defect is, what you changed, how you verified it.
2. **Don't touch `upstream-original/`** — those files are the pristine reference that
   makes the diff reconstructible. They must stay byte-identical to upstream.

If you find a good fix, consider offering it upstream too. See the "Upstreaming"
section at the end of SOLVER-PATCHES.md.

---

## Code style

- **Python** — PEP 8, 4-space indent, type hints on function signatures. Docstrings
  explain *why*, not *what*; the code already says what.
- **Shell** — `set -euo pipefail`, quote expansions, comment non-obvious flags.
- **Fortran** — match the surrounding style; the upstream code is F90 with OpenMP
  pragmas guarded by `#ifdef openmp`.

Comments in this project are written in Chinese and English. Both are fine.

---

## Reporting a wrong result

Velocity output can be wrong in ways that don't throw errors. If you suspect results, include:

1. A video link and calibration files shared privately with maintainers; do not attach site data to a public issue unless you have permission
2. The command you ran
3. What you expected vs what you got, and how you know it's wrong
   (e.g. comparison with a current meter, or an obviously implausible magnitude)
4. Your `export/vel_real.csv`, shared privately if it contains site data

The sanity-check procedure in
[docs/GUIDE-zh.md](docs/GUIDE-zh.md) §四 is a good starting point.

---

## License

By contributing, you agree your contributions are licensed under the same terms as the
files you modify — GPL-3.0-or-later for the driver, documentation, tests, shell and
batch scripts, and the original build scripts; LGPL-3.0 for the solver sources and
for `tools/arm/makefile`. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
