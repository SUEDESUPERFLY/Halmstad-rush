#!/usr/bin/env python3
"""Gör om Halmstads stadskarta (raster) till speldata.

Indata: en PNG renderad från turistkartan (pdftoppm -r 194), där 1 pixel ≈ 2 m.
Utdata (Luau-moduler i src/server/Map/Generated/):
  CityGrid.luau       markmaterial per 4x4-studs-ruta (RLE per rad)
  CityBuildings.luau  husfotavtryck: x, z, bredd, djup, höjd, stil
  CityRoadPoints.luau respawnpunkter mitt på gatorna med riktning

Skala: 1 kartpixel = 2 studs (≈ 1:3,6 mot verkligheten, som GTA komprimerar).
Origo (0, 0) ligger på Stora torg. X = öster, Z = söder.

Användning:
  pdftoppm -r 194 -png karta.pdf city
  python3 tools/map/build_city.py city-1.png [--preview preview.png]
"""

from __future__ import annotations

import argparse
import math
import random
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "src" / "server" / "Map" / "Generated"

FOOTER_Y = 1474  # lila sidfot på kartan börjar här
ORIGIN_PX = (1136, 652)  # Stora torg (vald så att origo hamnar på 4-studs-rutnätet)
STUDS_PER_PX = 2
CELL_PX = 2  # en terrängruta = 2x2 px = 4x4 studs
CELL_STUDS = CELL_PX * STUDS_PER_PX
SEED = 1307

# Klasser (bokstav = kod i RLE)
CLASSES = {
    "A": "road",
    "Y": "mainroad",
    "B": "block",
    "P": "park",
    "W": "water",
    "G": "grey",
    "F": "field",
    "S": "sports",
    "R": "redbuilding",
    "N": "sand",
    "D": "bridgedeck",
}
CODES = list(CLASSES.keys())

PALETTE = [
    ("A", (248, 248, 248)),
    ("A", (248, 248, 232)),
    ("Y", (248, 232, 8)),
    ("Y", (248, 232, 40)),
    ("Y", (248, 216, 24)),
    ("B", (248, 216, 152)),
    ("B", (248, 216, 136)),
    ("B", (248, 216, 168)),
    ("B", (248, 200, 152)),
    ("B", (248, 200, 136)),
    ("B", (232, 200, 152)),
    ("B", (232, 200, 168)),
    ("P", (184, 216, 168)),
    ("P", (184, 200, 168)),
    ("P", (184, 216, 152)),
    ("P", (184, 200, 152)),
    ("P", (200, 216, 168)),
    ("W", (184, 232, 248)),
    ("W", (168, 216, 232)),
    ("W", (168, 224, 248)),
    ("G", (216, 216, 216)),
    ("G", (232, 232, 232)),
    ("G", (200, 200, 200)),
    ("G", (232, 232, 248)),
    ("G", (216, 216, 232)),
    ("F", (232, 248, 200)),
    ("F", (216, 240, 184)),
    ("S", (104, 168, 136)),
    ("S", (120, 176, 144)),
    ("R", (200, 136, 104)),
    ("R", (184, 120, 88)),
    ("R", (208, 144, 112)),
]
MAX_COLOR_DISTANCE = 30

# Ytor (i studs, x0, z0, x1, z1) där husgeneratorn inte bygger: landmärken som byggs för hand.
# Kustremsa som läggs till söder om kartan (kartan slutar strax norr om kusten)
SOUTH_ROWS = 50  # 200 studs
STRANDVAGEN_ROWS = (30, 36)  # rader i remsan som blir Strandvägen
BEACH_START_ROW = 37

RESERVED = [
    (-70, 290, 50, 385),  # Halmstads slott
    (-150, 50, -65, 105),  # S:t Nikolai kyrka
    (265, -250, 355, -170),  # Stadsbiblioteket
    (-90, -50, 85, 50),  # Stora torg
    (-420, -1190, -370, -1130),  # Utsiktstornet på Galgberget
    (-250, -1120, -170, -1050),  # Hallandsgården
]


