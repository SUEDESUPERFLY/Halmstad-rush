#!/usr/bin/env python3
"""Bygger minikartans data från den genererade stadskartan (CityGrid.luau).

Skriver src/shared/Map/MinimapData.luau: rektanglar "x,z,b,d,typ" i studs, där typ är
0 = gata, 1 = huvudgata, 2 = vatten. Rektanglarna slås ihop så att minikartan blir lätt
(få GUI-objekt även på mobil).

Användning: python3 tools/map/build_minimap.py
"""

from __future__ import annotations

import re
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
GRID = ROOT / "src" / "server" / "Map" / "Generated" / "CityGrid.luau"
OUT = ROOT / "src" / "shared" / "Map" / "MinimapData.luau"
FACTOR = 6  # 6 terrängrutor (24 studs) per minikartruta


def load_grid() -> tuple[np.ndarray, int, int, int]:
    text = GRID.read_text(encoding="utf-8")
    cell = int(re.search(r"CellSize = (\d+)", text).group(1))
    ox = int(re.search(r"OriginX = (-?\d+)", text).group(1))
    oz = int(re.search(r"OriginZ = (-?\d+)", text).group(1))
    rows = re.findall(r'\t\t"([A-Z0-9]+)",', text)
    grid = []
    for row in rows:
        cells: list[str] = []
        for ch, n in re.findall(r"([A-Z])(\d+)", row):
            cells.extend([ch] * int(n))
        grid.append(cells)
    return np.array(grid), cell, ox, oz


def cover(mask: np.ndarray, max_size: int = 40) -> list[tuple[int, int, int, int]]:
    taken = ~mask.copy()
    rects = []
    h, w = mask.shape
    for z in range(h):
        x = 0
        while x < w:
            if taken[z, x]:
                x += 1
                continue
            rw = 1
            while x + rw < w and rw < max_size and not taken[z, x + rw]:
                rw += 1
            rh = 1
            while z + rh < h and rh < max_size and not taken[z + rh, x : x + rw].any():
                rh += 1
            taken[z : z + rh, x : x + rw] = True
            rects.append((x, z, rw, rh))
            x += rw
    return rects


def main() -> None:
    grid, cell, ox, oz = load_grid()
    h, w = grid.shape[0] // FACTOR, grid.shape[1] // FACTOR
    tiles = grid[: h * FACTOR, : w * FACTOR].reshape(h, FACTOR, w, FACTOR)
    water = (tiles == "W").mean(axis=(1, 3)) > 0.5
    main_road = np.isin(tiles, ["Y"]).mean(axis=(1, 3)) > 0.2
    road = (np.isin(tiles, ["A", "Y", "D"]).mean(axis=(1, 3)) > 0.3) & ~main_road

    size = FACTOR * cell
    entries = []
    for kind, mask in ((2, water), (0, road), (1, main_road)):
        for x, z, rw, rh in cover(mask):
            entries.append(f"{ox + x * size},{oz + z * size},{rw * size},{rh * size},{kind}")

    header = "--!strict\n-- GENERERAD av tools/map/build_minimap.py. Ändra inte för hand.\n"
    OUT.write_text(header + 'return "' + ";".join(entries) + '"\n', encoding="utf-8")
    print(f"Minikarta: {len(entries)} rektanglar -> {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
