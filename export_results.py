#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# SPDX-License-Identifier: MIT
"""Export Fudaa velocity DAT files to CSV.

Legacy outputs (unchanged, Excel-friendly, UTF-8 with BOM):
    <run>/export/vel_raw.csv, <run>/export/vel_real.csv
Multi-frame outputs (physics_twin compatible, UTF-8 without BOM):
    <run>/export/vel_series.csv, <run>/export/frames_manifest.json,
    <run>/export/physics_twin_series.csv

    python3 export_results.py [run_dir]            # both (default); run_dir defaults to newest ./runs/*
    python3 export_results.py run_dir --legacy-only
    python3 export_results.py --capabilities       # machine-readable feature probe, touches no data
"""

import argparse
import csv
import json
import math
import re
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

EXPORT_SCHEMA = 2  # 1 = legacy vel_raw/vel_real only; 2 = + multi-frame outputs

HEADER = ["file", "i_or_x", "j_or_y", "vx", "vy", "corr_or_status"]
VEL_SERIES_HEADER = ["frame_id", "frame_index", "source_file", "x", "y", "us", "vs", "speed", "corr_raw", "w_corr"]
PHYSICS_TWIN_HEADER = ["frame_id", "t_capture", "x", "y", "us", "vs", "w_corr", "corr_raw", "camera_id"]
MULTIFRAME_OUTPUTS = ["vel_series.csv", "frames_manifest.json", "physics_twin_series.csv"]
LEGACY_OUTPUTS = ["vel_raw.csv", "vel_real.csv"]