def classify(img: np.ndarray) -> np.ndarray:
    """Närmaste palettfärg per pixel, -1 = okänt (text, symboler, linjer)."""
    h, w, _ = img.shape
    colors = np.array([c for _, c in PALETTE], dtype=np.int32)
    labels = np.array([CODES.index(code) for code, _ in PALETTE], dtype=np.int16)
    best = np.full((h, w), 1e9, dtype=np.float32)
    result = np.full((h, w), -1, dtype=np.int16)
    for color, label in zip(colors, labels):
        dist = np.sqrt(((img - color) ** 2).sum(axis=2)).astype(np.float32)
        better = dist < best
        best[better] = dist[better]
        result[better] = label
    result[best > MAX_COLOR_DISTANCE] = -1
    return result


def remove_small(classes: np.ndarray, code: str, min_size: int) -> None:
    label_id = CODES.index(code)
    mask = classes == label_id
    components, count = ndimage.label(mask)
    if count == 0:
        return
    sizes = ndimage.sum(mask, components, range(1, count + 1))
    small = np.isin(components, np.nonzero(sizes < min_size)[0] + 1)
    classes[small] = -1


def fill_unknown(classes: np.ndarray) -> np.ndarray:
    unknown = classes < 0
    _, (iy, ix) = ndimage.distance_transform_edt(unknown, return_indices=True)
    return classes[iy, ix]


def mode_filter(classes: np.ndarray, size: int) -> np.ndarray:
    best = np.zeros(classes.shape, dtype=np.float32)
    out = classes.copy()
    for label in range(len(CODES)):
        score = ndimage.uniform_filter((classes == label).astype(np.float32), size=size)
        better = score > best
        best[better] = score[better]
        out[better] = label
    return out


def downsample(classes: np.ndarray) -> np.ndarray:
    h, w = classes.shape
    h2, w2 = h // CELL_PX, w // CELL_PX
    trimmed = classes[: h2 * CELL_PX, : w2 * CELL_PX]
    counts = np.zeros((len(CODES), h2, w2), dtype=np.int16)
    for label in range(len(CODES)):
        m = (trimmed == label).reshape(h2, CELL_PX, w2, CELL_PX).sum(axis=(1, 3))
        counts[label] = m
    # Vägar vinner oavgjort, så att smala gator inte bryts
    for priority in ("A", "Y"):
        counts[CODES.index(priority)] = counts[CODES.index(priority)] * 2 + 1
    return counts.argmax(axis=0).astype(np.int16)


def clean_isolated(grid: np.ndarray) -> np.ndarray:
    """Ensamma celler (brus från text) tar grannarnas vanligaste klass."""
    h, w = grid.shape
    padded = np.pad(grid, 1, mode="edge")
    neighbours = [padded[1 + dz : 1 + dz + h, 1 + dx : 1 + dx + w] for dz in (-1, 0, 1) for dx in (-1, 0, 1) if dz or dx]
    same = sum((n == grid).astype(np.int8) for n in neighbours)
    counts = np.stack([sum((n == label).astype(np.int8) for n in neighbours) for label in range(len(CODES))])
    majority = counts.argmax(axis=0).astype(grid.dtype)
    out = grid.copy()
    isolated = same <= 1
    out[isolated] = majority[isolated]
    print(f"Rensade {int(isolated.sum())} ensamma celler")
    return out


def add_south_coast(grid: np.ndarray) -> np.ndarray:
    """Förlänger kartan söderut till havet: gator fortsätter, Strandvägen och stränder."""
    code = CODES.index
    bottom = grid[-1]
    h, w = grid.shape
    strip = np.full((SOUTH_ROWS, w), code("P"), dtype=grid.dtype)
    water_cols = bottom == code("W")
    road_cols = (bottom == code("A")) | (bottom == code("Y"))
    # Nissan = det sammanhängande vattenpartiet i nedersta raden som ligger närmast Stora torg
    runs, start = [], None
    for col in range(w + 1):
        is_water = col < w and water_cols[col]
        if is_water and start is None:
            start = col
        elif not is_water and start is not None:
            runs.append((start, col - 1))
            start = None
    origin_col = ORIGIN_PX[0] / CELL_PX
    river_min, river_max = min(runs, key=lambda r: abs((r[0] + r[1]) / 2 - origin_col))
    for col in range(w):
        if water_cols[col]:
            strip[:, col] = code("W")
            continue
        near_river = river_min - 150 <= col <= river_max + 150
        strip[:BEACH_START_ROW, col] = code("G") if near_river else code("P")
        if road_cols[col]:
            strip[: STRANDVAGEN_ROWS[0], col] = bottom[col]
        strip[STRANDVAGEN_ROWS[0] : STRANDVAGEN_ROWS[1], col] = code("A")
        strip[BEACH_START_ROW:, col] = code("N")
    # Bro där Strandvägen korsar Nissan
    strip[STRANDVAGEN_ROWS[0] : STRANDVAGEN_ROWS[1], river_min : river_max + 1] = code("A")
    print(f"Nissans mynning: kolumn {river_min}-{river_max} -> x {cell_to_world(river_min, 0)[0]:.0f}..{cell_to_world(river_max, 0)[0]:.0f}")
    return np.vstack([grid, strip])


