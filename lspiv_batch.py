#!/usr/bin/env python3
"""Portable video -> image transform -> PIV -> velocity runner for Fudaa-LSPIV.

This wrapper does not contain or reimplement Fudaa's solvers; it invokes the
official executables supplied by the user in a local exes directory.
"""
from __future__ import annotations

import argparse
import concurrent.futures
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
IMAGE_RE = re.compile(r"^(.+?)_transf\.pgm$", re.IGNORECASE)
NUMBER_RE = re.compile(r"(\d+)")
CALIB_REQUIRED = ("GRP.dat", "img_ref.dat", "PIV_param.dat", "grid.dat", "h.dat")

# Solver executables, by base name. The extension is resolved per platform: the
# Windows builds ship as .exe and the Linux builds as .x, and the GUI itself
# already picks between the two the same way
# (PivExeLauncher: EXE_EXT = FuLib.isWindows() ? ".exe" : ".x").
SOLVER_NAMES = ("PIV", "transf_a", "vel_transf", "filter", "vel_scal", "ortho_plan",
                "verif_ortho", "gen_img_ref", "moy_ec", "moy_scal", "Q_compute",
                "bathy_compute", "manual_vel", "gen_mask", "stab_img")
# The solver extension to try first on this platform, then the other as fallback
# so a directory holding either layout works without configuration.
EXE_EXT = ".exe" if os.name == "nt" else ".x"


def solver_exe(exes: Path, name: str, required: bool = True) -> Path:
    """Resolve a solver executable in ``exes``, accepting either extension.

    Tries the platform's native extension first, then the other one, so the same
    run directory works whether it was populated from the Windows package or
    from a Linux/ARM build. Returns a non-existent path when nothing matches, so
    callers can keep raising their own FileNotFoundError with a useful message.
    """
    other = ".x" if EXE_EXT == ".exe" else ".exe"
    for ext in (EXE_EXT, other):
        candidate = exes / f"{name}{ext}"
        if candidate.is_file():
            return candidate
    if not required:
        return exes / f"{name}{EXE_EXT}"
    looked = ", ".join(f"{name}{ext}" for ext in (EXE_EXT, other))
    raise FileNotFoundError(
        f"{name} solver not found in {exes} (looked for {looked}); "
        f"build the solver for this platform or point --exes at the right directory")


def solver_exe_optional(exes: Path, name: str) -> Path | None:
    """Like solver_exe but returns None instead of raising when absent."""
    for ext in (EXE_EXT, ".x" if EXE_EXT == ".exe" else ".exe"):
        candidate = exes / f"{name}{ext}"
        if candidate.is_file():
            return candidate
    return None


def natural_key(path: Path) -> tuple[Any, ...]:
    return tuple(int(part) if part.isdigit() else part.lower() for part in NUMBER_RE.split(path.name))


def load_config() -> dict[str, Any]:
    path = SCRIPT_DIR / "config.json"
    if not path.is_file():
        return {}
    try:
        # utf-8-sig tolerates the byte order mark that Windows editors add,
        # which would otherwise make json.loads fail on a copied config file.
        data = json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError(f"cannot read {path}: {exc}") from exc
    if not isinstance(data, dict):
        raise ValueError(f"config must be a JSON object: {path}")
    return data


# Solver directories shipped by this repository, probed in this order when the
# configured one is missing. The order is platform-dependent because a release
# checkout contains BOTH layouts: bin/windows/*.exe and tools/arm/exes_arm/*.x.
# Picking the wrong one is only detected much later (the .exe files simply will
# not execute here), so we prefer the layout that matches this host first.
EXES_SEARCH_ORDER = (
    ("bin/windows", "tools/arm/exes_arm", "exes")
    if os.name == "nt"
    else ("tools/arm/exes_arm", "exes", "bin/windows")
)


def _has_native_solver(path: Path) -> bool:
    """True when ``path`` holds solver binaries using this host's extension.

    Deliberately checks only the *native* extension: on ARM, bin/windows does
    contain PIV.exe, and accepting it would pick a directory that cannot run.
    """
    return (path / f"PIV{EXE_EXT}").is_file()


def resolve_exes(value: str | None, config: dict[str, Any]) -> Path:
    """Locate the solver binaries.

    An explicit ``--exes`` always wins. Otherwise ``exes_dir`` from config.json
    is used, and when that directory is absent we probe the layouts this
    repository ships, so a fresh checkout works on Windows and ARM alike without
    hand-editing config.json.
    """
    if value:
        return Path(value).expanduser().resolve()
    configured = config.get("exes_dir")
    missing: Path | None = None
    if configured:
        path = Path(str(configured)).expanduser()
        resolved = (SCRIPT_DIR / path).resolve() if not path.is_absolute() else path.resolve()
        if resolved.is_dir():
            return resolved
        missing = resolved
    for candidate in EXES_SEARCH_ORDER:
        probe = (SCRIPT_DIR / candidate).resolve()
        if _has_native_solver(probe):
            if missing is not None:
                print(
                    f"[info] exes_dir {missing} 不存在，自动改用 {probe}",
                    file=sys.stderr,
                )
            return probe
    # Nothing matched: hand back the configured path (or the historical default)
    # so the caller's error message points at what the user asked for.
    return missing if missing is not None else (SCRIPT_DIR / "exes").resolve()


def effective_workers(value: int | None, config: dict[str, Any], default: int | None = None) -> int:
    selected = value if value is not None else config.get("workers", default or (os.cpu_count() or 1))
    try:
        return max(1, int(selected))
    except (TypeError, ValueError) as exc:
        raise ValueError(f"workers must be an integer, got {selected!r}") from exc


def effective_keep(value: bool | None, config: dict[str, Any]) -> bool:
    return bool(config.get("keep_workdirs", False) if value is None else value)


def effective_pgm_binary(value: bool | None, config: dict[str, Any]) -> bool:
    """Whether to write P5 (binary) images for the solver.

    Default is True because it is both faster and smaller, but it requires a
    solver built with the P5-capable reader. Set ``pgm_binary: false`` in
    config.json - or pass ``--pgm-binary/--no-pgm-binary`` - to fall back to the
    P2 text images that older solver builds expect.
    """
    return bool(config.get("pgm_binary", True) if value is None else value)


SOLVER_MODES = ("auto", "process", "openmp", "hybrid")
# The OpenMP builds of PIV and transf_a read the thread count with '(i2)',
# so anything above 99 cannot be expressed.
MAX_SOLVER_THREADS = 99
# Two sweep points closer than this count as a tie in bench, so that normal
# run-to-run jitter does not turn into advice to give up cores.
BENCH_NOISE = 0.08
# The single-pair thread probe needs more than one pair and more than one
# repeat: a two-pair, three-repeat probe on a busy desktop swings by 2x.
BENCH_PROBE_PAIRS = 4
BENCH_PROBE_REPEATS = 4
# auto only hands the leftover cores to native threads when each solver would
# get at least this many. Below it the extra threads cost more than they save.
AUTO_THREAD_FLOOR = 4
# Repeats for the filesystem probe in bench. Five is enough: the numbers it
# reports differ by orders of magnitude, not by percent.
BENCH_FS_REPEATS = 5


def effective_mode(value: str | None, config: dict[str, Any]) -> str:
    selected = (value or config.get("solver_mode") or "auto").strip().lower()
    if selected not in SOLVER_MODES:
        raise ValueError(f"mode must be one of {', '.join(SOLVER_MODES)}, got {selected!r}")
    return selected


def effective_solver_threads(value: int | None, config: dict[str, Any]) -> int:
    selected = value if value is not None else config.get("solver_threads", 1)
    try:
        return max(1, min(MAX_SOLVER_THREADS, int(selected)))
    except (TypeError, ValueError) as exc:
        raise ValueError(f"solver threads must be an integer, got {selected!r}") from exc


def effective_budget(value: int | None, config: dict[str, Any]) -> int:
    selected = value if value is not None else config.get("cpu_budget", os.cpu_count() or 1)
    try:
        return max(1, int(selected))
    except (TypeError, ValueError) as exc:
        raise ValueError(f"cpu budget must be an integer, got {selected!r}") from exc


