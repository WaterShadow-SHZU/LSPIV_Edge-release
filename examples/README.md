# Examples

No worked measurement case is included yet. This document describes the files and
checks needed when adding a reproducible example.

---

## Planned

| # | Case | Status |
|---|---|---|
| 01 | *(not included)* | planned |

---

## What a case should contain

A useful example is reproducible: someone cloning this repository should be able to
re-run it and get the same numbers. Add only data cleared for public release. Use
synthetic or anonymized calibration and results if sharing real site data is not
authorized.

```
examples/01-your-case-name/
├── README.md              ← REQUIRED: what this case is, and how to run it
├── calibration/           ← synthetic or public-release calibration files
│   ├── GRP.dat
│   ├── img_ref.dat
│   ├── PIV_param.dat
│   ├── grid.dat
│   └── h.dat
├── command.txt            ← exact command that produced the results
├── export/                ← the resulting CSVs  (tracked)
│   └── vel_real.csv
├── vel_real/              ← real-coordinate DAT files  (tracked)
├── preview.png            ← optional quiver plot, if you have matplotlib
└── video.md               ← link to the source video (do NOT commit the video)
```

### README.md template

```markdown
# Case 01 — <site name>

**Site:** <publicly shareable site description, or "synthetic">
**Date:** <yyyy-mm-dd>
**Camera:** <model, height above water, tilt>

## What this demonstrates

<One paragraph: e.g. "A straight reach with visible surface texture, showing a
well-behaved velocity field. Good first case to run.">

## Data

| File | Note |
|---|---|
| Video | <link> — 1920×1080, ~31 s, 30 fps |
| Calibration | `calibration/` — synthetic, anonymized, or explicitly cleared for release |

## How to run

```bash
# 1. Get the video (not committed — too large)
curl -L -o case01.mp4 "<url>"

# 2. Run
bash process_video.sh case01.mp4 ./calibration

# 3. Export
python3 export_results.py
```

## Expected result

| Metric | Value |
|---|---|
| Frames processed | 935 |
| Valid grid points | 70.3 % |
| Mean velocity | X.XX m/s |
| Runtime | ~2 min (12-core desktop) |

Compare your `export/vel_real.csv` against the committed one. Values should agree
to floating-point round-off.

## Notes

<Notes relevant to reproducing the case. Do not include private site or personal information.>
```

---

## What NOT to commit

| | Why |
|---|---|
| The video file | Tens to hundreds of MB; use a link |
| `frames/`, `img_pgm/`, `img_transf/` | Regenerable from the video, and large |
| `vel_raw/` | Per-frame intermediate output; bulky, rarely needed |
| `tmp/` | Scratch space |

The `.gitignore` at the repository root already excludes these.

### A note on calibration data

Committing your calibration files publishes your **measurement geometry** — ground
control points with real-world coordinates, the orthorectification extent, and the
water level. That is usually harmless (it's a public river, and the numbers are just
geometry), but think about it before committing, especially if the site is private
property or the survey was done under a permit.

Do not add real site calibration or measurement outputs without confirming that they
may be shared publicly. The required calibration files are listed in `calib/README.txt`.

---

## Adding a case

1. Run the pipeline on your data.
2. Create `examples/NN-short-name/`.
3. Copy in the calibration files, `vel_real/`, and `export/`.
4. Write `README.md` from the template above, and `command.txt` with the exact command.
5. Verify the case is reproducible **from a clean checkout** before committing:

```bash
cd examples/NN-short-name
bash ../../process_video.sh case01.mp4 ./calibration
diff -r export/ <your-recorded-results>/
```
