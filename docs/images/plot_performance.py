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
"""Redraw docs/images/performance-comparison.png from the published notes.

The figure is saved only after the plotted values have been read back out of:

- docs/PERFORMANCE.md — 935-frame conversion, 48-frame orthorectification
  scaling, and the stage-time table
- docs/SOLVER-PATCHES.md — P2 and P5 size and solver read time
- docs/ARM-DEPLOYMENT-zh.md — img_pgm/ and img_transf/ on the 935-frame run

Requires matplotlib. Run from any working directory:

    python3 docs/images/plot_performance.py
"""

from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt


ROOT = Path(__file__).resolve().parents[2]
DOCS = ROOT / "docs"
OUT = Path(__file__).resolve().parent / "performance-comparison.png"

INK = "#1c2430"
MUTED = "#8e9aab"
ACCENT = "#1f4e79"
PALE = "#d5dde6"
GRID = "#e6e4df"
NOTE = "#3e4a57"


def strip_md(cell):
    return cell.replace("*", "").replace("`", "").strip()


def cells(line):
    return [strip_md(part) for part in line.strip().strip("|").split("|")]


def find_line(text, needle):
    for line in text.splitlines():
        if needle in line:
            return line
    raise SystemExit("Missing documented line containing: %s" % needle)


def require_file(name):
    path = DOCS / name
    if not path.is_file():
        raise SystemExit("Missing %s" % path)
    return path.read_text(encoding="utf-8")


def seconds_cell(cell):
    """Parse a PERFORMANCE.md cell such as '~172 s' or '**~16 s**'."""
    text = strip_md(cell).replace("~", "").replace("s", "").strip()
    return float(text)


def load_measurements():
    performance = require_file("PERFORMANCE.md")
    patches = require_file("SOLVER-PATCHES.md")
    arm = require_file("ARM-DEPLOYMENT-zh.md")

    if "935 frames of 1920×1080" not in performance:
        raise SystemExit("PERFORMANCE.md no longer describes the 935-frame 1920×1080 run")
    if "12-core desktop" not in performance:
        raise SystemExit("PERFORMANCE.md no longer names the 12-core desktop")
    if "Measured on 48-frame transform batches:" not in performance:
        raise SystemExit("PERFORMANCE.md no longer locates the orthorectification sweep")

    conversion = []
    for label in (
        "One ffmpeg per frame",
        "One ffmpeg per batch",
        "8 ffmpeg processes, P5 direct",
    ):
        row = cells(find_line(performance, label))
        if row[0] != label:
            raise SystemExit("Unexpected conversion row: %s" % row)
        conversion.append((label, seconds_cell(row[1])))

    scaling_line = find_line(performance, "| s/frame | 0.329 |")
    scaling_cells = cells(scaling_line)
    if scaling_cells[0] != "s/frame":
        raise SystemExit("Unexpected scaling row: %s" % scaling_cells)
    scaling = [float(value) for value in scaling_cells[1:]]
    processes = [1, 2, 4, 6, 8, 12]
    if len(scaling) != len(processes):
        raise SystemExit("Orthorectification sweep does not have 6 process counts")

    stage_specs = (
        ("Frame extraction (video → PNG).", "extraction"),
        ("Frame conversion (PNG → PGM)", "conversion"),
        ("Orthorectification (`transf_a`)", "ortho"),
        ("Cross-correlation (`PIV`)", "piv"),
        ("Real-coordinate conversion (`vel_real`)", "real"),
    )
    stages = {}
    for needle, key in stage_specs:
        row = cells(find_line(performance, needle))
        stages[key] = row[1]

    if stages["extraction"] != "~30 s":
        raise SystemExit("Frame extraction is %s, not '~30 s'" % stages["extraction"])
    if stages["conversion"] != "~16 s":
        raise SystemExit("Frame conversion stage is %s, not '~16 s'" % stages["conversion"])
    if stages["ortho"] != "~40 s":
        raise SystemExit("Orthorectification stage is %s, not '~40 s'" % stages["ortho"])
    if stages["piv"] != "~18 s":
        raise SystemExit("Cross-correlation stage is %s, not '~18 s'" % stages["piv"])
    if stages["real"] != "~12–16 s":
        raise SystemExit("Real-coordinate stage is %s, not '~12–16 s'" % stages["real"])
    ortho_share = cells(find_line(performance, "Orthorectification (`transf_a`)"))[2]
    if ortho_share != "~46 %":
        raise SystemExit("Orthorectification share is %s, not '~46 %'" % ortho_share)
    if "4.8× faster, output byte-identical." not in performance:
        raise SystemExit("PERFORMANCE.md no longer records the 4.8× byte-identical parse")
    before = cells(find_line(performance, "| Before |"))
    after = cells(find_line(performance, "| **After** |"))
    if before != ["Before", "0.335"] or after != ["After", "0.070"]:
        raise SystemExit("Parsing rows changed: %s / %s" % (before, after))
    if "0 difference across all 9 columns" not in performance:
        raise SystemExit("PERFORMANCE.md no longer records 0 difference across 9 columns")

    p2 = cells(find_line(patches, "**14.85 s / pair**"))
    p5 = cells(find_line(patches, "**0.25 s / pair**"))
    if p2[0] != "P2" or p2[3] != "~2.5 MB" or p2[4] != "14.85 s / pair":
        raise SystemExit("Unexpected P2 row: %s" % p2)
    if p5[0] != "P5" or p5[3] != "~0.64 MB" or p5[4] != "0.25 s / pair":
        raise SystemExit("Unexpected P5 row: %s" % p5)
    if "59×" not in patches:
        raise SystemExit("SOLVER-PATCHES.md no longer states the 59× gap")

    arm_line = find_line(arm, "img_pgm/")
    if "img_transf/" not in arm_line or "约 2.4 GB" not in arm_line or "约 0.6 GB" not in arm_line:
        raise SystemExit("ARM directory sizes changed: %s" % arm_line)

    return {
        "conversion_s": [item[1] for item in conversion],
        "processes": processes,
        "ortho_s_per_frame": scaling,
        "p2_mb": 2.5,
        "p5_mb": 0.64,
        "p2_s_per_pair": 14.85,
        "p5_s_per_pair": 0.25,
        "p2_dir_gb": 2.4,
        "p5_dir_gb": 0.6,
        "stage_s": (30, 16, 40, 18),
        "real_range_s": (12, 16),
    }


