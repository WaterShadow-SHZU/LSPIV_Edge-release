# SPDX-License-Identifier: MIT
"""Regression tests for export_results.py (stdlib unittest; run: python3 -m unittest discover -s tests)."""
import csv
import io
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "export_results.py"
PHYSICS_TWIN_HEADER = ["frame_id", "t_capture", "x", "y", "us", "vs", "w_corr", "corr_raw", "camera_id"]
LEGACY_HEADER = ["file", "i_or_x", "j_or_y", "vx", "vy", "corr_or_status"]

POINTS = [("0.10", "2.50", "1.20", "-0.30", "0.91"),
          ("0.20", "2.50", "0.00", "0.00", "-99.000000000000000"),
          ("0.30", "2.50", "1.10", "0.05", "0.75")]


def make_run(root: Path, frames=3, real=True, raw=True, dt="0.016666666666666666") -> Path:
    run = root / "run"
    for k in range(1, frames + 1):
        body = "".join("%s %s %s %s %s\n" % p for p in POINTS)
        if raw:
            (run / "vel_raw").mkdir(parents=True, exist_ok=True)
            (run / "vel_raw" / ("piv%04d.dat" % k)).write_text(body)
        if real:
            (run / "vel_real").mkdir(parents=True, exist_ok=True)
            (run / "vel_real" / ("real_piv%04d.dat" % k)).write_text(body)
    (run / "resolved_calib").mkdir(parents=True, exist_ok=True)
    (run / "resolved_calib" / "PIV_param.dat").write_text(
        "# FileVersion 4.0 / IA Size\n20\nTime interval / Under sampling period\n%s 1\n" % dt)
    return run


def run_script(*args, cwd=None):
    return subprocess.run([sys.executable, str(SCRIPT), *map(str, args)], cwd=cwd,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)


def read_csv(path: Path, encoding="utf-8"):
    with path.open(newline="", encoding=encoding) as fp:
        return list(csv.reader(fp))


class ExportResultsTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = Path(self._tmp.name)

    def tearDown(self):
        self._tmp.cleanup()

    def test_legacy_outputs_unchanged(self):
        run = make_run(self.tmp)
        p = run_script(run)
        self.assertEqual(p.returncode, 0, p.stderr)
        for name in ("vel_raw.csv", "vel_real.csv"):
            raw = (run / "export" / name).read_bytes()
            self.assertTrue(raw.startswith(b"\xef\xbb\xbf"), "legacy CSV keeps the UTF-8 BOM")
            rows = read_csv(run / "export" / name, "utf-8-sig")
            self.assertEqual(rows[0], LEGACY_HEADER)
            self.assertEqual(len(rows) - 1, 3 * len(POINTS))
        rows = read_csv(run / "export" / "vel_real.csv", "utf-8-sig")
        self.assertEqual(rows[1], ["vel_real/real_piv0001.dat", "0.10", "2.50", "1.20", "-0.30", "0.91"])
        self.assertIn("Wrote", p.stdout)
        self.assertIn("vel_raw.csv (9 data rows from 3 file(s))", p.stdout)

    def test_multiframe_outputs(self):
        run = make_run(self.tmp, frames=4)
        p = run_script(run)
        self.assertEqual(p.returncode, 0, p.stderr)
        twin = read_csv(run / "export" / "physics_twin_series.csv")
        self.assertEqual(twin[0], PHYSICS_TWIN_HEADER)
        self.assertFalse((run / "export" / "physics_twin_series.csv").read_bytes().startswith(b"\xef\xbb\xbf"))
        frames = sorted({r[0] for r in twin[1:]})
        self.assertEqual(frames, ["real_piv0001", "real_piv0002", "real_piv0003", "real_piv0004"])
        manifest = json.loads((run / "export" / "frames_manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(len(manifest), 4)
        self.assertTrue(all(m["point_count"] == len(POINTS) for m in manifest))
        self.assertAlmostEqual(manifest[1]["t_rel_sec"], 0.016667, places=6)
        self.assertTrue((run / "export" / "vel_series.csv").is_file())
        self.assertEqual(twin[2][6], "1.000000")  # invalid -99 point: fudaa w_corr mapping kept as-is (downstream rewrites)

    def test_old_invocation_newest_run(self):
        runs = self.tmp / "runs"
        runs.mkdir()
        run = make_run(runs)
        p = run_script(cwd=str(self.tmp))  # no argument: newest ./runs/*
        self.assertEqual(p.returncode, 0, p.stderr)
        for name in ("vel_raw.csv", "vel_real.csv", "physics_twin_series.csv", "frames_manifest.json"):
            self.assertTrue((run / "export" / name).is_file(), name)

    def test_legacy_only_flag(self):
        run = make_run(self.tmp)
        self.assertEqual(run_script(run, "--legacy-only").returncode, 0)
        self.assertTrue((run / "export" / "vel_raw.csv").is_file())
        self.assertFalse((run / "export" / "physics_twin_series.csv").exists())

    def test_fallback_to_vel_raw(self):
        run = make_run(self.tmp, real=False)
        p = run_script(run)
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertFalse((run / "export" / "vel_real.csv").exists())
        twin = read_csv(run / "export" / "physics_twin_series.csv")
        self.assertEqual(twin[1][0], "piv0001")

    def test_empty_run_is_not_an_error(self):
        run = self.tmp / "empty"
        run.mkdir()
        p = run_script(run)
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertTrue((run / "export" / "vel_raw.csv").is_file())

    def test_missing_run_dir(self):
        self.assertEqual(run_script(self.tmp / "nope").returncode, 2)

    def test_capabilities_probe(self):
        p = run_script("--capabilities", cwd=str(self.tmp))
        self.assertEqual(p.returncode, 0, p.stderr)
        caps = json.load(io.StringIO(p.stdout))
        self.assertTrue(caps["multiframe"])
        self.assertGreaterEqual(caps["export_schema"], 2)
        for name in ("physics_twin_series.csv", "frames_manifest.json", "vel_raw.csv", "vel_real.csv"):
            self.assertIn(name, caps["outputs"])
        self.assertFalse((self.tmp / "runs").exists())


if __name__ == "__main__":
    unittest.main()