def mark_bridges(grid: np.ndarray) -> None:
    """Väg över vatten blir brodäck (vatten under) i stället för en massiv damm."""
    code = CODES.index
    water = grid == code("W")
    road = (grid == code("A")) | (grid == code("Y"))
    reach = 6
    near = np.zeros_like(water)
    for dx in range(-reach, reach + 1):
        for dz in range(-reach, reach + 1):
            near |= np.roll(np.roll(water, dz, axis=0), dx, axis=1)
    left = np.zeros_like(water)
    right = np.zeros_like(water)
    up = np.zeros_like(water)
    down = np.zeros_like(water)
    for d in range(1, reach + 1):
        left |= np.roll(water, d, axis=1)
        right |= np.roll(water, -d, axis=1)
        up |= np.roll(water, d, axis=0)
        down |= np.roll(water, -d, axis=0)
    deck = road & near & ((left & right) | (up & down))
    grid[deck] = code("D")
    print(f"Brodäck: {int(deck.sum())} celler")


def cell_to_world(cx: float, cz: float) -> tuple[float, float]:
    """Mittpunkt för en ruta i studs."""
    px = (cx + 0.5) * CELL_PX
    pz = (cz + 0.5) * CELL_PX
    return (px - ORIGIN_PX[0]) * STUDS_PER_PX, (pz - ORIGIN_PX[1]) * STUDS_PER_PX


def world_origin() -> tuple[float, float]:
    """Världskoordinat för rutnätets hörn (cell 0,0 övre vänstra hörn)."""
    return -ORIGIN_PX[0] * STUDS_PER_PX, -ORIGIN_PX[1] * STUDS_PER_PX


def in_reserved(x: float, z: float, margin: float = 0) -> bool:
    for x0, z0, x1, z1 in RESERVED:
        if x0 - margin <= x <= x1 + margin and z0 - margin <= z <= z1 + margin:
            return True
    return False


def cover_rects(mask: np.ndarray, max_w: int, max_h: int) -> list[tuple[int, int, int, int]]:
    """Girig täckning av en mask med axelparallella rektanglar (cx, cz, w, h) i celler."""
    taken = ~mask.copy()
    rects = []
    h, w = mask.shape
    for cz in range(h):
        row = taken[cz]
        cx = 0
        while cx < w:
            if row[cx]:
                cx += 1
                continue
            rw = 1
            while cx + rw < w and rw < max_w and not row[cx + rw]:
                rw += 1
            rh = 1
            while cz + rh < h and rh < max_h and not taken[cz + rh, cx : cx + rw].any():
                rh += 1
            taken[cz : cz + rh, cx : cx + rw] = True
            rects.append((cx, cz, rw, rh))
            cx += rw
    return rects