def style_axis(ax, grid="x"):
    ax.set_facecolor("white")
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    for side in ("left", "bottom"):
        ax.spines[side].set_color(INK)
        ax.spines[side].set_linewidth(0.6)
    ax.tick_params(colors=INK, labelsize=8.5, length=3, width=0.6)
    ax.grid(axis=grid, color=GRID, linewidth=0.6, zorder=0)
    ax.set_axisbelow(True)


def end_label(ax, x, y, text, color=INK):
    ax.text(x, y, text, va="center", ha="left", fontsize=8, color=color, clip_on=False)


def panel_title(ax, text):
    ax.set_title(text, loc="left", fontsize=11, color=INK, pad=7)


def color_tick(tick, accent):
    tick.set_color(ACCENT if accent else INK)


def draw(data):
    plt.rcParams.update({
        "font.family": "DejaVu Sans",
        "axes.unicode_minus": False,
        "figure.facecolor": "white",
        "savefig.facecolor": "white",
        "text.color": INK,
        "axes.labelcolor": INK,
    })

    fig = plt.figure(figsize=(8.6, 8.35), dpi=130)
    grid = fig.add_gridspec(
        2, 2,
        left=0.21, right=0.985, top=0.955, bottom=0.095,
        wspace=0.56, hspace=0.46,
        height_ratios=(1.0, 1.22),
    )

    draw_conversion(fig.add_subplot(grid[0, 0]), data)
    draw_ortho(fig.add_subplot(grid[0, 1]), data)
    draw_p5(fig, grid[1, 0].subgridspec(
        2, 2,
        height_ratios=(1.25, 1.05),
        width_ratios=(1.0, 1.0),
        wspace=0.48,
        hspace=1.15,
    ), data)
    draw_stages(fig.add_subplot(grid[1, 1]), data)

    fig.text(
        0.21, 0.038,
        "Blue marks the default in (a), (b), and (c), and the largest stage in (d).  "
        "The pale tip in (d) is the documented ~12–16 s range.",
        fontsize=7.4, color=NOTE, ha="left", va="bottom",
    )
    fig.text(
        0.21, 0.012,
        "Sources: docs/PERFORMANCE.md, docs/SOLVER-PATCHES.md, docs/ARM-DEPLOYMENT-zh.md.",
        fontsize=7.4, color=NOTE, ha="left", va="bottom",
    )
    fig.savefig(OUT)
    plt.close(fig)


def draw_conversion(ax, data):
    labels = (
        "One ffmpeg per frame",
        "One ffmpeg per batch",
        "8-way parallel, P5 direct",
    )
    values = data["conversion_s"]
    colors = (MUTED, MUTED, ACCENT)
    positions = (0, 1, 2)
    ax.barh(positions, values, color=colors, height=0.62, zorder=3)
    ax.set_yticks(positions, labels)
    ax.invert_yaxis()
    ax.set_xlabel("Seconds", fontsize=8.5)
    ax.set_xlim(0, 230)
    style_axis(ax, grid="x")
    panel_title(ax, "(a)  Frame conversion, 935 frames")
    for pos, value, color in zip(positions, values, colors):
        end_label(ax, value + 4, pos, "~%g s" % value, INK)
        color_tick(ax.get_yticklabels()[pos], color == ACCENT)
    ax.tick_params(axis="y", length=0)


