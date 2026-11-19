#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 LSPIV_Edge contributors
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
"""Create an optional quiver preview for one velocity DAT file."""

import sys

from export_results import choose_run_dir, data_files, parse_data_file


def main(argv=None):
    try:
        import matplotlib.pyplot as plt
    except ImportError:
        print("matplotlib is not installed; use export_csv.bat or export_results.py and open the CSV in Excel.")
        print("\u672a\u68c0\u6d4b\u5230 matplotlib\uff1b\u8bf7\u4f7f\u7528 export_csv.bat \u6216 export_results.py \u5bfc\u51fa CSV\uff0c\u518d\u7528 Excel \u67e5\u770b\u3002")
        return 0

    argv = sys.argv[1:] if argv is None else argv
    try:
        run_dir = choose_run_dir(argv[0] if argv else None)
    except (FileNotFoundError, NotADirectoryError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 2

    real_files = data_files(run_dir, "vel_real")
    raw_files = data_files(run_dir, "vel_raw")
    source = real_files[0] if real_files else (raw_files[0] if raw_files else None)
    if source is None:
        print("No vel_real or vel_raw DAT files found; no preview was created.")
        print("\u6ca1\u6709\u627e\u5230 vel_real \u6216 vel_raw \u7684 DAT \u6587\u4ef6\uff0c\u672a\u751f\u6210\u9884\u89c8\u56fe\u3002")
        return 0

    rows = list(parse_data_file(source))
    if not rows:
        print(f"No numeric velocity rows found in {source}; no preview was created.")
        return 0

    x = [float(row[0]) for row in rows]
    y = [float(row[1]) for row in rows]
    vx = [float(row[2]) for row in rows]
    vy = [float(row[3]) for row in rows]
    output = run_dir / "preview.png"

    figure, axes = plt.subplots(figsize=(10, 7))
    axes.quiver(x, y, vx, vy, angles="xy", scale_units="xy", scale=None)
    axes.set_xlabel("x / i")
    axes.set_ylabel("y / j")
    axes.set_title(f"Velocity preview: {source.name}")
    axes.set_aspect("equal", adjustable="datalim")
    figure.tight_layout()
    figure.savefig(output, dpi=150)
    plt.close(figure)
    print(f"Saved preview: {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