_NUMBER = re.compile(r"^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$")
_NUMBER_ANY = re.compile(r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?")
_PIV_STEM = re.compile(r"^piv(\d+)$", re.IGNORECASE)
_DEFAULT_DT = 1.0 / 30.0


# ---------------------------------------------------------------------------
# shared
# ---------------------------------------------------------------------------
def newest_run(runs_dir=Path("runs")):
    """Return the newest directory below runs_dir, or None."""
    if not runs_dir.is_dir():
        return None
    candidates = [p for p in runs_dir.iterdir() if p.is_dir()]
    return max(candidates, key=lambda p: (p.stat().st_mtime, p.name), default=None)


def choose_run_dir(argument=None):
    """Resolve an explicit run directory or the newest ./runs subdirectory."""
    run_dir = Path(argument) if argument else newest_run()
    if run_dir is None:
        raise FileNotFoundError("No run directory was supplied and ./runs has no subdirectories.")
    run_dir = run_dir.expanduser()
    if not run_dir.is_dir():
        raise NotADirectoryError(f"Run directory does not exist: {run_dir}")
    return run_dir


def data_files(run_dir, kind):
    """Find raw piv*.dat files, or DAT files under vel_real (legacy ordering: relative path)."""
    directory = run_dir / kind
    if not directory.is_dir():
        return []
    files = []
    for path in directory.rglob("*"):
        if not path.is_file() or path.suffix.lower() != ".dat":
            continue
        if kind == "vel_raw" and not path.stem.lower().startswith("piv"):
            continue
        files.append(path)
    return sorted(files, key=lambda p: p.relative_to(directory).as_posix().lower())


def _is_number(value):
    return bool(_NUMBER.match(value))


# ---------------------------------------------------------------------------
# legacy export (behaviour and bytes identical to the schema-1 script)
# ---------------------------------------------------------------------------
def parse_data_file(path):
    """Yield rows with the first four numeric columns and any trailing field."""
    with path.open("r", encoding="utf-8", errors="replace") as stream:
        for line in stream:
            text = line.strip()
            if not text or text.startswith("#") or text.startswith(";"):
                continue
            fields = [item for item in re.split(r"[\s,]+", text) if item]
            # A DAT row is normally i/j (or x/y), vx, vy, then corr/status.
            if len(fields) < 4 or not all(_is_number(item) for item in fields[:4]):
                continue
            tail = " ".join(fields[4:]) if len(fields) > 4 else ""
            yield fields[0], fields[1], fields[2], fields[3], tail


def write_csv(run_dir, files, output_path):
    output_path.parent.mkdir(parents=True, exist_ok=True)
    row_count = 0
    with output_path.open("w", newline="", encoding="utf-8-sig") as stream:
        writer = csv.writer(stream)
        writer.writerow(HEADER)
        for path in files:
            relative_name = path.relative_to(run_dir).as_posix()
            for row in parse_data_file(path):
                writer.writerow([relative_name, *row])
                row_count += 1
    return row_count


def export_legacy(run_dir):
    export_dir = run_dir / "export"
    raw_files = data_files(run_dir, "vel_raw")
    raw_rows = write_csv(run_dir, raw_files, export_dir / "vel_raw.csv")
    real_files = data_files(run_dir, "vel_real")
    real_rows = None
    if real_files:
        real_rows = write_csv(run_dir, real_files, export_dir / "vel_real.csv")

    print(f"Run: {run_dir}")
    print(f"Wrote {export_dir / 'vel_raw.csv'} ({raw_rows} data rows from {len(raw_files)} file(s)).")
    if real_rows is not None:
        print(f"Wrote {export_dir / 'vel_real.csv'} ({real_rows} data rows from {len(real_files)} file(s)).")
    else:
        print("No vel_real/*.dat files found; only vel_raw.csv was written.")
    return raw_files, real_files


# ---------------------------------------------------------------------------
# multi-frame export
# ---------------------------------------------------------------------------
def _frame_sort_key(path):
    m = _PIV_STEM.match(path.stem)
    if m:
        return (0, int(m.group(1)), path.name.lower())
    return (1, path.name.lower())


def series_files(run_dir):
    """Velocity files for the frame series: vel_real (real-world metres) if present, else vel_raw."""
    for kind in ("vel_real", "vel_raw"):
        files = data_files(run_dir, kind)
        if files:
            return sorted(files, key=_frame_sort_key), kind
    return [], None


def parse_velocity_rows(path):
    """Yield (x, y, us, vs, corr_raw_str) strings; corr is '' when absent/non-numeric."""
    for x, y, us, vs, tail in parse_data_file(path):
        first = tail.split(" ", 1)[0] if tail else ""
        yield x, y, us, vs, (first if first and _is_number(first) else "")


def frame_id_for(path):
    m = _PIV_STEM.match(path.stem)
    return f"piv{int(m.group(1)):04d}" if m else path.stem


def frame_index_for(path, ordinal):
    m = _PIV_STEM.match(path.stem)
    return int(m.group(1)) if m else ordinal


def read_dt_seconds(run_dir):
    """Time interval from PIV_param.dat (value on the line after the title); default 1/30 s."""
    for path in (run_dir / "resolved_calib" / "PIV_param.dat", run_dir / "calib" / "PIV_param.dat",
                 Path("calib") / "PIV_param.dat"):
        if not path.is_file():
            continue
        try:
            lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            continue
        for i, line in enumerate(lines):
            if "time interval" not in line.lower():
                continue
            for candidate in lines[i:i + 3]:
                for token in _NUMBER_ANY.findall(candidate):
                    try:
                        value = float(token)
                    except ValueError:
                        continue
                    if 0 < value < 3600:
                        return value
    return _DEFAULT_DT


def load_camera_id(run_dir):
    for path in (run_dir / "config.json", Path("config.json")):
        if not path.is_file():
            continue
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        for key in ("camera_id", "cameraId", "cam_id"):
            if data.get(key):
                return str(data[key])
    return "cam_local"


def corr_to_w(corr_raw):
    """Map correlation to a weight in [0, 1]; '' if unknown."""
    if corr_raw == "":
        return ""
    try:
        v = float(corr_raw)
    except ValueError:
        return ""
    if math.isnan(v) or math.isinf(v):
        return ""
    w = abs(v)
    if w > 1.0:
        w = 1.0 / (1.0 + math.exp(-(w - 1.0)))
    return f"{max(0.0, min(1.0, w)):.6f}"


def export_multiframe(run_dir, physics_twin=True):
    files, kind = series_files(run_dir)
    if not files:
        print("No vel_real or vel_raw DAT files found; multi-frame outputs skipped.")
        return 0
    export_dir = run_dir / "export"
    export_dir.mkdir(parents=True, exist_ok=True)
    dt = read_dt_seconds(run_dir)
    camera_id = load_camera_id(run_dir)
    t0 = datetime.now(timezone.utc).replace(microsecond=0)

    series_path = export_dir / "vel_series.csv"
    twin_path = export_dir / "physics_twin_series.csv"
    manifest_path = export_dir / "frames_manifest.json"
    manifest = []
    total_rows = 0
    twin_fp = twin_path.open("w", newline="", encoding="utf-8") if physics_twin else None
    try:
        twin_writer = csv.writer(twin_fp) if twin_fp else None
        if twin_writer:
            twin_writer.writerow(PHYSICS_TWIN_HEADER)
        with series_path.open("w", newline="", encoding="utf-8") as series_fp:
            series_writer = csv.writer(series_fp)
            series_writer.writerow(VEL_SERIES_HEADER)
            for ordinal, path in enumerate(files, start=1):
                fid = frame_id_for(path)
                fidx = frame_index_for(path, ordinal)
                t_rel = (fidx - 1) * dt if fidx >= 1 else (ordinal - 1) * dt
                t_capture = (t0 + timedelta(seconds=t_rel)).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"
                rel = path.relative_to(run_dir).as_posix()
                point_count = 0
                for x, y, us, vs, corr in parse_velocity_rows(path):
                    speed = math.hypot(float(us), float(vs))
                    w = corr_to_w(corr)
                    series_writer.writerow([fid, fidx, rel, x, y, us, vs, f"{speed:.8g}", corr, w])
                    if twin_writer:
                        twin_writer.writerow([fid, t_capture, x, y, us, vs, w, corr, camera_id])
                    point_count += 1
                    total_rows += 1
                manifest.append({"frame_id": fid, "frame_index": fidx, "source_file": rel,
                                 "point_count": point_count, "t_rel_sec": round(t_rel, 6)})
    finally:
        if twin_fp:
            twin_fp.close()
    manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    note = " (source=vel_raw; x/y may be i/j pixel indices)" if kind == "vel_raw" else ""
    print(f"Wrote {series_path} ({total_rows} rows, {len(manifest)} frames){note}")
    print(f"Wrote {manifest_path}")
    if physics_twin:
        print(f"Wrote {twin_path}")
    return 0


# ---------------------------------------------------------------------------
def capabilities():
    return {"tool": "export_results.py", "export_schema": EXPORT_SCHEMA, "multiframe": True,
            "outputs": LEGACY_OUTPUTS + MULTIFRAME_OUTPUTS,
            "multiframe_outputs": MULTIFRAME_OUTPUTS, "velocity_source": ["vel_real", "vel_raw"]}


def build_parser():
    p = argparse.ArgumentParser(description="Export Fudaa velocity DAT files to CSV (legacy + multi-frame).")
    p.add_argument("run_dir", nargs="?", help="run directory; default: newest under ./runs")
    p.add_argument("--legacy-only", action="store_true", help="only vel_raw.csv / vel_real.csv (schema-1 behaviour)")
    p.add_argument("--no-physics-twin", action="store_true", help="skip physics_twin_series.csv")
    p.add_argument("--legacy", action="store_true", help=argparse.SUPPRESS)  # accepted for old multi-frame callers
    p.add_argument("--capabilities", action="store_true", help="print a JSON feature description and exit")
    return p


def main(argv=None):
    args = build_parser().parse_args(sys.argv[1:] if argv is None else argv)
    if args.capabilities:
        print(json.dumps(capabilities(), ensure_ascii=False))
        return 0
    try:
        run_dir = choose_run_dir(args.run_dir)
    except (FileNotFoundError, NotADirectoryError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 2
    export_legacy(run_dir)
    if args.legacy_only:
        return 0
    try:
        return export_multiframe(run_dir, physics_twin=not args.no_physics_twin)
    except (OSError, ValueError) as exc:
        print(f"Error: multi-frame export failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