def draw_ortho(ax, data):
    processes = data["processes"]
    values = data["ortho_s_per_frame"]
    positions = list(range(len(processes)))
    colors = [ACCENT if count == 4 else MUTED for count in processes]
    ax.bar(positions, values, color=colors, width=0.68, zorder=3)
    ax.set_xticks(positions, [str(count) for count in processes])
    ax.set_xlim(-0.55, len(processes) - 0.45)
    ax.set_ylim(0, 0.42)
    ax.set_xlabel("Processes, 48-frame batches", fontsize=8.5)
    ax.set_ylabel("Seconds per frame", fontsize=8.5)
    style_axis(ax, grid="y")
    panel_title(ax, "(b)  Orthorectification")
    for pos, value, count in zip(positions, values, processes):
        label_color = ACCENT if count == 4 else INK
        ax.text(
            pos, value + 0.010, "%.3f" % value,
            ha="center", va="bottom", fontsize=7.4, color=label_color,
        )
        color_tick(ax.get_xticklabels()[pos], count == 4)


def draw_p5(fig, inner, data):
    time_ax = fig.add_subplot(inner[0, :])
    mb_ax = fig.add_subplot(inner[1, 0])
    gb_ax = fig.add_subplot(inner[1, 1])

    labels = ("P2 ASCII", "P5 binary")
    positions = (0, 1)
    time_values = (data["p2_s_per_pair"], data["p5_s_per_pair"])
    time_colors = (MUTED, ACCENT)
    time_ax.barh(positions, time_values, color=time_colors, height=0.58, zorder=3)
    time_ax.set_yticks(positions, labels)
    time_ax.invert_yaxis()
    time_ax.set_xlim(0, 22)
    time_ax.set_xlabel("Seconds per pair", fontsize=8.5)
    style_axis(time_ax, grid="x")
    panel_title(time_ax, "(c)  Solver read, 1089×591")
    end_label(time_ax, time_values[0] + 0.35, 0, "14.85 s")
    end_label(time_ax, time_values[1] + 0.35, 1, "0.25 s", ACCENT)
    time_ax.text(8.2, 1, "59×", va="center", ha="left", fontsize=10, color=INK)
    for pos, color in zip(positions, time_colors):
        color_tick(time_ax.get_yticklabels()[pos], color == ACCENT)
    time_ax.tick_params(axis="y", length=0)

    paired_bars(
        mb_ax,
        (data["p2_mb"], data["p5_mb"]),
        "Image (MB)",
        ("~2.5", "~0.64"),
        3.7,
    )
    paired_bars(
        gb_ax,
        (data["p2_dir_gb"], data["p5_dir_gb"]),
        "GB each\nimg_pgm/\nimg_transf/",
        ("~2.4", "~0.6"),
        3.6,
    )


def paired_bars(ax, values, title, labels, xlim, xlabel=None):
    positions = (0, 1)
    colors = (MUTED, ACCENT)
    ax.barh(positions, values, color=colors, height=0.58, zorder=3)
    ax.set_yticks(positions, ("P2", "P5"))
    ax.invert_yaxis()
    ax.set_xlim(0, xlim)
    style_axis(ax, grid="x")
    ax.set_title(title, loc="left", fontsize=8.5, color=INK, pad=3)
    if xlabel:
        ax.set_xlabel(xlabel, fontsize=7)
    for pos, value_label, color in zip(positions, labels, colors):
        end_label(ax, values[pos] + xlim * 0.03, pos, value_label, ACCENT if color == ACCENT else INK)
        color_tick(ax.get_yticklabels()[pos], color == ACCENT)
    ax.tick_params(axis="y", labelsize=8, length=0)


def draw_stages(ax, data):
    labels = (
        "Frame extraction",
        "PNG → PGM",
        "Orthorectification",
        "Cross-correlation",
        "Real coordinates",
    )
    positions = (0, 1, 2, 3, 4)
    point_values = data["stage_s"]
    real_low, real_high = data["real_range_s"]
    colors = (MUTED, MUTED, ACCENT, MUTED, MUTED)
    ax.barh(positions[:4], point_values, color=colors[:4], height=0.58, zorder=3)
    ax.barh(positions[4], real_low, color=MUTED, height=0.58, zorder=3)
    ax.barh(
        positions[4], real_high - real_low, left=real_low,
        color=PALE, height=0.58, zorder=3,
    )
    ax.set_yticks(positions, labels)
    ax.invert_yaxis()
    ax.set_xlim(0, 54)
    ax.set_xlabel("Seconds", fontsize=8.5)
    style_axis(ax, grid="x")
    panel_title(ax, "(d)  Stage time, 935-frame run")
    for pos, value in zip(positions[:4], point_values):
        end_label(ax, value + 0.8, pos, "~%g s" % value)
    end_label(ax, real_high + 0.8, positions[4], "~12–16 s")
    for pos, color in zip(positions, colors):
        color_tick(ax.get_yticklabels()[pos], color == ACCENT)
    ax.tick_params(axis="y", length=0)


def main():
    data = load_measurements()
    draw(data)
    print("Wrote %s" % OUT)
    print("conversion_s", data["conversion_s"])
    print("ortho_s_per_frame", list(zip(data["processes"], data["ortho_s_per_frame"])))
    print(
        "p5",
        data["p2_s_per_pair"], data["p5_s_per_pair"],
        data["p2_mb"], data["p5_mb"],
        data["p2_dir_gb"], data["p5_dir_gb"],
    )
    print("stages", data["stage_s"], data["real_range_s"])


if __name__ == "__main__":
    main()