def generate_buildings(grid: np.ndarray, rng: random.Random) -> list[tuple[int, int, int, int, int, int]]:
    buildings = []
    block = grid == CODES.index("B")
    red = grid == CODES.index("R")
    h, w = grid.shape
    zz, xx = np.mgrid[0:h, 0:w]
    wx, wz = cell_to_world(xx, zz)
    dist = np.sqrt(wx**2 + wz**2)

    depth = ndimage.distance_transform_edt(block)

    def add(cx, cz, rw, rh, height, style, inset=0.0):
        x0, z0 = cell_to_world(cx - 0.5, cz - 0.5)
        width = rw * CELL_STUDS - inset * 2
        length = rh * CELL_STUDS - inset * 2
        x = x0 + rw * CELL_STUDS / 2
        z = z0 + rh * CELL_STUDS / 2
        if width < 6 or length < 6 or in_reserved(x, z):
            return
        buildings.append((round(x), round(z), round(width), round(length), round(height), style))

    # Stadskärna: slutna kvarter längs gatan med gård i mitten (svensk stenstad)
    core = block & (dist < 750) & (depth <= 5)
    for cx, cz, rw, rh in cover_rects(core, 7, 7):
        add(cx, cz, rw, rh, rng.uniform(18, 34), 0)

    # Mellanzon: flerfamiljshus, lite glesare
    middle = block & (dist >= 750) & (dist < 1500) & (depth <= 4)
    for cx, cz, rw, rh in cover_rects(middle, 6, 6):
        if rng.random() < 0.85:
            add(cx, cz, rw, rh, rng.uniform(14, 24), 1, inset=1)

    # Ytterområden: villor på tomter
    outer = block & (dist >= 1500)
    step = 7
    for cz in range(0, h - 4, step):
        for cx in range(0, w - 4, step):
            ox, oz = cx + rng.randint(0, 2), cz + rng.randint(0, 2)
            rw, rh = (4, 3) if rng.random() < 0.5 else (3, 4)
            if oz + rh < h and ox + rw < w and outer[oz : oz + rh, ox : ox + rw].all() and rng.random() < 0.85:
                add(ox, oz, rw, rh, rng.uniform(9, 13), 2, inset=0.5)

    # Mörkröda större byggnader (sjukhus, skolor, offentliga hus)
    for cx, cz, rw, rh in cover_rects(red, 10, 10):
        add(cx, cz, rw, rh, rng.uniform(22, 36), 3)

    return buildings


def road_points(grid: np.ndarray) -> list[tuple[int, int, int]]:
    road = (grid == CODES.index("A")) | (grid == CODES.index("Y"))
    depth = ndimage.distance_transform_edt(road)
    h, w = grid.shape
    points = []
    tile = 10
    for tz in range(0, h, tile):
        for tx in range(0, w, tile):
            window = depth[tz : tz + tile, tx : tx + tile]
            if window.size == 0 or window.max() < 2:
                continue
            iz, ix = np.unravel_index(window.argmax(), window.shape)
            cz, cx = tz + iz, tx + ix
            # Gatans riktning: huvudaxeln för vägceller i närheten
            r = 6
            z0, z1 = max(0, cz - r), min(h, cz + r + 1)
            x0, x1 = max(0, cx - r), min(w, cx + r + 1)
            ys, xs = np.nonzero(road[z0:z1, x0:x1])
            if len(xs) < 5:
                continue
            cov = np.cov(np.vstack([xs - xs.mean(), ys - ys.mean()]))
            vals, vecs = np.linalg.eigh(cov)
            dx, dz = vecs[:, vals.argmax()]
            yaw = math.degrees(math.atan2(-dx, -dz))
            x, z = cell_to_world(cx, cz)
            points.append((round(x), round(z), round(yaw)))
    return points


# NPC-rutter längs huvudgatorna. Ankare i rutnätsceller (kolumn, rad), snäpps till närmaste
# gula huvudgata. Rutten mellan ankarna hittas med A* på gatunätet. Körriktning = listans ordning.
ROUTES = {
    # Slottsgatan över Nissan -> Viktoriagatan -> Wrangelsgatan norrut -> Järnvägsleden -> Timmermansleden
    "StoraRingen": [(505, 382), (640, 378), (720, 420), (880, 540), (1050, 680), (1010, 420), (990, 250), (830, 140), (600, 20), (545, 165), (358, 330), (430, 375)],
    # Järnvägsleden söderut -> Slottsjordsvägen -> tillbaka mot Slottsgatan
    "Vastra": [(358, 330), (240, 495), (310, 490), (420, 450), (500, 400)],
}
LANE_OFFSET = 4.0  # studs till höger om gatans mitt (högertrafik)
ROUTE_STEP = 5  # celler mellan vägpunkter (20 studs)


def snap_anchor(grid: np.ndarray, cx: int, cz: int) -> tuple[int, int]:
    yellow = grid == CODES.index("Y")
    road = yellow | (grid == CODES.index("A"))
    for mask, radius in ((yellow, 18), (road, 30)):
        z0, z1 = max(0, cz - radius), min(grid.shape[0], cz + radius + 1)
        x0, x1 = max(0, cx - radius), min(grid.shape[1], cx + radius + 1)
        ys, xs = np.nonzero(mask[z0:z1, x0:x1])
        if len(xs):
            d = (xs + x0 - cx) ** 2 + (ys + z0 - cz) ** 2
            i = d.argmin()
            return int(xs[i] + x0), int(ys[i] + z0)
    raise SystemExit(f"Inget gatuläge nära ankaret {(cx, cz)}")


