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
"""Redraw the Performance figures from the published notes.

Four landscape figures are written only after the plotted values have
been read back out of:

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
from matplotlib import font_manager, ticker
import matplotlib.pyplot as plt


ROOT = Path(__file__).resolve().parents[2]
DOCS = ROOT / "docs"
OUT_DIR = Path(__file__).resolve().parent

INK = "#1b2430"
MUTED = "#97a2ad"
ACCENT = "#1f4e79"
PALE = "#c5ced6"
GRID = "#ecece8"
NOTE = "#5c6670"
PAPER = "#ffffff"

# Optional; DejaVu Sans is the fallback when these files are not present.
_FONT_CANDIDATES = (
    Path("/usr/share/fonts/truetype/sand-box/custom/Source Sans Pro/SourceSansPro-Regular.ttf"),
    Path("/usr/share/fonts/truetype/sand-box/custom/Source Sans Pro/SourceSansPro-Semibold.ttf"),
    Path("/usr/share/fonts/truetype/sand-box/custom/Source Sans Pro/SourceSansPro-Bold.ttf"),
    Path("/usr/share/fonts/truetype/sand-box/custom/Source Sans Pro/SourceSansPro-It.ttf"),
)


def setup_fonts():
    family = "DejaVu Sans"
    for path in _FONT_CANDIDATES:
        if path.is_file():
            font_manager.fontManager.addfont(str(path))
            family = "Source Sans Pro"
    plt.rcParams.update({
        "font.family": family,
        "font.size": 11,
        "axes.unicode_minus": False,
        "figure.facecolor": PAPER,
        "savefig.facecolor": PAPER,
        "text.color": INK,
        "axes.labelcolor": INK,
        "axes.titleweight": "semibold",
    })
    return family


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
    ax.set_facecolor(PAPER)
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    ax.spines["left"].set_visible(grid == "y")
    for side in ("left", "bottom"):
        ax.spines[side].set_color(INK)
        ax.spines[side].set_linewidth(0.7)
    ax.tick_params(colors=INK, labelsize=11, length=0 if grid == "x" else 3, width=0.7)
    if grid == "x":
        ax.tick_params(axis="x", length=3)
    ax.grid(axis=grid, color=GRID, linewidth=0.8, zorder=0)
    ax.set_axisbelow(True)


def bar_label(ax, value, pos, text, xlim, inside_ok=True, color=INK):
    """Place a label inside a long bar, otherwise just past the end."""
    if inside_ok and value / xlim >= 0.28:
        ax.text(
            value - xlim * 0.018, pos, text,
            va="center", ha="right", fontsize=11, color="white",
            fontweight="semibold", clip_on=False, zorder=4,
        )
    else:
        ax.text(
            value + xlim * 0.018, pos, text,
            va="center", ha="left", fontsize=11, color=color,
            clip_on=False, zorder=4,
        )


def new_figure(width, height, left, right, top, bottom):
    fig, ax = plt.subplots(figsize=(width, height), dpi=160)
    fig.subplots_adjust(left=left, right=right, top=top, bottom=bottom)
    return fig, ax


def figure_title(fig, text, x):
    fig.text(
        x, 0.93, text,
        ha="left", va="top", fontsize=14, color=INK, fontweight="semibold",
    )


def save(fig, name):
    path = OUT_DIR / name
    fig.savefig(path, dpi=160)
    plt.close(fig)
    print("Wrote %s (%d bytes)" % (path, path.stat().st_size))
    return path


def draw_conversion(data):
    labels = (
        "One ffmpeg per frame",
        "One ffmpeg per batch",
        "8-way parallel, P5 direct",
    )
    values = data["conversion_s"]
    colors = (MUTED, MUTED, ACCENT)
    positions = (0, 1, 2)
    xlim = 210

    fig, ax = new_figure(10.8, 3.25, left=0.26, right=0.97, top=0.80, bottom=0.20)
    figure_title(fig, "Frame conversion  ·  935 frames of 1920×1080", x=0.02)
    ax.barh(positions, values, color=colors, height=0.62, zorder=3)
    ax.set_yticks(positions, labels)
    ax.invert_yaxis()
    ax.set_xlim(0, xlim)
    ax.set_xlabel("Seconds", fontsize=11)
    style_axis(ax, grid="x")
    for pos, value, color in zip(positions, values, colors):
        text = "~%g s" % value
        bar_label(ax, value, pos, text, xlim, color=ACCENT if color == ACCENT else INK)
        ax.get_yticklabels()[pos].set_color(ACCENT if color == ACCENT else INK)
        if color == ACCENT:
            ax.get_yticklabels()[pos].set_fontweight("semibold")
    save(fig, "performance-conversion.png")


def draw_ortho(data):
    processes = data["processes"]
    values = data["ortho_s_per_frame"]
    positions = list(range(len(processes)))
    colors = [ACCENT if count == 4 else MUTED for count in processes]

    fig, ax = new_figure(10.8, 3.65, left=0.10, right=0.97, top=0.78, bottom=0.20)
    figure_title(fig, "Orthorectification  ·  fastest at 4 processes (the default)", x=0.02)
    ax.plot(positions, values, color="#8a96a2", linewidth=1.6, zorder=2)
    ax.bar(positions, values, color=colors, width=0.58, zorder=3)
    ax.set_xticks(positions, [str(count) for count in processes])
    ax.set_xlim(-0.55, len(processes) - 0.45)
    ax.set_ylim(0, 0.40)
    ax.yaxis.set_major_locator(ticker.MultipleLocator(0.10))
    ax.set_xlabel("Processes  ·  48-frame batches", fontsize=11)
    ax.set_ylabel("Seconds per frame", fontsize=11)
    style_axis(ax, grid="y")
    ax.spines["left"].set_visible(True)
    for pos, value, count in zip(positions, values, processes):
        is_default = count == 4
        ax.text(
            pos, value + 0.012, "%.3f" % value,
            ha="center", va="bottom", fontsize=10.5,
            color=ACCENT if is_default else INK,
            fontweight="semibold" if is_default else "regular",
        )
        ax.get_xticklabels()[pos].set_color(ACCENT if is_default else INK)
        if is_default:
            ax.get_xticklabels()[pos].set_fontweight("semibold")
    save(fig, "performance-ortho.png")


def draw_p5(data):
    fig = plt.figure(figsize=(10.8, 3.7), dpi=160)
    figure_title(fig, "Solver read format  ·  1089×591 image", x=0.02)
    grid = fig.add_gridspec(
        1, 3,
        left=0.13, right=0.98, top=0.74, bottom=0.20,
        wspace=0.62,
    )
    time_ax = fig.add_subplot(grid[0, 0])
    mb_ax = fig.add_subplot(grid[0, 1])
    gb_ax = fig.add_subplot(grid[0, 2])

    def pair(ax, values, labels, xlim, xlabel, title):
        positions = (0, 1)
        colors = (MUTED, ACCENT)
        names = ("P2 ASCII", "P5 binary")
        ax.barh(positions, values, color=colors, height=0.58, zorder=3)
        ax.set_yticks(positions, names)
        ax.invert_yaxis()
        ax.set_xlim(0, xlim)
        ax.set_xlabel(xlabel, fontsize=10.5)
        style_axis(ax, grid="x")
        ax.set_title(title, loc="left", fontsize=11, color=NOTE, pad=8, fontweight="regular")
        for pos, value, text, color in zip(positions, values, labels, colors):
            bar_label(
                ax, value, pos, text, xlim,
                inside_ok=(value / xlim >= 0.28),
                color=ACCENT if color == ACCENT else INK,
            )
            ax.get_yticklabels()[pos].set_color(ACCENT if color == ACCENT else INK)
            if color == ACCENT:
                ax.get_yticklabels()[pos].set_fontweight("semibold")

    pair(
        time_ax,
        (data["p2_s_per_pair"], data["p5_s_per_pair"]),
        ("14.85 s", "0.25 s"),
        18.5,
        "Seconds per pair",
        "Read time  ·  59× faster",
    )
    pair(
        mb_ax,
        (data["p2_mb"], data["p5_mb"]),
        ("~2.5 MB", "~0.64 MB"),
        3.4,
        "Megabytes",
        "One image",
    )
    pair(
        gb_ax,
        (data["p2_dir_gb"], data["p5_dir_gb"]),
        ("~2.4 GB", "~0.6 GB"),
        3.2,
        "Gigabytes",
        "Each of img_pgm/ and img_transf/",
    )
    save(fig, "performance-p5.png")


def draw_stages(data):
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
    xlim = 58

    fig, ax = new_figure(10.8, 3.85, left=0.22, right=0.97, top=0.80, bottom=0.28)
    figure_title(fig, "Stage time  ·  same 935-frame run", x=0.02)
    ax.barh(positions[:4], point_values, color=colors[:4], height=0.58, zorder=3)
    ax.barh(positions[4], real_low, color=MUTED, height=0.58, zorder=3)
    ax.barh(
        positions[4], real_high - real_low, left=real_low,
        color=PALE, height=0.58, zorder=3,
    )
    ax.set_yticks(positions, labels)
    ax.invert_yaxis()
    ax.set_xlim(0, xlim)
    ax.set_xlabel("Seconds", fontsize=11)
    style_axis(ax, grid="x")
    for pos, value in zip(positions[:4], point_values):
        extra = "  ·  largest stage, ~46%" if pos == 2 else ""
        color = ACCENT if pos == 2 else INK
        bar_label(ax, value, pos, "~%g s%s" % (value, extra), xlim, color=color)
        ax.get_yticklabels()[pos].set_color(color)
        if pos == 2:
            ax.get_yticklabels()[pos].set_fontweight("semibold")
    bar_label(ax, real_high, positions[4], "~12–16 s", xlim, inside_ok=False)
    ax.get_yticklabels()[4].set_color(INK)
    fig.text(
        0.22, 0.055,
        "The light tip on Real coordinates is the documented 12–16 s range.",
        ha="left", va="bottom", fontsize=9.5, color=NOTE,
    )
    save(fig, "performance-stages.png")


def main():
    setup_fonts()
    data = load_measurements()

    draw_conversion(data)
    draw_ortho(data)
    draw_p5(data)
    draw_stages(data)

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