def resolve_plan(mode: str, workers: int, threads: int, budget: int, pair_count: int,
                 threads_given: bool = False) -> tuple[int, int, str]:
    """Decide how to spend the CPU budget: how many solver processes, how many
    native threads each, and why.

    The solver exposes two knobs:
      * run N copies of the executable, one per image pair (process parallelism)
      * pass a thread count so OpenMP parallelises the grid loop inside one run
    Per-pair cost is ``a + c/T`` (a = launch + image I/O, c = the correlation
    kernel). Over a batch of N pairs that makes the total ``N*(a*T + c)/budget``,
    which is minimised at T = 1: threading one pair shortens that pair but
    shortens the batch not at all. Native threads only pay off for the leftover
    cores when there are fewer pairs than cores.
    """
    budget = max(1, budget)
    pair_count = max(1, pair_count)
    if mode == "process":
        spawned = max(1, min(workers, pair_count, budget))
        return spawned, 1, "one single-threaded solver per pair"
    if mode == "openmp":
        # Asking for one process only makes sense with real threads, so fall
        # back to the whole budget when the user did not name a thread count.
        per_solver = max(1, min(threads if threads_given else budget, budget))
        return 1, per_solver, "one solver process using native threads"
    if mode == "hybrid":
        per_solver = max(1, min(threads, budget))
        spawned = max(1, min(workers, budget // per_solver, pair_count))
        return spawned, per_solver, f"{spawned} solver processes x {per_solver} native threads"
    # auto: fill the budget with pairs first. Threading a solver only wins when
    # it would otherwise sit mostly idle, because concurrent processes fight
    # over the same files; measured on a 4+4+4 machine, six 2-thread solvers
    # were ~20% slower than six 1-thread ones.
    spawned = max(1, min(workers, pair_count, budget))
    leftover = max(1, budget // spawned)
    if threads_given and threads > 1:
        per_solver = max(1, min(threads, leftover))
        return spawned, per_solver, f"pairs first, {per_solver} native threads per process as requested"
    if leftover >= AUTO_THREAD_FLOOR:
        return spawned, leftover, f"few pairs, so leftover cores go out as {leftover} native threads per process"
    return spawned, 1, "pairs first; too few leftover cores for native threads to be worth it"


def parse_pairs(value: str | None, count: int) -> list[int]:
    if not value:
        return list(range(1, max(0, count)))
    match = re.fullmatch(r"\s*(\d+)\s*:\s*(\d+)\s*", value)
    if not match:
        raise ValueError("--pairs must use inclusive 1-based START:END, e.g. 1:3")
    start, end = (int(x) for x in match.groups())
    if start < 1 or end < start or end >= count:
        raise ValueError(f"pair range {value!r} is invalid for {count} images (valid pairs: 1:{max(0, count - 1)})")
    return list(range(start, end + 1))


def image_files(img_dir: Path) -> list[Path]:
    if not img_dir.is_dir():
        raise FileNotFoundError(f"image directory not found: {img_dir}")
    files = [p for p in img_dir.iterdir() if p.is_file() and IMAGE_RE.match(p.name)]
    files.sort(key=natural_key)
    empty = [p for p in files if p.stat().st_size == 0]
    if empty:
        raise ValueError("source image is empty (0 bytes): " + ", ".join(map(str, empty)))
    if len(files) < 2:
        raise FileNotFoundError(f"need at least two *_transf.pgm files in {img_dir}")
    return files


def validate_common(exes: Path, calib: Path, img_transf: Path) -> tuple[Path, list[Path]]:
    piv_exe = solver_exe(exes, "PIV")
    for name in ("PIV_param.dat", "grid.dat"):
        if not (calib / name).is_file():
            raise FileNotFoundError(f"calibration file not found: {calib / name}")
    return piv_exe, image_files(img_transf)


def _copy_calib(calib: Path, destination: Path) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    for item in calib.iterdir():
        if item.is_file():
            shutil.copy2(item, destination / item.name)


def count_grid_points(calib: Path) -> int:
    """Number of points in grid.dat, i.e. the trip count of the OpenMP loop.

    sub_PIV distributes it with ``schedule(static, compt/omp_get_num_threads())``.
    If the thread count exceeds the grid point count that chunk size becomes
    zero, which the OpenMP runtime rejects and PIV.exe exits with code 3.
    """
    path = calib / "grid.dat"
    if not path.is_file():
        return 0
    count = 0
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        stripped = line.strip()
        if stripped and not stripped.startswith("#"):
            count += 1
    return count


def clamp_threads(threads: int, work_items: int, what: str) -> int:
    """Keep the OpenMP thread count inside the range the solver can accept."""
    if work_items <= 0:
        return 1
    if threads > work_items:
        print(f"Note: capping native threads at {work_items} because only {work_items} {what} "
              f"are available (the solver rejects a thread count above the work item count)")
        return work_items
    return threads


def ensure_coeff(calib: Path, exes: Path, work_root: Path) -> Path:
    """Ensure coeff.dat exists, generating it from GRP.dat when necessary."""
    target = calib / "coeff.dat"
    if target.is_file() and target.stat().st_size > 0:
        return target
    grp = calib / "GRP.dat"
    if not grp.is_file() or grp.stat().st_size == 0:
        raise FileNotFoundError(f"GRP.dat is required to generate coeff.dat: {grp}")
    ortho = solver_exe(exes, "ortho_plan")
    temp_parent = work_root / "tmp"
    temp_parent.mkdir(parents=True, exist_ok=True)
    temp_dir = Path(tempfile.mkdtemp(prefix="coeff_", dir=str(temp_parent)))
    try:
        outputs = temp_dir / "outputs.dir"
        outputs.mkdir()
        shutil.copy2(grp, outputs / "GRP.dat")
        result = subprocess.run([str(ortho)], cwd=str(temp_dir), capture_output=True,
                                text=True, encoding="utf-8", errors="replace", check=False)
        if result.returncode != 0:
            detail = (result.stderr or result.stdout or "").strip()[-2000:]
            raise RuntimeError(f"ortho_plan.exe failed with exit code {result.returncode}: {detail}")
        generated = outputs / "coeff.dat"
        if not generated.is_file() or generated.stat().st_size == 0:
            detail = (result.stdout or result.stderr or "").strip()[-2000:]
            raise RuntimeError(f"ortho_plan.exe returned success but outputs.dir/coeff.dat is missing or empty: {detail}")
        shutil.copy2(generated, target)
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)
    print("Generated coeff.dat from GRP.dat via ortho_plan.exe")
    return target


def normalize_piv_param_bi(calib: Path) -> int | None:
    """Force the interpolation window in PIV_param.dat to an odd number.

    ``lire_PIV_param`` requires an odd ``Bi`` and, when it reads an even one,
    tries to bump it and rewrite the file in place. It opens that file with
    ``status='old'`` (read-only), so the write aborts the whole process:

        At line 162 of file sub_lspiv_parameter.f90
        Fortran runtime error: Cannot write to file opened for READ

    That is an upstream defect. Fixing it properly needs a rebuild, so the
    driver also removes the trigger: correct the value once, here, before any
    worker starts. Doing it centrally also avoids the race where several workers
    try to rewrite the same file at the same time.

    Returns the new value when a change was made, else None.
    """
    path = calib / "PIV_param.dat"
    if not path.is_file():
        return None
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return None
    lines = text.splitlines(keepends=True)
    if len(lines) < 2:
        return None
    # Line 2 holds Bi: the file starts with a "# FileVersion ..." comment line.
    body = lines[1].strip()
    if not body.isdigit():
        return None
    value = int(body)
    if value % 2 == 1:
        return None
    replacement = value + 1
    newline = "\n" if lines[1].endswith("\n") else ""
    lines[1] = f"{replacement}{newline}"
    try:
        path.write_text("".join(lines), encoding="utf-8")
    except OSError:
        return None
    print(f"Note: Bi in PIV_param.dat was {value} (even); corrected to {replacement} "
          f"(the solver requires an odd interpolation window)")
    return replacement


def prepare_resolved_calib(calib: Path, out_root: Path) -> Path:
    """Copy user calibration into the run so generated files never alter calib."""
    resolved = out_root / "resolved_calib"
    if resolved.exists():
        shutil.rmtree(resolved)
    _copy_calib(calib, resolved)
    # Do this after the copy so the user's own calibration files stay untouched,
    # and before any worker runs so none of them hits the solver's write-on-
    # read-only-unit abort.
    normalize_piv_param_bi(resolved)
    return resolved


def save_instant_results_list(raw_files: list[Path], destination: Path) -> None:
    """Write the instant raw-result names expected by Fudaa post-processors."""
    destination.write_text("".join(f"{item.name}\n" for item in raw_files), encoding="utf-8")


def saveInstantResultsList(raw_files: list[Path], destination: Path) -> None:
    """Compatibility spelling for callers referring to the GUI operation by name."""
    save_instant_results_list(raw_files, destination)


def _run_pair(job: tuple[str, str, str, str, str, int, int]) -> dict[str, Any]:
    piv_exe_s, calib_s, image_a_s, image_b_s, out_root_s, index, threads = job
    piv_exe, calib = Path(piv_exe_s), Path(calib_s)
    image_a, image_b, out_root = Path(image_a_s), Path(image_b_s), Path(out_root_s)
    # One workdir per worker process, reused for every pair it handles. PIV only
    # ever writes vel_raw/piv.dat and the result is moved straight out, so
    # overwriting the two images in place gives the same input state as building
    # a fresh tree - without deleting anything per pair. That matters because a
    # deletion is the most expensive filesystem call in this loop (antivirus and
    # cloud-sync filters hook it), while a plain overwrite is cheap.
    workdir = out_root / "tmp" / f"worker_{os.getpid()}"
    started = time.perf_counter()
    try:
        (workdir / "outputs.dir").mkdir(parents=True, exist_ok=True)
        (workdir / "img_transf").mkdir(exist_ok=True)
        (workdir / "vel_raw").mkdir(exist_ok=True)
        shutil.copyfile(calib / "PIV_param.dat", workdir / "outputs.dir" / "PIV_param.dat")
        shutil.copyfile(calib / "grid.dat", workdir / "outputs.dir" / "grid.dat")
        shutil.copyfile(image_a, workdir / "img_transf" / "image1_transf.pgm")
        shutil.copyfile(image_b, workdir / "img_transf" / "image2_transf.pgm")
        # Only reachable when an earlier pair of this same worker failed and left
        # its output behind. PIV opens piv.dat with status='unknown', so a
        # shorter new result would keep the stale tail of the longer old one -
        # and if the file is still held open the solver dies with "Cannot write
        # to file opened for READ". Truncate in place instead of deleting: a
        # delete can be blocked (by antivirus, cloud-sync filters, or a policy
        # layer) whereas opening for write and closing again is allowed far more
        # often, and it leaves the zero-length file PIV expects to find.
        stale = workdir / "vel_raw" / "piv.dat"
        if stale.exists():
            try:
                with stale.open("wb"):
                    pass
            except OSError:
                try:
                    stale.unlink()
                except OSError:
                    pass
        # The OpenMP builds read the thread count as their first argument. A
        # sequential build ignores it, so only pass it when it is meaningful.
        command = [str(piv_exe)] + ([str(threads)] if threads > 1 else [])
        solver_started = time.perf_counter()
        result = subprocess.run(command, cwd=str(workdir), capture_output=True,
                                text=True, encoding="utf-8", errors="replace", check=False)
        # Time spent inside the solver alone. ``elapsed`` below also covers the
        # workdir setup and the result move, which on Windows can be inflated by
        # antivirus and are useless for judging thread scaling.
        solver_elapsed = time.perf_counter() - solver_started
        stdout, stderr = result.stdout or "", result.stderr or ""
        if result.returncode != 0 or "error termination" in (stdout + stderr).lower():
            (workdir / "stdout.txt").write_text(stdout, encoding="utf-8")
            (workdir / "stderr.txt").write_text(stderr, encoding="utf-8")
            message = f"PIV.exe exit code {result.returncode}" if result.returncode != 0 else "PIV.exe reported error termination"
            return {"index": index, "ok": False, "elapsed": time.perf_counter() - started,
                    "solver": solver_elapsed, "message": message, "workdir": str(workdir)}
        piv_file = workdir / "vel_raw" / "piv.dat"
        if not piv_file.is_file() or piv_file.stat().st_size == 0:
            (workdir / "stdout.txt").write_text(stdout, encoding="utf-8")
            (workdir / "stderr.txt").write_text(stderr, encoding="utf-8")
            return {"index": index, "ok": False, "elapsed": time.perf_counter() - started,
                    "solver": solver_elapsed,
                    "message": "PIV.exe succeeded but vel_raw/piv.dat is missing or empty", "workdir": str(workdir)}
        destination = out_root / "vel_raw" / f"piv{index:04d}.dat"
        destination.parent.mkdir(parents=True, exist_ok=True)
        # os.replace is a rename: it overwrites a previous result of the same
        # name without a delete, and it keeps the workdir free of piv.dat so the
        # next pair starts from a clean slate.
        os.replace(piv_file, destination)
        elapsed = time.perf_counter() - started
        return {"index": index, "ok": True, "elapsed": elapsed, "solver": solver_elapsed,
                "message": str(destination), "workdir": str(workdir)}
    except Exception as exc:
        workdir.mkdir(parents=True, exist_ok=True)
        (workdir / "error.txt").write_text(repr(exc), encoding="utf-8")
        return {"index": index, "ok": False, "elapsed": time.perf_counter() - started,
                "solver": None, "message": f"{type(exc).__name__}: {exc}", "workdir": str(workdir)}


def run_piv(args: argparse.Namespace, out: Path | None = None, workers: int | None = None,
            threads: int | None = None, mode: str | None = None,
            quiet: bool = False) -> dict[str, Any]:
    config = getattr(args, "_config", load_config())
    exes = resolve_exes(getattr(args, "exes", None), config)
    calib = Path(args.calib).expanduser().resolve()
    if not getattr(args, "img_transf", None):
        raise ValueError("piv needs --img-transf, or a .\\img_transf folder")
    img_transf = Path(args.img_transf).expanduser().resolve()
    out_root = (out or Path(args.out).expanduser()).resolve()
    piv_exe, images = validate_common(exes, calib, img_transf)
    # A direct `piv` run may point at a calibration directory that did not come
    # through prepare_resolved_calib. Normalise Bi before any worker starts, so
    # the solver's read-only-unit rewrite can never fire mid-batch.
    normalize_piv_param_bi(calib)
    indexes = parse_pairs(args.pairs, len(images))
    out_root.mkdir(parents=True, exist_ok=True)
    (out_root / "vel_raw").mkdir(exist_ok=True)
    (out_root / "tmp").mkdir(exist_ok=True)
    selected_workers = workers if workers is not None else getattr(args, "workers", None)
    requested_workers = effective_workers(selected_workers, config, default=os.cpu_count() or 1)
    cli_threads = threads if threads is not None else getattr(args, "solver_threads", None)
    # Distinguish "1 because that is the default" from "1 because the user said
    # so": openmp mode has to widen the default to the whole budget.
    threads_given = cli_threads is not None or "solver_threads" in config
    requested_threads = effective_solver_threads(cli_threads, config)
    selected_mode = effective_mode(
        mode if mode is not None else getattr(args, "mode", None), config)
    budget = effective_budget(getattr(args, "cpu_budget", None), config)
    max_workers, per_solver_threads, plan_note = resolve_plan(
        selected_mode, requested_workers, requested_threads, budget, len(indexes),
        threads_given=threads_given)
    per_solver_threads = clamp_threads(per_solver_threads, count_grid_points(calib), "grid points")
    keep = effective_keep(getattr(args, "keep_workdirs", None), config)
    jobs = [(str(piv_exe), str(calib), str(images[i - 1]), str(images[i]), str(out_root), i,
             per_solver_threads) for i in indexes]
    if not quiet:
        print(f"PIV plan: mode={selected_mode} ({plan_note}); "
              f"processes={max_workers} x threads={per_solver_threads} "
              f"(cpu budget {budget}, {len(indexes)} pairs)")
    started = time.perf_counter()
    results: list[dict[str, Any]] = []
    with concurrent.futures.ProcessPoolExecutor(max_workers=max_workers) as pool:
        futures = [pool.submit(_run_pair, job) for job in jobs]
        for future in concurrent.futures.as_completed(futures):
            result = future.result()
            results.append(result)
            if not quiet:
                print(f"[{('OK' if result['ok'] else 'FAIL')}] pair {result['index']:04d} {result['elapsed']:.2f}s: {result['message']}")
    results.sort(key=lambda item: item["index"])
    elapsed = time.perf_counter() - started
    failed = [item for item in results if not item["ok"]]
    if not failed and not keep:
        # One deletion per run instead of one per pair. The worker workdirs hold
        # the images of the last pair each worker handled, which is only worth
        # keeping when something actually failed.
        shutil.rmtree(out_root / "tmp", ignore_errors=True)
    if not quiet:
        print(f"PIV finished: {len(results) - len(failed)}/{len(results)} pairs, "
              f"processes={max_workers}, threads={per_solver_threads}, wall={elapsed:.2f}s")
        if failed:
            print("Failed workdirs kept for diagnosis:")
            for item in failed:
                print(f"  pair {item['index']:04d}: {item['workdir']}")
    return {"results": results, "elapsed": elapsed, "workers": max_workers,
            "threads": per_solver_threads, "mode": selected_mode, "out": out_root}


def run_vel_real(args: argparse.Namespace) -> int:
    config = getattr(args, "_config", load_config())
    exes = resolve_exes(getattr(args, "exes", None), config)
    calib = Path(args.calib).expanduser().resolve()
    out_root = Path(args.out).expanduser().resolve()
    exe = solver_exe(exes, "vel_transf")
    raw_files = sorted((out_root / "vel_raw").glob("piv*.dat"), key=natural_key)
    if not raw_files:
        raise FileNotFoundError(f"no PIV results found in {out_root / 'vel_raw'}; run piv first")
    if not (calib / "PIV_param.dat").is_file() or not (calib / "img_ref.dat").is_file():
        raise FileNotFoundError(f"vel-real needs PIV_param.dat and img_ref.dat in {calib}")
    workdir = out_root / "tmp" / "vel_real_work"
    if workdir.exists():
        shutil.rmtree(workdir)
    (workdir / "outputs.dir").mkdir(parents=True)
    (workdir / "vel_raw").mkdir()
    (workdir / "vel_real").mkdir()
    _copy_calib(calib, workdir / "outputs.dir")
    save_instant_results_list(raw_files, workdir / "outputs.dir" / "list_avg.dat")
    for item in raw_files:
        shutil.copy2(item, workdir / "vel_raw" / item.name)
    started = time.perf_counter()
    result = subprocess.run([str(exe)], cwd=str(workdir), capture_output=True, text=True, encoding="utf-8", errors="replace", check=False)
    (workdir / "stdout.txt").write_text(result.stdout or "", encoding="utf-8")
    (workdir / "stderr.txt").write_text(result.stderr or "", encoding="utf-8")
    if result.returncode != 0:
        print(f"vel_transf.exe failed with exit code {result.returncode}; workdir kept: {workdir}")
        return result.returncode or 1
    produced, destination = workdir / "vel_real", out_root / "vel_real"
    if produced.is_dir():
        if destination.exists():
            shutil.rmtree(destination)
        shutil.copytree(produced, destination)
    else:
        print("Warning: vel_transf.exe returned success but no vel_real directory was found")
    if not effective_keep(getattr(args, "keep_workdirs", None), config):
        shutil.rmtree(workdir, ignore_errors=True)
    print(f"vel-real finished in {time.perf_counter() - started:.2f}s; output: {destination}")
    return 0


def run_filter(args: argparse.Namespace, out_root: Path, calib: Path, exes: Path) -> bool:
    """Run optional GUI-equivalent filtering over all collected instantaneous PIV files."""
    raw_files = sorted((out_root / "vel_raw").glob("piv*.dat"), key=natural_key)
    if not raw_files:
        print(f"Skipping filter: no raw results in {out_root / 'vel_raw'}")
        return False
    requested = getattr(args, "filter_enabled", None)
    filters_file = calib / "filters.dat"
    if requested is False or (requested is not True and not filters_file.is_file()):
        if requested is not False and not filters_file.is_file():
            print("Skipping filter: filters.dat is not present in calib")
        return False
    if not filters_file.is_file():
        print("Skipping filter: filters.dat is not present in calib")
        return False
    filter_exe = solver_exe_optional(exes, "filter")
    if filter_exe is None:
        print(f"Warning: filter solver not found in {exes}; skipping filter")
        return False
    workdir = out_root / "tmp" / "filter_work"
    if workdir.exists():
        shutil.rmtree(workdir)
    (workdir / "outputs.dir").mkdir(parents=True)
    (workdir / "vel_raw").mkdir()
    (workdir / "vel_filter").mkdir()
    _copy_calib(calib, workdir / "outputs.dir")
    save_instant_results_list(raw_files, workdir / "outputs.dir" / "list_avg.dat")
    for item in raw_files:
        shutil.copy2(item, workdir / "vel_raw" / item.name)
    result = subprocess.run([str(filter_exe)], cwd=str(workdir), capture_output=True,
                            text=True, encoding="utf-8", errors="replace", check=False)
    (workdir / "stdout.txt").write_text(result.stdout or "", encoding="utf-8")
    (workdir / "stderr.txt").write_text(result.stderr or "", encoding="utf-8")
    if result.returncode != 0:
        print(f"Warning: filter.exe failed with exit code {result.returncode}; raw results kept")
        if not effective_keep(getattr(args, "keep_workdirs", None), getattr(args, "_config", load_config())):
            shutil.rmtree(workdir, ignore_errors=True)
        return False
    vel_scal = solver_exe_optional(exes, "vel_scal")
    if vel_scal is not None:
        scaled = subprocess.run([str(vel_scal)], cwd=str(workdir), capture_output=True,
                                text=True, encoding="utf-8", errors="replace", check=False)
        (workdir / "vel_scal_stdout.txt").write_text(scaled.stdout or "", encoding="utf-8")
        (workdir / "vel_scal_stderr.txt").write_text(scaled.stderr or "", encoding="utf-8")
        if scaled.returncode != 0:
            print(f"Warning: vel_scal.exe failed with exit code {scaled.returncode}; keeping filter output")
    destination = out_root / "vel_filter"
    filter_dirs = [workdir / "vel_filter", workdir / "outputs.dir" / "vel_filter"]
    source = next((item for item in filter_dirs if item.is_dir() and any(child.is_file() for child in item.iterdir())), None)
    loose_filter_files = [item for item in workdir.rglob("filter_piv*.dat") if item.is_file()]
    if source is None and loose_filter_files:
        destination.mkdir(parents=True, exist_ok=True)
        for item in loose_filter_files:
            shutil.copy2(item, destination / item.name)
        source = destination
    elif source is not None:
        if destination.exists():
            shutil.rmtree(destination)
        shutil.copytree(source, destination)
    mask_destination = out_root / "filter_mask"
    mask_sources = [workdir / "filter_mask", workdir / "outputs.dir" / "filter_mask"]
    mask_files = []
    for source_dir in mask_sources:
        if source_dir.is_dir():
            mask_files.extend(item for item in source_dir.iterdir() if item.is_file())
    outputs = workdir / "outputs.dir"
    mask_files.extend(item for item in outputs.rglob("*") if item.is_file() and ("mask" in item.stem.lower() or item.name.lower().endswith("_fmask.dat")))
    if mask_files:
        mask_destination.mkdir(parents=True, exist_ok=True)
        for item in mask_files:
            shutil.copy2(item, mask_destination / item.name)
    if source is None:
        print("Warning: filter.exe returned success but no vel_filter output was found")
    else:
        print(f"Filter finished; output: {destination}")
    if mask_files:
        print(f"Filter masks copied to: {mask_destination}")
    if not effective_keep(getattr(args, "keep_workdirs", None), getattr(args, "_config", load_config())):
        shutil.rmtree(workdir, ignore_errors=True)
    return source is not None


def parse_img_ref_size(calib: Path) -> tuple[int, int] | None:
    path = calib / "img_ref.dat"
    if not path.is_file():
        return None
    pairs: list[tuple[int, int]] = []
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        match = re.match(r"^\s*(\d+)\s+(\d+)\s*$", line)
        if match:
            pairs.append((int(match.group(1)), int(match.group(2))))
    if not pairs:
        return None
    height, width = pairs[-1]
    return width, height


def parse_piv_interval(calib: Path) -> float | None:
    path = calib / "PIV_param.dat"
    if not path.is_file():
        return None
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    for index, line in enumerate(lines):
        if "time interval" in line.lower() and index + 1 < len(lines):
            match = re.search(r"[-+]?\d+(?:\.\d*)?(?:[eE][-+]?\d+)?", lines[index + 1])
            if match:
                value = float(match.group(0))
                if value > 0:
                    return value
    return None


def run_checked(command: list[str], cwd: Path | None = None) -> subprocess.CompletedProcess[bytes]:
    result = subprocess.run(command, cwd=str(cwd) if cwd else None, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    if result.returncode:
        detail = result.stderr.decode("utf-8", "replace")[-2000:]
        raise RuntimeError(f"command failed ({result.returncode}): {' '.join(command)}\n{detail}")
    return result


def resolve_media_tools(exes: Path) -> tuple[Path, Path]:
    """Locate ffmpeg and ffprobe.

    The Windows package ships them inside exes/ next to the solver. On Linux and
    ARM there is no reason to vendor a 63 MB static build when every distribution
    packages ffmpeg, so fall back to whatever is on PATH. Both are resolved with
    the same extension trick the solver uses, because the GUI names the ones it
    ships ffmpeg.x and ffprobe.x.
    """
    ffmpeg = solver_exe_optional(exes, "ffmpeg")
    if ffmpeg is None:
        found = shutil.which("ffmpeg")
        if found:
            ffmpeg = Path(found)
    ffprobe = solver_exe_optional(exes, "ffprobe")
    if ffprobe is None:
        found = shutil.which("ffprobe")
        if found:
            ffprobe = Path(found)
    if ffmpeg is None:
        raise FileNotFoundError(
            f"ffmpeg not found: neither {exes} nor PATH has it; "
            f"install ffmpeg (e.g. apt install ffmpeg) or place it in {exes}")
    if ffprobe is None:
        raise FileNotFoundError(
            f"ffprobe not found: neither {exes} nor PATH has it; "
            f"install ffmpeg (e.g. apt install ffmpeg) or place it in {exes}")
    return ffmpeg, ffprobe


def probe_dimensions(media: Path, ffprobe: Path) -> tuple[int, int]:
    if not ffprobe.is_file():
        raise FileNotFoundError(f"ffprobe not found: {ffprobe}")
    result = run_checked([str(ffprobe), "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height", "-of", "csv=p=0", str(media)])
    match = re.search(rb"(\d+)\s*[, ]\s*(\d+)", result.stdout)
    if not match:
        raise RuntimeError(f"ffprobe did not return dimensions for {media}")
    return int(match.group(1)), int(match.group(2))

def sample_frames(video: Path, out_root: Path, exes: Path, calib: Path, every: int | None, fps_sample: float | None, ffmpeg_options: list[str]) -> list[Path]:
    ffmpeg, ffprobe = resolve_media_tools(exes)
    dimensions = parse_img_ref_size(calib)
    frames_dir = out_root / "frames"
    if frames_dir.exists():
        shutil.rmtree(frames_dir)
    frames_dir.mkdir(parents=True)
    filters: list[str] = []
    if fps_sample is not None:
        if fps_sample <= 0:
            raise ValueError("--fps-sample must be positive")
        filters.append(f"fps={fps_sample:g}")
    else:
        step = max(1, int(every if every is not None else 1))
        filters.append(f"framestep={step}")
    if dimensions:
        width, height = dimensions
        filters.append(f"scale={width}:{height}")
    command = [str(ffmpeg), "-y", *ffmpeg_options, "-i", str(video), "-vf", ",".join(filters), str(frames_dir / "frame_%06d.png")]
    run_checked(command)
    frames = sorted(frames_dir.glob("frame_*.png"), key=natural_key)
    if not frames:
        raise RuntimeError(f"ffmpeg produced no frames in {frames_dir}")
    actual = probe_dimensions(frames[0], ffprobe)
    if dimensions and actual != dimensions:
        raise RuntimeError(f"sampled frame dimensions {actual} do not match img_ref dimensions {dimensions}")
    print(f"Sampled {len(frames)} frames into {frames_dir} using {','.join(filters)}; dimensions={actual[0]}x{actual[1]}")
    return frames


def write_p2(values: bytes | bytearray, width: int, height: int, destination: Path) -> None:
    if len(values) != width * height:
        raise ValueError(f"gray frame has {len(values)} bytes, expected {width * height} for {width}x{height}")
    with destination.open("w", encoding="ascii", newline="\n") as handle:
        handle.write(f"P2\n{width} {height}\n255\n")
        for row in range(height):
            start = row * width
            handle.write(" ".join(str(value) for value in values[start:start + width]) + "\n")


def write_pgm(values: bytes | bytearray, width: int, height: int, destination: Path,
              binary: bool = True) -> None:
    """Write a grayscale PGM, as binary P5 by default and ASCII P2 on request.

    P5 is the format the solver wants. One transformed 1089x591 frame is 643k
    pixels: as P2 that is 2.56 MB of text that the solver has to parse number by
    number, as P5 it is 0.64 MB of bytes it can copy straight into its image
    array. Writing P5 also cuts the disk the run needs, because img_transf and
    img_pgm both shrink by about 4x - and on a field device that is what runs
    out first.
    """
    if len(values) != width * height:
        raise ValueError(f"gray frame has {len(values)} bytes, expected {width * height} for {width}x{height}")
    if binary:
        with destination.open("wb") as handle:
            handle.write(b"P5\n%d %d\n255\n" % (width, height))
            handle.write(bytes(values))
        return
    write_p2(values, width, height, destination)


def png_to_pgm(png: Path, destination: Path, exes: Path, dimensions: tuple[int, int],
               binary: bool = True) -> None:
    ffmpeg, _ = resolve_media_tools(exes)
    width, height = dimensions
    command = [str(ffmpeg), "-v", "error", "-i", str(png), "-f", "rawvideo", "-pix_fmt", "gray", "-"]
    raw = run_checked(command).stdout
    write_pgm(raw, width, height, destination, binary=binary)


def png_to_p2(png: Path, destination: Path, exes: Path, dimensions: tuple[int, int]) -> None:
    png_to_pgm(png, destination, exes, dimensions, binary=False)


# Decoding a video's worth of PNGs happens once per run and is pure ffmpeg work.
# One ffmpeg process keeps exactly one core busy, so the frame list is split into
# this many ranges and decoded concurrently. Measured on the 12-core reference
# machine (48 frames of 1920x1080): 1 range = 0.087 s/frame, 8 ranges =
# 0.023 s/frame (3.6x), while 12 ranges is slower again - hence a cap of 8
# rather than the core count.
CONVERT_PARTS_CAP = 8


def _chunk_ranges(count: int, parts: int) -> list[tuple[int, int]]:
    """Split ``range(count)`` into at most ``parts`` contiguous [start, stop)."""
    parts = max(1, min(parts, count))
    size, extra = divmod(count, parts)
    ranges: list[tuple[int, int]] = []
    start = 0
    for index in range(parts):
        stop = start + size + (1 if index < extra else 0)
        if stop > start:
            ranges.append((start, stop))
        start = stop
    return ranges


def _write_frame_list(path: Path, frames: list[Path]) -> None:
    """Write an ffmpeg concat-demuxer list; paths must use forward slashes."""
    with path.open("w", encoding="utf-8") as handle:
        for frame in frames:
            posix = frame.resolve().as_posix().replace("'", "'\\''")
            handle.write(f"file '{posix}'\n")


def _pgm_p5_layout(path: Path) -> tuple[int, int, int] | None:
    """Return ``(width, height, header_bytes)`` for a P5 file, else None.

    Confirms a file ffmpeg wrote is a complete image: the header is parsed and
    the caller compares the file size against it, so a truncated or half-written
    frame can never reach the solver.
    """
    try:
        head = path.read_bytes()[:80]
    except OSError:
        return None
    if not head.startswith(b"P5"):
        return None
    position, tokens = 2, []
    while len(tokens) < 3:
        while position < len(head) and head[position:position + 1].isspace():
            position += 1
        if head[position:position + 1] == b"#":
            while position < len(head) and head[position:position + 1] != b"\n":
                position += 1
            continue
        start = position
        while position < len(head) and not head[position:position + 1].isspace():
            position += 1
        if position == start:
            return None
        try:
            tokens.append(int(head[start:position]))
        except ValueError:
            return None
    if tokens[2] != 255:
        return None
    return tokens[0], tokens[1], position + 1


def _install_p5_chunk(produced: list[Path], destinations: list[Path],
                      dimensions: tuple[int, int]) -> bool:
    """Verify the files one chunk produced, then rename them into place.

    Each chunk writes under its own name prefix, so a chunk that emitted one
    frame too many cannot silently overwrite its neighbour's first frame. The
    rename stays inside the output folder, so it works even when the run folder
    and the system temp folder are on different drives.
    """
    width, height = dimensions
    if len(produced) != len(destinations):
        return False
    for source in produced:
        layout = _pgm_p5_layout(source)
        if layout is None:
            return False
        file_width, file_height, header = layout
        if (file_width, file_height) != (width, height):
            return False
        try:
            if source.stat().st_size != header + file_width * file_height:
                return False
        except OSError:
            return False
    for source, destination in zip(produced, destinations):
        try:
            os.replace(source, destination)
        except OSError:
            try:
                shutil.move(str(source), str(destination))
            except OSError:
                return False
    return True


def _decode_chunk_to_pgm(job: tuple[str, str, int, str, str]) -> tuple[list[str], str]:
    """Worker: ffmpeg turns one frame range straight into P5 files.

    ffmpeg's own pgm encoder emits the same ``P5\\n<w> <h>\\n255\\n`` header this
    module writes by hand - verified byte-identical against ``write_pgm`` on a
    real video - so no Python ever touches the 2 MB of pixels in a 1920x1080
    frame. That pixel work is what used to pin one core while the rest of the
    machine sat idle.

    Runs in a thread, not a process: the real work is the external ffmpeg, so
    the returned paths need no pickling.
    """
    ffmpeg, list_path, start, pattern, prefix = job
    command = [ffmpeg, "-v", "error", "-y", "-f", "concat", "-safe", "0",
               "-i", list_path, "-vsync", "0", "-pix_fmt", "gray",
               "-c:v", "pgm", "-f", "image2", "-start_number", str(start),
               pattern]
    result = subprocess.run(command, capture_output=True, check=False, text=True)
    if result.returncode != 0:
        return [], (result.stderr or "ffmpeg failed").strip()[:300]
    produced = sorted(Path(pattern).parent.glob(f"{prefix}*.pgm"), key=natural_key)
    return [str(path) for path in produced], ""


def _decode_chunk_to_raw(job: tuple[str, str, str, list[str], int, int, bool]) -> tuple[int, str]:
    """Worker: decode one frame range to raw bytes, then write its PGMs.

    Fallback for an ffmpeg build without a pgm encoder, or when the direct pass
    produced anything that failed verification. Each worker keeps only its own
    range in memory and deletes its scratch file, so peak disk stays at one
    chunk instead of the whole video.
    """
    ffmpeg, list_path, raw_path, destinations, width, height, binary = job
    command = [ffmpeg, "-v", "error", "-y", "-f", "concat", "-safe", "0",
               "-i", list_path, "-vsync", "0", "-f", "rawvideo",
               "-pix_fmt", "gray", raw_path]
    try:
        result = subprocess.run(command, capture_output=True, check=False, text=True)
        if result.returncode != 0:
            return 0, (result.stderr or "ffmpeg failed").strip()[:300]
        raw = Path(raw_path).read_bytes()
        per_frame = width * height
        if len(raw) != per_frame * len(destinations):
            return 0, f"got {len(raw)} bytes for {len(destinations)} frames"
        for index, destination in enumerate(destinations):
            write_pgm(raw[index * per_frame:(index + 1) * per_frame],
                      width, height, Path(destination), binary=binary)
        return len(destinations), ""
    finally:
        try:
            Path(raw_path).unlink()
        except OSError:
            pass


def convert_frames(frames: list[Path], pgm_dir: Path, exes: Path,
                   dimensions: tuple[int, int], binary: bool = True,
                   write_workers: int = 0) -> list[Path]:
    """Convert every frame to PGM with no single-core stage left in it.

    Two successive bottlenecks lived here:

    * one ffmpeg process per frame (935 launches for a 935 frame video), which
      cost ~0.27 s/frame on a single core; then
    * one ffmpeg process for the whole list, which removed the launch overhead
      but still pinned a single core, because PNG decoding is single threaded
      inside one process.

    So the list is split into contiguous ranges and every range is decoded by
    its own ffmpeg, while ffmpeg's pgm encoder writes the P5 files directly.
    Measured on 48 frames of 1920x1080 (12-core reference machine): one process
    0.087 s/frame, eight processes 0.023 s/frame - 3.6x, unchanged output.

    Two fallbacks keep an unusual ffmpeg build or a single odd frame from
    sinking a run: chunked decode to raw plus parallel PGM writes, then the
    original one-ffmpeg-per-frame path.
    """
    pgm_dir.mkdir(parents=True, exist_ok=True)
    width, height = dimensions
    destinations = [pgm_dir / f"image{index:04d}.pgm" for index in range(1, len(frames) + 1)]
    if not frames:
        return []
    parts = write_workers if write_workers > 0 else min(os.cpu_count() or 1, CONVERT_PARTS_CAP)
    ranges = _chunk_ranges(len(frames), parts)
    ffmpeg, _ = resolve_media_tools(exes)
    started = time.perf_counter()
    notes: list[str] = []

    with tempfile.TemporaryDirectory(prefix="lspiv_convert_") as scratch:
        scratch_root = Path(scratch)
        lists: list[tuple[int, int, Path]] = []
        for number, (start, stop) in enumerate(ranges):
            list_path = scratch_root / f"chunk{number:03d}.txt"
            _write_frame_list(list_path, frames[start:stop])
            lists.append((start, stop, list_path))

        # Tier 1: ffmpeg writes the P5 files itself, one process per range.
        # Threads rather than processes: the real work is an external ffmpeg.
        # Chunks land in pgm_dir under a private prefix and are renamed into
        # place afterwards, so nothing has to move between volumes.
        if binary:
            jobs = []
            for number, (start, stop, list_path) in enumerate(lists):
                prefix = f"_c{number:03d}_"
                jobs.append((str(ffmpeg), str(list_path), start + 1,
                             str(pgm_dir / f"{prefix}%04d.pgm"), prefix))
            with concurrent.futures.ThreadPoolExecutor(max_workers=len(jobs)) as pool:
                outcomes = list(pool.map(_decode_chunk_to_pgm, jobs))
            installed = all(
                not error and len(produced) == stop - start
                for (produced, error), (start, stop, _list_path) in zip(outcomes, lists))
            if installed:
                for (produced, _error), (start, stop, _list_path) in zip(outcomes, lists):
                    if not _install_p5_chunk([Path(name) for name in produced],
                                             destinations[start:stop], dimensions):
                        installed = False
                        break
            if installed:
                print(f"Converted {len(frames)} frame(s) to PGM in "
                      f"{time.perf_counter() - started:.2f}s "
                      f"({len(jobs)} ffmpeg process(es), direct P5)")
                return destinations
            notes.extend(error for _produced, error in outcomes if error)
            # A failure part-way through the rename above can leave staging
            # files behind; clear them so img_pgm only ever holds image####.pgm.
            for leftover in pgm_dir.glob("_c*_*.pgm"):
                try:
                    leftover.unlink()
                except OSError:
                    pass
            detail = notes[0] if notes else "output failed verification"
            print(f"Warning: direct PGM write was not usable ({detail}); "
                  "retrying through raw frames")

        # Tier 2: chunked decode to raw, then parallel PGM writes. The raw
        # spill goes next to the output rather than in the system temp folder,
        # so a full video's worth of bytes stays on the volume that was chosen
        # for this run. Each worker deletes its own file as soon as it is done.
        raw_root = pgm_dir.parent / "tmp" / "convert_raw"
        raw_root.mkdir(parents=True, exist_ok=True)
        jobs = []
        for number, (start, stop, list_path) in enumerate(lists):
            jobs.append((str(ffmpeg), str(list_path), str(raw_root / f"chunk{number:03d}.raw"),
                         [str(destination) for destination in destinations[start:stop]],
                         width, height, binary))
        done = True
        with concurrent.futures.ProcessPoolExecutor(max_workers=len(jobs)) as pool:
            for written, error in pool.map(_decode_chunk_to_raw, jobs):
                if not written:
                    done = False
                    notes.append(error)
        if done:
            print(f"Converted {len(frames)} frame(s) to PGM in "
                  f"{time.perf_counter() - started:.2f}s "
                  f"({len(jobs)} ffmpeg process(es), raw + parallel writes)")
            return destinations

    print("Warning: batched frame conversion failed; falling back to one ffmpeg per frame")
    for frame, destination in zip(frames, destinations):
        png_to_pgm(frame, destination, exes, dimensions, binary=binary)
    return destinations


def _pgm_tokens(data: bytes) -> list[bytes]:
    tokens: list[bytes] = []
    index = 0
    while index < len(data):
        while index < len(data) and data[index] in b" \t\r\n":
            index += 1
        if index < len(data) and data[index] == 35:
            end = data.find(b"\n", index)
            index = len(data) if end < 0 else end + 1
            continue
        if index >= len(data):
            break
        end = index
        while end < len(data) and data[end] not in b" \t\r\n#":
            end += 1
        tokens.append(data[index:end])
        index = end
    return tokens


def _p2_row_aligned(data: bytes) -> tuple[int, int, list[bytes]] | None:
    """Recognise a row-aligned P2 image and return its ``(width, height, rows)``.

    ``_pgm_tokens`` walks the buffer one byte at a time in Python, which costs
    about 0.33 s for a 1089x591 image - more than the solver spends on the pair.
    The P2 files this tool has to canonicalise come from transf_a, which writes
    one record per image row with its ``(I5)`` format, so splitting on newlines
    and re-joining each row is enough and lands at ~0.04 s. Returns None for any
    file that is not in that shape, and the caller falls back to the general
    tokenising path.
    """
    if not data.startswith(b"P2"):
        return None
    lines = data.splitlines()
    if len(lines) < 4 or lines[0].strip() != b"P2":
        return None
    dimensions = lines[1].split()
    if len(dimensions) != 2:
        return None
    try:
        width, height = int(dimensions[0]), int(dimensions[1])
    except ValueError:
        return None
    if lines[2].strip() != b"255":  # anything else needs the scaling path
        return None
    rows = lines[3:3 + height]
    if len(rows) != height:
        return None
    normalised: list[bytes] = []
    for row in rows:
        tokens = row.split()
        if len(tokens) != width or max(map(len, tokens)) > 3:
            return None
        if not all(token.isdigit() for token in tokens):
            return None
        normalised.append(b" ".join(tokens))
    return width, height, normalised


def _fast_rewrite_p2(data: bytes, destination: Path) -> bool:
    """Write a row-aligned P2 file back out as canonical P2."""
    shape = _p2_row_aligned(data)
    if shape is None:
        return False
    width, height, rows = shape
    body = [b"P2", b"%d %d" % (width, height), b"255", *rows]
    destination.write_bytes(b"\n".join(body) + b"\n")
    return True


def _p2_rows_to_p5(data: bytes, destination: Path) -> bool:
    """Write a row-aligned P2 file as P5 bytes without tokenising it.

    This is the hot path: transf_a emits P2, and the solver wants P5. Going via
    ``int()`` per pixel used to cost ~0.33 s/frame - 62% of the whole transform
    stage. Because the values are already the decimal form of bytes and the
    rows are whitespace separated, ``bytes(map(int, ...))`` over each row is
    done in C and cuts that to a few tens of milliseconds.
    """
    shape = _p2_row_aligned(data)
    if shape is None:
        return False
    width, height, rows = shape
    try:
        values = bytearray()
        for row in rows:
            values.extend(bytes(map(int, row.split())))
    except ValueError:
        return False
    if len(values) != width * height:
        return False
    with destination.open("wb") as handle:
        handle.write(b"P5\n%d %d\n255\n" % (width, height))
        handle.write(bytes(values))
    return True


def normalize_pgm(source: Path, destination: Path, binary: bool = True) -> None:
    """Rewrite a PGM in the canonical form the solver reads fastest.

    With ``binary=True`` (the default) the output is P5 regardless of the input
    format, so a solver built with the P5 reader gets a byte copy instead of a
    640k-token text parse. Pass ``binary=False`` to keep the historical P2
    output, which older solver builds require.

    The P2 input path is kept because transf_a still emits P2.
    """
    data = source.read_bytes()
    if not data.startswith((b"P2", b"P5")):
        raise ValueError(f"unsupported PGM magic in {source}")
    magic = data[:2]
    if magic == b"P2":
        # transf_a is the P2 producer here, and it writes row-aligned records.
        # Both destinations have a cheap path for that shape; going through
        # _pgm_tokens instead costs ~0.33 s/frame, which was 62% of the whole
        # transform stage. Only fall back to the general tokeniser when the file
        # is not row aligned or needs maxval rescaling.
        if binary and _p2_rows_to_p5(data, destination):
            return
        if not binary and _fast_rewrite_p2(data, destination):
            return
        tokens = _pgm_tokens(data)
        if len(tokens) < 4:
            raise ValueError(f"incomplete P2 PGM: {source}")
        width, height, maxval = map(int, tokens[1:4])
        values = [min(255, round(int(token) * 255 / maxval)) for token in tokens[4:4 + width * height]]
        if len(values) != width * height:
            raise ValueError(f"P2 pixel count mismatch in {source}")
        write_pgm(bytes(values), width, height, destination, binary=binary)
        return
    index = 2
    header: list[bytes] = []
    while len(header) < 3:
        while index < len(data) and data[index] in b" \t\r\n":
            index += 1
        if index < len(data) and data[index] == 35:
            end = data.find(b"\n", index)
            index = len(data) if end < 0 else end + 1
            continue
        end = index
        while end < len(data) and data[end] not in b" \t\r\n#":
            end += 1
        header.append(data[index:end])
        index = end
    width, height, maxval = map(int, header)
    count = width * height
    payload = data[index:]
    if maxval < 256:
        values = payload[:count]
    else:
        values = bytes(int.from_bytes(payload[i:i + 2], "big") * 255 // maxval for i in range(0, count * 2, 2))
    write_pgm(values, width, height, destination, binary=binary)


def _run_transform(job: tuple[str, str, str, str, int, int, bool]) -> dict[str, Any]:
    transf_s, calib_s, frame_s, out_root_s, index, threads, binary_pgm = job
    transf, calib, frame, out_root = Path(transf_s), Path(calib_s), Path(frame_s), Path(out_root_s)
    # Same reasoning as _run_pair: one workdir per worker process, overwritten in
    # place, so no directory is rebuilt or deleted per frame. transf_a only
    # writes img_transf/image1_transf.pgm and every frame of a run has the same
    # geometry, so a plain overwrite reproduces a fresh tree exactly.
    workdir = out_root / "tmp" / f"transf_worker_{os.getpid()}"
    started = time.perf_counter()
    try:
        (workdir / "outputs.dir").mkdir(parents=True, exist_ok=True)
        (workdir / "img_pgm").mkdir(exist_ok=True)
        (workdir / "img_transf").mkdir(exist_ok=True)
        _copy_calib(calib, workdir / "outputs.dir")
        shutil.copyfile(frame, workdir / "img_pgm" / "image1.pgm")
        # transf_a.exe reads its thread count as the first argument too.
        command = [str(transf)] + ([str(threads)] if threads > 1 else [])
        result = subprocess.run(command, cwd=str(workdir), capture_output=True, text=True, encoding="utf-8", errors="replace", check=False)
        (workdir / "stdout.txt").write_text(result.stdout or "", encoding="utf-8")
        (workdir / "stderr.txt").write_text(result.stderr or "", encoding="utf-8")
        source = workdir / "img_transf" / "image1_transf.pgm"
        if result.returncode != 0 or not source.is_file() or source.stat().st_size == 0:
            return {"index": index, "ok": False, "elapsed": time.perf_counter() - started,
                    "message": f"transf_a.exe exit={result.returncode}; output missing/empty", "workdir": str(workdir)}
        destination = out_root / "img_transf" / f"image{index:04d}_transf.pgm"
        destination.parent.mkdir(parents=True, exist_ok=True)
        normalize_pgm(source, destination, binary=binary_pgm)
        return {"index": index, "ok": True, "elapsed": time.perf_counter() - started, "message": str(destination), "workdir": str(workdir)}
    except Exception as exc:
        workdir.mkdir(parents=True, exist_ok=True)
        (workdir / "error.txt").write_text(repr(exc), encoding="utf-8")
        return {"index": index, "ok": False, "elapsed": time.perf_counter() - started,
                "message": f"{type(exc).__name__}: {exc}", "workdir": str(workdir)}


def run_transforms(frames: list[Path], out_root: Path, exes: Path, calib: Path, workers: int,
                   keep: bool, dimensions: tuple[int, int], threads: int = 1,
                   binary_pgm: bool = True) -> list[dict[str, Any]]:
    # convert_frames splits the decode over several ffmpeg processes and sizes
    # itself from the core count, so it is deliberately not tied to `workers`:
    # this stage finishes before any transform worker starts, and a single
    # ffmpeg is single threaded however many cores the machine has.
    converted = convert_frames(frames, out_root / "img_pgm", exes, dimensions,
                               binary=binary_pgm)
    # Resolve through solver_exe, not a literal "transf_a.exe": on Linux/ARM the
    # binaries are suffixed ".x", so a hard-coded ".exe" made every transform
    # job fail to launch on the board. Resolved once so a missing solver is
    # reported before any worker starts.
    transf = solver_exe(exes, "transf_a")
    jobs = [(str(transf), str(calib), str(pgm), str(out_root), index, threads, binary_pgm)
            for index, pgm in enumerate(converted, 1)]
    results: list[dict[str, Any]] = []
    with concurrent.futures.ProcessPoolExecutor(max_workers=min(workers, len(jobs))) as pool:
        futures = [pool.submit(_run_transform, job) for job in jobs]
        for future in concurrent.futures.as_completed(futures):
            result = future.result()
            results.append(result)
            print(f"[{('OK' if result['ok'] else 'FAIL')}] transform {result['index']:04d} {result['elapsed']:.2f}s: {result['message']}")
    if all(item["ok"] for item in results) and not keep:
        shutil.rmtree(out_root / "tmp", ignore_errors=True)
    return sorted(results, key=lambda item: item["index"])


def run_video(args: argparse.Namespace) -> int:
    config = getattr(args, "_config", load_config())
    exes = resolve_exes(args.exes, config)
    calib = Path(args.calib).expanduser().resolve()
    video = Path(args.video).expanduser().resolve()
    out_root = Path(args.out).expanduser().resolve()
    transf = solver_exe(exes, "transf_a")
    if not video.is_file():
        raise FileNotFoundError(f"video not found: {video}")
    if not calib.is_dir():
        raise FileNotFoundError(f"calibration directory not found: {calib}")
    missing = [name for name in CALIB_REQUIRED if not (calib / name).is_file()]
    if missing:
        raise FileNotFoundError(f"calibration files missing from {calib}: {', '.join(missing)}")
    out_root.mkdir(parents=True, exist_ok=True)
    resolved_calib = prepare_resolved_calib(calib, out_root)
    ensure_coeff(resolved_calib, exes, out_root)
    dimensions = parse_img_ref_size(resolved_calib)
    if not dimensions:
        raise FileNotFoundError(f"img_ref.dat with source dimensions is required in {calib}")
    ffmpeg_options = config.get("ffmpeg_options", [])
    if not isinstance(ffmpeg_options, list) or not all(isinstance(item, str) for item in ffmpeg_options):
        raise ValueError("config ffmpeg_options must be a list of strings")
    every = args.every
    if every is None:
        every = int(config.get("frame_every", 1))
    workers = effective_workers(args.workers, config, default=os.cpu_count() or 1)
    keep = effective_keep(args.keep_workdirs, config)
    started = time.perf_counter()
    frames = sample_frames(video, out_root, exes, resolved_calib, every, args.fps_sample, ffmpeg_options)
    tf_workers, tf_threads, tf_note = resolve_plan(
        effective_mode(getattr(args, "mode", None), config),
        workers,
        effective_solver_threads(getattr(args, "solver_threads", None), config),
        effective_budget(getattr(args, "cpu_budget", None), config),
        len(frames))
    # sub_transf_23D also splits its row loop with static chunking, so the same
    # thread ceiling applies, here bounded by the image height.
    tf_threads = clamp_threads(tf_threads, dimensions[1], "image rows")
    print(f"ortho plan: processes={tf_workers} x threads={tf_threads} ({tf_note})")
    binary_pgm = effective_pgm_binary(getattr(args, "pgm_binary", None), config)
    transform_results = run_transforms(frames, out_root, exes, resolved_calib, tf_workers, keep,
                                       dimensions, tf_threads, binary_pgm=binary_pgm)
    successful = [item for item in transform_results if item["ok"]]
    failed = [item for item in transform_results if not item["ok"]]
    if failed:
        print(f"Warning: {len(failed)} frame transformations failed; failed workdirs were kept")
    if len(successful) < 2:
        raise RuntimeError("fewer than two transformed frames are available for PIV")
    piv_args = argparse.Namespace(**vars(args))
    piv_args.exes, piv_args.calib, piv_args.img_transf, piv_args._config = str(exes), str(resolved_calib), str(out_root / "img_transf"), config
    piv_args.pairs = None
    piv_args.keep_workdirs = keep
    piv_result = run_piv(piv_args)
    if args.vel_real and (resolved_calib / "img_ref.dat").is_file():
        code = run_vel_real(piv_args)
        if code:
            return code
    elif args.vel_real:
        print("Skipping vel-real: img_ref.dat is not present")
    run_filter(piv_args, out_root, resolved_calib, exes)
    print(f"Using calib={calib} resolved_calib={resolved_calib} out={out_root} workers={workers}")
    print_result_summary(out_root, sum(1 for item in piv_result["results"] if item["ok"]))
    return 0 if not failed and all(item["ok"] for item in piv_result["results"]) else 1


def run_make_coeff(args: argparse.Namespace) -> int:
    config = getattr(args, "_config", load_config())
    exes = resolve_exes(args.exes, config)
    calib = Path(args.calib).expanduser().resolve()
    if not calib.is_dir():
        raise FileNotFoundError(f"calibration directory not found: {calib}")
    if not (calib / "GRP.dat").is_file():
        raise FileNotFoundError(f"GRP.dat is required: {calib / 'GRP.dat'}")
    out_root = Path(args.out).expanduser().resolve()
    out_root.mkdir(parents=True, exist_ok=True)
    target = calib if args.write_calib else prepare_resolved_calib(calib, out_root)
    ensure_coeff(target, exes, out_root)
    print(f"coeff.dat ready: {target / 'coeff.dat'}")
    return 0


VIDEO_SUFFIXES = {".mp4", ".avi", ".mov", ".mkv", ".wmv", ".m4v", ".mpg", ".mpeg"}


def calibration_is_complete(path: Path) -> bool:
    return path.is_dir() and all((path / name).is_file() for name in CALIB_REQUIRED)


def default_calibration() -> str:
    for candidate in (Path("calib"), SCRIPT_DIR / "calib"):
        if candidate.is_dir() and calibration_is_complete(candidate):
            return str(candidate)
    return ".\\calib"


def default_output(command: str, video: str | None = None) -> str:
    from datetime import datetime
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    stem = Path(video).stem if video else command
    return str(Path("runs") / f"{stem}_{stamp}")


def normalize_argv(argv: list[str]) -> list[str]:
    # Allow `script video.mp4` and `script video video.mp4` shorthand.
    items = list(argv)
    if not items:
        return items
    if items[0].lower() == "video" and len(items) > 1:
        candidate = items[1]
        if not candidate.startswith("-") and Path(candidate).suffix.lower() in VIDEO_SUFFIXES:
            return ["video", "--video", candidate, *items[2:]]
    first = items[0]
    if Path(first).suffix.lower() in VIDEO_SUFFIXES and Path(first).is_file():
        return ["video", "--video", first, *items[1:]]
    return items


def apply_defaults(args: argparse.Namespace) -> argparse.Namespace:
    if hasattr(args, "calib") and not args.calib:
        args.calib = default_calibration()
    if hasattr(args, "img_transf") and not args.img_transf and Path("img_transf").is_dir():
        args.img_transf = ".\\img_transf"
    if hasattr(args, "out") and not args.out:
        if args.command == "video":
            args.out = default_output("video", args.video)
        elif args.command == "vel-real":
            args.out = str(Path("runs") / "latest")
        else:
            args.out = default_output(args.command)
    return args


def print_start_summary(args: argparse.Namespace) -> None:
    config = getattr(args, "_config", {})
    workers = effective_workers(getattr(args, "workers", None), config, default=os.cpu_count() or 1)
    mode = effective_mode(getattr(args, "mode", None), config)
    threads = effective_solver_threads(getattr(args, "solver_threads", None), config)
    budget = effective_budget(getattr(args, "cpu_budget", None), config)
    print(f"Using calib={Path(args.calib).expanduser().resolve()} out={Path(args.out).expanduser().resolve()} "
          f"mode={mode} workers={workers} solver_threads={threads} cpu_budget={budget}")


def probe_filesystem(root: Path, images: list[Path]) -> None:
    """Measure what one pair's worth of file shuffling costs on this machine.

    Every pair used to cost three mkdir calls, four copies and the deletion of
    the previous workdir. Writing and copying are cheap everywhere, but deletion
    is the one call antivirus and cloud-sync filters intercept, and on some
    machines it is two orders of magnitude dearer than a copy. Worth measuring
    instead of guessing, because it decides whether the workdir should be
    rebuilt or reused.
    """
    root.mkdir(parents=True, exist_ok=True)
    payload = bytes(256) * (10 * 1024)  # 2.5 MB, the size of one transformed frame
    scratch = root / "scratch"
    sample = root / "sample.bin"
    write_times: list[float] = []
    copy_times: list[float] = []
    delete_times: list[float] = []
    tree_times: list[float] = []
    source = images[0] if images else None
    for _ in range(BENCH_FS_REPEATS):
        started = time.perf_counter()
        sample.write_bytes(payload)
        write_times.append(time.perf_counter() - started)
        if source is not None:
            started = time.perf_counter()
            shutil.copyfile(source, root / "copy.pgm")
            copy_times.append(time.perf_counter() - started)
        started = time.perf_counter()
        sample.unlink()
        delete_times.append(time.perf_counter() - started)

        shutil.rmtree(scratch, ignore_errors=True)
        (scratch / "img_transf").mkdir(parents=True)
        (scratch / "vel_raw").mkdir()
        (scratch / "vel_raw" / "piv.dat").write_bytes(b"x" * 20000)
        for name, image in enumerate(images[:2]):
            shutil.copyfile(image, scratch / "img_transf" / f"image{name + 1}_transf.pgm")
        started = time.perf_counter()
        shutil.rmtree(scratch, ignore_errors=True)
        tree_times.append(time.perf_counter() - started)
    (root / "copy.pgm").unlink(missing_ok=True)
    shutil.rmtree(scratch, ignore_errors=True)

    write = min(write_times)
    delete = min(delete_times)
    tree = min(tree_times)
    print(f"BENCH filesystem profile under {root}")
    print(f"BENCH   write a 2.5 MB file                {write:.4f}s")
    if copy_times:
        print(f"BENCH   copy one {source.stat().st_size / 1048576:.1f} MB PGM              {min(copy_times):.4f}s")
    print(f"BENCH   delete a 2.5 MB file               {delete:.4f}s")
    print(f"BENCH   delete a dir with 2 PGMs + 1 dat   {tree:.4f}s")
    ratio = delete / write if write else 0.0
    print(f"BENCH verdict: a deletion costs {ratio:.0f}x a write here, so the per-pair "
          f"workdir is reused and nothing is deleted between pairs")


def run_bench(args: argparse.Namespace) -> int:
    """Profile the solver so the multi-core plan can be chosen from data.

    Reports two independent numbers:
      1. thread scaling inside one solver run -> how much of a pair is the
         correlator, i.e. the ceiling for native threading;
      2. batch throughput against the number of solver processes.
    """
    config = getattr(args, "_config", load_config())
    exes = resolve_exes(getattr(args, "exes", None), config)
    calib = Path(args.calib).expanduser().resolve()
    if not getattr(args, "img_transf", None):
        raise ValueError("bench needs --img-transf, or a .\\img_transf folder")
    img_transf = Path(args.img_transf).expanduser().resolve()
    _, images = validate_common(exes, calib, img_transf)
    indexes = parse_pairs(args.pairs, len(images))
    budget = effective_budget(getattr(args, "cpu_budget", None), config)
    root = Path(args.out).expanduser().resolve()
    print(f"BENCH: {len(indexes)} pairs selected of {len(images)} transformed images; cpu budget {budget}")

    # -- 1. thread scaling inside a single solver run -------------------------
    # Measured from the time each worker reports for the solver process itself,
    # so neither the process-pool start-up nor the workdir file shuffling (both
    # antivirus-sensitive on Windows) leaks into the estimate. The minimum over
    # several repeats is used because only interrupts ever make a run slower.
    probe = argparse.Namespace(**vars(args))
    probe_pairs = indexes[:min(len(indexes), BENCH_PROBE_PAIRS)]
    probe.pairs = f"{probe_pairs[0]}:{probe_pairs[-1]}"
    thread_points = sorted({1, min(budget, 2), min(budget, 4), budget})
    timings: list[tuple[int, float, bool]] = []
    full_by_threads: dict[int, float] = {}
    for threads in thread_points:
        best: float | None = None
        best_full: float | None = None
        for _ in range(BENCH_PROBE_REPEATS):
            result = run_piv(probe, root / f"threads_{threads}", workers=1, threads=threads,
                             mode="hybrid", quiet=True)
            good = [item["solver"] for item in result["results"]
                    if item["ok"] and item.get("solver")]
            if good and (best is None or min(good) < best):
                best = min(good)
            whole = [item["elapsed"] for item in result["results"] if item["ok"]]
            if whole and (best_full is None or min(whole) < best_full):
                best_full = min(whole)
        timings.append((threads, best or 0.0, best is not None))
        if best_full is not None:
            full_by_threads[threads] = best_full
    for threads, pair_time, ok in timings:
        print(f"BENCH   {threads:>2} thread(s): {pair_time:.3f}s per pair (solver process only) ok={ok}")
    single = next(t for th, t, _ in timings if th == 1)
    widest, widest_time, _ = timings[-1]
    inner_speedup = single / widest_time if widest_time else 0.0
    # t(T) = a + c/T  ->  c = (t(1) - t(T)) / (1 - 1/T)
    compute = ((single - widest_time) / (1.0 - 1.0 / widest)) if widest > 1 and single > widest_time else 0.0
    share = max(0.0, min(1.0, compute / single)) if single else 0.0
    print(f"BENCH single pair: 1 thread {single:.3f}s, {widest} threads {widest_time:.3f}s "
          f"-> inner speedup {inner_speedup:.2f}x")
    if full_by_threads.get(1):
        print(f"BENCH per pair end to end: {full_by_threads[1]:.3f}s, of which {single:.3f}s is inside "
              f"PIV.exe; the rest is workdir setup and moving the result out")
    print(f"BENCH estimate (rough; rerun if the numbers look noisy): about {share * 100:.0f}% of one "
          f"solver run is the parallelisable correlation kernel ({compute:.3f}s); the remaining "
          f"{single - compute:.3f}s is PIV.exe start-up plus reading the images and writing the result, "
          f"which native threads cannot touch")

    # -- 1b. what the per-pair file shuffling costs on this machine -----------
    probe_filesystem(root / "fsprobe", images)

    # -- 2. batch throughput against process count ----------------------------
    if getattr(args, "sweep", None):
        sweep = sorted({int(item) for item in str(args.sweep).split(",") if item.strip()})
    else:
        sweep = sorted({1, 2, 4, 6, 8, budget} | {budget // 2})
    sweep = [w for w in sweep if 1 <= w <= budget] or [1]
    sample = indexes if getattr(args, "pairs", None) else indexes[:max(1, min(len(indexes), 4 * budget))]
    print(f"BENCH batch sweep over {len(sample)} pairs, processor counts {sweep}")
    batch_args = argparse.Namespace(**vars(args))
    batch_args.pairs = f"{sample[0]}:{sample[-1]}" if len(sample) > 1 else f"{sample[0]}:{sample[0]}"
    batch_args.workers = None
    serial_wall = None
    best: tuple[float, int] | None = None
    walls: dict[int, float] = {}
    for procs in sweep:
        result = run_piv(batch_args, root / f"proc_{procs}", workers=procs, mode="process", quiet=True)
        wall = result["elapsed"]
        ok = all(item["ok"] for item in result["results"])
        if procs == 1:
            serial_wall = wall
        speedup = (serial_wall / wall) if serial_wall else 1.0
        rate = len(sample) / wall if wall else 0.0
        print(f"BENCH processes={procs:>2} wall={wall:7.2f}s speedup={speedup:5.2f}x "
              f"{rate:5.2f} pairs/s ok={ok}")
        if ok:
            walls[procs] = wall
            if best is None or wall < best[0]:
                best = (wall, procs)

    if best is not None:
        _, best_procs = best
        # A handful of percent between two neighbouring points is run-to-run
        # noise on a desktop cpu, so do not tell the user to shrink a budget
        # over it; keep the wider budget when the two are statistically tied.
        budget_wall = walls.get(budget)
        margin = (budget_wall / best[0] - 1.0) if budget_wall else 0.0
        tied = best_procs < budget and budget_wall is not None and margin <= BENCH_NOISE
        chosen = budget if (tied or best_procs == budget) else best_procs
        print(f"BENCH recommended: --mode auto --cpu-budget {chosen} "
              f"(fastest measured plan: {best_procs} solver processes over {len(sample)} pairs, sweep {sweep})")
        if tied:
            print(f"BENCH note: {budget} processes came within {margin * 100:.0f}% of {best_procs}, which is "
                  f"run-to-run noise on this machine; keeping the larger budget is safe")
        elif best_procs < budget:
            print(f"BENCH note: {budget} processes was {margin * 100:.0f}% slower than {best_procs}. On a hybrid "
                  f"big+small core cpu the extra cores are the small ones, so a smaller budget really does win")
        if share < 0.25:
            print(f"BENCH note: the correlation kernel is only ~{share * 100:.0f}% of a run, so more native "
                  f"threads will not shorten a batch; spend the cores on more solver processes instead")
    return 0


def print_result_summary(out: Path, success_pairs: int) -> None:
    try:
        folders = sorted(item.name for item in out.iterdir() if item.is_dir())
    except OSError:
        folders = []
    print(f"OK pairs={success_pairs}; result folders={', '.join(folders) if folders else 'none'}")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Portable fixed-file Fudaa-LSPIV runner")
    sub = parser.add_subparsers(dest="command", required=True)

    def common(p: argparse.ArgumentParser) -> None:
        p.add_argument("--exes", help="Fudaa exes directory; default config.json then .\\exes beside this script")
        p.add_argument("--calib", help="calibration directory; default .\\calib")
        p.add_argument("--out", help="run output directory; default .\\runs\\... timestamped folder")
        add_solver_options(p)

    def add_solver_options(p: argparse.ArgumentParser) -> None:
        p.add_argument("--mode", choices=SOLVER_MODES,
                       help="auto (default): fill the cpu budget with pairs, leftover cores as native "
                            "threads; process: one single-threaded solver per pair (previous behaviour); "
                            "openmp: one solver using native threads; hybrid: --workers x --solver-threads")
        p.add_argument("--solver-threads", type=int,
                       help="native (OpenMP) threads inside one solver run; default 1")
        p.add_argument("--cpu-budget", type=int,
                       help="cores the plan is allowed to use; default config cpu_budget or os.cpu_count()")

    piv = sub.add_parser("piv", help="run PIV pairs in isolated workdirs")
    common(piv)
    piv.add_argument("--img-transf", help="transformed image directory; default .\\img_transf when present")
    piv.add_argument("--workers", type=int)
    piv.add_argument("--pairs", help="inclusive 1-based pair range, for example 1:3")
    piv.add_argument("--filter", dest="filter_enabled", action=argparse.BooleanOptionalAction, default=None,
                     help="post-filter all raw PIV results; default auto when filters.dat exists")
    piv.add_argument("--keep-workdirs", action=argparse.BooleanOptionalAction, default=None)

    vel = sub.add_parser("vel-real", help="run vel_transf.exe on collected vel_raw results")
    common(vel)
    vel.add_argument("--keep-workdirs", action=argparse.BooleanOptionalAction, default=None)

    bench = sub.add_parser("bench", help="profile the solver: per-pair thread scaling and batch throughput")
    common(bench)
    bench.add_argument("--img-transf", help="transformed image directory; default .\\img_transf when present")
    bench.add_argument("--pairs")
    bench.add_argument("--workers", type=int)
    bench.add_argument("--keep-workdirs", action=argparse.BooleanOptionalAction, default=None)
    bench.add_argument("--sweep", help="comma separated solver-process counts to try, e.g. 1,2,4,8,12; "
                                       "default is a sweep derived from the cpu budget")

    video = sub.add_parser("video", help="video -> transf_a -> PIV -> optional vel-real")
    video.add_argument("video_path", nargs="?", help="video path (or use --video)")
    video.add_argument("--video", help="video path")
    video.add_argument("--calib", help="calibration directory; default .\\calib")
    video.add_argument("--out", help="run output directory; default .\\runs\\<video>_<timestamp>")
    video.add_argument("--exes", help="solver directory; default config.json then .\\exes beside this script")
    video.add_argument("--workers", type=int)
    video.add_argument("--every", type=int, help="take every Nth source frame; default config frame_every or 1")
    video.add_argument("--fps-sample", type=float, help="sample at this output frame rate instead of --every")
    video.add_argument("--vel-real", action=argparse.BooleanOptionalAction, default=True)
    video.add_argument("--filter", dest="filter_enabled", action=argparse.BooleanOptionalAction, default=None,
                       help="post-filter all raw PIV results; default auto when filters.dat exists")
    video.add_argument("--keep-workdirs", action=argparse.BooleanOptionalAction, default=None)
    video.add_argument("--pgm-binary", action=argparse.BooleanOptionalAction, default=None,
                       help="write P5 binary images for the solver (default; needs a P5-capable build); "
                            "--no-pgm-binary writes legacy P2 text images instead")
    add_solver_options(video)

    coeff = sub.add_parser("make-coeff", help="generate coeff.dat from GRP.dat")
    coeff.add_argument("--calib", help="calibration directory; default .\\calib")
    coeff.add_argument("--exes", help="solver directory; default config.json then .\\exes beside this script")
    coeff.add_argument("--out", help="temporary/run output directory; default .\\runs\\make-coeff_...")
    coeff.add_argument("--write-calib", action="store_true",
                       help="write generated coeff.dat into calib; default writes out\\resolved_calib")
    return parser


def main(argv: list[str] | None = None) -> int:
    raw_argv = sys.argv[1:] if argv is None else argv
    args = build_parser().parse_args(normalize_argv(raw_argv))
    args._config = load_config()
    if args.command == "video":
        if not args.video:
            args.video = args.video_path
        if not args.video:
            print("ERROR: video command needs a video path", file=sys.stderr)
            return 2
    args = apply_defaults(args)
    try:
        print_start_summary(args)
        if args.command == "piv":
            result = run_piv(args)
            run_filter(args, result["out"], Path(args.calib).expanduser().resolve(), resolve_exes(args.exes, args._config))
            print_result_summary(result["out"], sum(1 for item in result["results"] if item["ok"]))
            return 0 if all(item["ok"] for item in result["results"]) else 1
        if args.command == "vel-real":
            code = run_vel_real(args)
            if code == 0:
                print_result_summary(Path(args.out).expanduser().resolve(), 0)
            return code
        if args.command == "video":
            return run_video(args)
        if args.command == "make-coeff":
            return run_make_coeff(args)
        if args.command == "bench":
            return run_bench(args)
    except (OSError, ValueError, FileNotFoundError, RuntimeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    return 2


if __name__ == "__main__":
    import multiprocessing
    multiprocessing.freeze_support()
    raise SystemExit(main())