def astar(cost: np.ndarray, start: tuple[int, int], goal: tuple[int, int]) -> list[tuple[int, int]]:
    import heapq

    h, w = cost.shape
    sx, sz = start
    gx, gz = goal
    best = {start: 0.0}
    came: dict[tuple[int, int], tuple[int, int]] = {}
    heap = [(0.0, 0.0, start)]
    steps = [(dx, dz, math.hypot(dx, dz)) for dx in (-1, 0, 1) for dz in (-1, 0, 1) if dx or dz]
    while heap:
        _, g, node = heapq.heappop(heap)
        if node == goal:
            path = [node]
            while node in came:
                node = came[node]
                path.append(node)
            return path[::-1]
        if g > best.get(node, math.inf):
            continue
        x, z = node
        for dx, dz, length in steps:
            nx, nz = x + dx, z + dz
            if 0 <= nx < w and 0 <= nz < h and cost[nz, nx] < math.inf:
                ng = g + length * cost[nz, nx]
                if ng < best.get((nx, nz), math.inf):
                    best[(nx, nz)] = ng
                    came[(nx, nz)] = node
                    heapq.heappush(heap, (ng + math.hypot(gx - nx, gz - nz) * 0.6, ng, (nx, nz)))
    raise SystemExit(f"Ingen väg mellan {start} och {goal}")


def build_routes(grid: np.ndarray) -> dict[str, list[tuple[float, float]]]:
    code = CODES.index
    road = (grid == code("A")) | (grid == code("Y")) | (grid == code("D"))
    depth = ndimage.distance_transform_edt(road)
    cost = np.full(grid.shape, math.inf)
    cost[road] = 1 + 3 / np.maximum(depth[road], 1)  # håll dig mitt på gatan
    cost[grid == code("Y")] *= 0.6  # föredra huvudgator
    routes = {}
    for name, anchors in ROUTES.items():
        snapped = [snap_anchor(grid, cx, cz) for cx, cz in anchors]
        cells: list[tuple[int, int]] = []
        for i in range(len(snapped)):
            leg = astar(cost, snapped[i], snapped[(i + 1) % len(snapped)])
            cells.extend(leg[:-1])
        sampled = cells[::ROUTE_STEP]
        world = np.array([cell_to_world(cx, cz) for cx, cz in sampled])
        # Utjämning (cirkulär) så att kurvorna blir mjuka
        smooth = (np.roll(world, 1, axis=0) + world * 2 + np.roll(world, -1, axis=0)) / 4
        ahead = np.roll(smooth, -1, axis=0) - np.roll(smooth, 1, axis=0)
        norms = np.linalg.norm(ahead, axis=1, keepdims=True)
        direction = ahead / np.maximum(norms, 1e-6)
        right = np.stack([-direction[:, 1], direction[:, 0]], axis=1)
        lane = smooth + right * LANE_OFFSET
        routes[name] = [(float(x), float(z)) for x, z in lane]
        length = np.linalg.norm(np.roll(lane, -1, axis=0) - lane, axis=1).sum()
        print(f"Rutt {name}: {len(lane)} punkter, {length:.0f} studs")
    return routes


def rle_rows(grid: np.ndarray) -> list[str]:
    rows = []
    for row in grid:
        parts = []
        current = row[0]
        count = 0
        for value in row:
            if value == current:
                count += 1
            else:
                parts.append(f"{CODES[current]}{count}")
                current, count = value, 1
        parts.append(f"{CODES[current]}{count}")
        rows.append("".join(parts))
    return rows


def write_lua(name: str, body: str) -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    header = "--!strict\n-- GENERERAD av tools/map/build_city.py. Ändra inte för hand.\n"
    (OUT_DIR / f"{name}.luau").write_text(header + body, encoding="utf-8")


