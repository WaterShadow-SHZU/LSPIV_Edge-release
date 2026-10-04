# Performance notes

Numbers below come from real runs: 935 frames of 1920×1080 video, an orthorectified
output of 1089×591, and a 128-point grid. The machine is a 12-core desktop
(4 performance + 4 efficiency + 4 more efficiency cores).

**Treat the proportions as transferable and the absolute values as machine-specific.**
Run `bench` to get numbers for your own hardware.

---

## Where the time goes

| Stage | Time | Share |
|---|---|---|
| Frame extraction (video → PNG). | ~30 s | — |
| **Frame conversion (PNG → PGM)** | **~16 s** | ~16 % |
| **Orthorectification (`transf_a`)** | **~40 s** | **~46 %** |
| Cross-correlation (`PIV`) | ~18 s | ~18 % |
| Real-coordinate conversion (`vel_real`) | ~12–16 s | ~15 % |
| **Total, excluding frame extraction** | **~85–99 s** | |
| **End to end, including extraction** | **~110–130 s** | |

After all optimisations, **orthorectification is the largest single cost** — not frame
conversion, which is where it used to be.

---

## Optimisation 1 — parallel frame conversion (172 s → 16 s)

### The problem

Converting 935 PNGs to PGM used to run on **one core**, despite a 12-core machine.
Two successive misdiagnoses were involved:

- **First attempt:** one `ffmpeg` process per frame. That's 935 process launches,
  serialised on one core.
- **Second attempt:** one `ffmpeg` process for the whole batch, using a concat
  demuxer. No more process-launch overhead — but still **one core**, because
  **a single ffmpeg decodes PNG single-threaded**. The bottleneck was never process
  startup; it was that one decoding thread.

### The fix

Split the frame list into up to 8 chunks, run 8 `ffmpeg` processes concurrently, and
have each write **P5 output directly** via ffmpeg's built-in `pgm` encoder:
`-c:v pgm`. Python never touches a pixel.

That last detail matters more than it looks: ffmpeg's `pgm` encoder emits
`P5\n<width> <height>\n255\n` with no comment lines, which is **byte-identical** to
the P5 header this project writes by hand. So letting ffmpeg write the file removes an
entire Python-side pass without changing a single byte of output.

### Results

| Approach | 935 frames |
|---|---|
| One ffmpeg per frame | ~172 s |
| One ffmpeg per batch | ~78 s |
| **8 ffmpeg processes, P5 direct** | **~16 s** |

Chunk-count scaling (48-frame sample):

| Chunks | 1 | 2 | 4 | **8** | 12 |
|---|---|---|---|---|---|
| s/frame | 0.087 | 0.045 | 0.028 | **0.023** | 0.026 |

Eight is the peak. The cap is `CONVERT_PARTS_CAP = 8`, deliberately **independent of
`config.json`'s `workers`** — this phase runs before the others, so it can use the whole
machine. `workers` governs only the orthorectification and PIV phases.

### Three-tier fallback

Not every ffmpeg build ships the `pgm` encoder. The driver tries, in order:

1. **Tier 1** — chunked parallel ffmpeg with `-c:v pgm` (fastest; the normal path).
2. **Tier 2** — chunked parallel decode to raw, then parallel Python PGM writing.
3. **Tier 3** — one ffmpeg per frame (slowest, but maximally compatible).

All three tiers were verified to produce **byte-identical** output, so a fallback costs
time, never correctness.

---

## Optimisation 2 — killing a 62 % parsing overhead

Before the P5 work, `normalize_pgm` was re-parsing `transf_a`'s P2 text output and
consuming **62 % of total transform time** (0.335 s vs 0.202 s of actual solving).

The reader had a fast path that handled row-aligned P2 data, but it was gated behind a
`binary` flag — so for P2 input it was skipped and the slow general parser ran instead.
Removing that gate made the fast path apply whenever the data was row-aligned:

| | s/frame |
|---|---|
| Before | 0.335 |
| **After** | **0.070** |

4.8× faster, output byte-identical.

---

## Why `workers = 4` and not more

More processes does **not** mean faster here. Measured on 48-frame transform batches:

| Processes | 1 | 2 | **4** | 6 | 8 | 12 |
|---|---|---|---|---|---|---|
| s/frame | 0.329 | 0.205 | **0.188** | 0.189 | 0.201 | 0.225 |

Four is the ceiling; eight and twelve are **slower** and start producing sporadic
failures. The bottleneck is `transf_a` contending for resources with itself — 1920×1080
source images resampled to 1089×591, which looks memory-bandwidth bound rather than
core-count bound.

**Leave `"workers": 4` in `config.json`.** On a different machine, measure first:

```bash
python3 lspiv_batch.py bench \
    --calib ./calib \
    --img-transf ./runs/<a-run>/img_transf \
    --pairs 1:24 --sweep 1,4,8,12
```

This reports per-setting timings and recommends a value. On battery-powered boards,
prefer 2.

At 4 processes the orthorectification phase achieves **3.96× parallel efficiency** —
essentially perfectly saturated.

---

## Reproducibility fix

`sub_PIV.f90` had two uninitialised-variable defects that made `vel_raw` columns 6–8
differ between runs and depend on thread count. Fixed — see
[SOLVER-PATCHES.md](SOLVER-PATCHES.md). After the fix, identical inputs give
**0 difference across all 9 columns** whether run twice or with 1 vs 4 threads.

The velocity columns (1–5, and therefore `vel_real` and every CSV) were never affected.

---

## Reproducing these numbers

```bash
# Full video run, timed per stage
python3 lspiv_batch.py video --exes ./bin/windows --calib ./calib --video your_video.mp4

# Just the frame conversion, isolated
python3 lspiv_batch.py video ... --stop-after-convert

# Thread/process scaling sweep
python3 lspiv_batch.py bench --calib ./calib --img-transf ./runs/<run>/img_transf \
    --pairs 1:24 --sweep 1,2,4,6,8,12
```

The staged timings in the first table came from instrumenting a full 935-frame run on a
second, independent run — the two agreed within the ranges quoted.