def save_preview(grid: np.ndarray, buildings, points, path: str, routes=None) -> None:
    colors = {
        "A": (90, 90, 95),
        "Y": (60, 60, 60),
        "B": (225, 215, 195),
        "P": (110, 170, 90),
        "W": (60, 150, 220),
        "G": (170, 170, 175),
        "F": (190, 210, 120),
        "S": (70, 140, 80),
        "R": (225, 215, 195),
        "N": (235, 215, 160),
        "D": (150, 110, 90),
    }
    lut = np.array([colors[c] for c in CODES], dtype=np.uint8)
    img = lut[grid]
    scale = 1
    im = Image.fromarray(img)
    from PIL import ImageDraw

    d = ImageDraw.Draw(im)
    ox, oz = world_origin()
    for x, z, w, l, h, style in buildings:
        cx0 = (x - w / 2 - ox) / CELL_STUDS
        cz0 = (z - l / 2 - oz) / CELL_STUDS
        cx1 = (x + w / 2 - ox) / CELL_STUDS
        cz1 = (z + l / 2 - oz) / CELL_STUDS
        col = [(200, 120, 90), (210, 160, 120), (230, 120, 100), (150, 70, 60)][style]
        d.rectangle([cx0 * scale, cz0 * scale, cx1 * scale, cz1 * scale], fill=col)
    for x, z, _ in points:
        cx = (x - ox) / CELL_STUDS
        cz = (z - oz) / CELL_STUDS
        d.point((cx, cz), fill=(255, 255, 0))
    for i, route in enumerate((routes or {}).values()):
        color = [(255, 0, 255), (0, 255, 255)][i % 2]
        coords = [((x - ox) / CELL_STUDS, (z - oz) / CELL_STUDS) for x, z in route]
        d.line(coords + coords[:1], fill=color, width=3)
    im.save(path)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("image")
    parser.add_argument("--preview")
    args = parser.parse_args()

    img = np.asarray(Image.open(args.image).convert("RGB")).astype(np.int32)[:FOOTER_Y]
    classes = classify(img)
    remove_small(classes, "W", 400)  # P-skyltar och ikoner är också blå
    remove_small(classes, "R", 60)  # röda symboler (kyrkor, sevärdheter)
    remove_small(classes, "S", 80)
    remove_small(classes, "G", 300)  # lila stadsdelsnamn blir annars grå fläckar
    classes = fill_unknown(classes)
    classes = mode_filter(classes, 3)
    grid = downsample(classes)
    grid = clean_isolated(grid)
    grid = add_south_coast(grid)
    mark_bridges(grid)

    rng = random.Random(SEED)
    buildings = generate_buildings(grid, rng)
    points = road_points(grid)

    h, w = grid.shape
    ox, oz = world_origin()
    rows = rle_rows(grid)
    body = "return {\n"
    body += f"\tCellSize = {CELL_STUDS},\n\tWidth = {w},\n\tHeight = {h},\n"
    body += f"\tOriginX = {ox},\n\tOriginZ = {oz},\n"
    body += '\tCodes = "' + "".join(CODES) + '",\n'
    body += "\tRows = {\n" + "".join(f'\t\t"{r}",\n' for r in rows) + "\t},\n}\n"
    write_lua("CityGrid", body)

    lines = ";".join(f"{x},{z},{bw},{bl},{bh},{s}" for x, z, bw, bl, bh, s in buildings)
    write_lua("CityBuildings", f'return "{lines}"\n')

    pts = ";".join(f"{x},{z},{yaw}" for x, z, yaw in points)
    write_lua("CityRoadPoints", f'return "{pts}"\n')

    routes = build_routes(grid)
    route_body = "return {\n"
    for name, route in routes.items():
        route_body += f'\t{name} = "' + ";".join(f"{x:.0f},{z:.0f}" for x, z in route) + '",\n'
    route_body += "}\n"
    write_lua("CityRoutes", route_body)

    counts = {CODES[i]: int((grid == i).sum()) for i in range(len(CODES))}
    print(f"Rutnät {w}x{h} celler ({w * CELL_STUDS}x{h * CELL_STUDS} studs), origo {ox},{oz}")
    print("Celler per klass:", counts)
    print(f"Byggnader: {len(buildings)}  Respawnpunkter: {len(points)}  RLE-längd: {sum(len(r) for r in rows)}")
    if args.preview:
        save_preview(grid, buildings, points, args.preview, routes)


if __name__ == "__main__":
    main()
