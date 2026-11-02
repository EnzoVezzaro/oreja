#!/usr/bin/env python3
"""Generates Oreja's pixel companion: Vincent, a small postman of the ear.

Vincent is drawn on a 40x40 pixel grid, five frames wide, and written as one PNG sprite sheet to
`site/assets/oreja-vincent.png`. The macOS app copies that same file into its bundle and slices the
frames, so the web and the app can never drift apart.

    python3 scripts/vincent-sprite.py

Frames, left to right:
    0  idle          eyes open, ear at rest
    1  idle blink    the quiet blink that keeps the character alive
    2  listening     sound marks, open mouth, the working ear lights up
    3  listening blink
    4  ouch          the click joke: scissors on the bandaged ear, eyes shut, mouth open

He is a painter, not a portrait: a straw hat, a rust beard, the bandage over the ear he gave away,
and one working ear on the other side. Palette values mirror `apps/macos/Theme.swift`,
`site/styles.css` and `docs/brand.md`.
"""

import struct
import zlib
from pathlib import Path

GRID = 40
SCALE = 8
FRAMES = 5

OUTLINE = "#2B2723"
SKIN = "#F7C29D"
SKIN_LIGHT = "#FCE0C8"
SKIN_SHADOW = "#E39C74"
BEARD = "#B4502F"
BEARD_LIGHT = "#C9704A"
BEARD_DEEP = "#8E3A22"
MOUTH = "#6B2718"
BANDAGE = "#FFF6EC"
BANDAGE_SHADE = "#E8D9C6"
HAT = "#E7B44C"
HAT_LIGHT = "#F2C96F"
HAT_SHADE = "#C08F35"
HAT_BAND = "#3A342E"
COAT = "#33506F"
COAT_LIGHT = "#476B92"
COAT_DEEP = "#243B53"
EAR_INNER = "#E77952"
EAR_LIGHT = "#F6A07C"
WAVE = "#C9714B"
STEEL = "#544C42"
FLOWER_PETAL = "#E7B44C"
FLOWER_HEART = "#3A342E"


class Pixels:
    """A tiny paint surface. Coordinates are pixel cells, origin top-left."""

    def __init__(self, size=GRID):
        self.size = size
        self.cells = {}

    def set(self, x, y, color):
        if 0 <= x < self.size and 0 <= y < self.size:
            self.cells[(x, y)] = color

    def get(self, x, y):
        return self.cells.get((x, y))

    def fill_ellipse(self, cx, cy, rx, ry, color, tilt=0.0):
        import math

        cos, sin = math.cos(tilt), math.sin(tilt)
        for y in range(int(cy - rx - ry) - 2, int(cy + rx + ry) + 3):
            for x in range(int(cx - rx - ry) - 2, int(cx + rx + ry) + 3):
                dx, dy = x - cx, y - cy
                u = dx * cos + dy * sin
                v = -dx * sin + dy * cos
                if (u / rx) ** 2 + (v / ry) ** 2 <= 1.0:
                    self.set(x, y, color)

    def rect(self, x0, y0, x1, y1, color):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self.set(x, y, color)

    def round_rect(self, x0, y0, x1, y1, color, corner=1):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                near_x = min(x - x0, x1 - x)
                near_y = min(y - y0, y1 - y)
                if near_x + near_y < corner:
                    continue
                self.set(x, y, color)

    def arc(self, cx, cy, radius, start_deg, end_deg, color, thickness=1.0):
        import math

        steps = int(abs(end_deg - start_deg) * 4 * radius / 40) + 40
        for step in range(steps + 1):
            angle = math.radians(start_deg + (end_deg - start_deg) * step / steps)
            x = cx + radius * math.cos(angle)
            y = cy + radius * math.sin(angle)
            spread = max(1, int(round(thickness)))
            for dy in range(-spread, spread + 1):
                for dx in range(-spread, spread + 1):
                    px, py = int(round(x)) + dx, int(round(y)) + dy
                    if (px - x) ** 2 + (py - y) ** 2 <= (thickness / 2 + 0.15) ** 2:
                        self.set(px, py, color)


def stamp(art, layer, force_outline=False):
    """Draw a layer: ink edge on its silhouette, then its own colours on top.

    `force_outline` also inks edges that sit on an already-painted area, which is what separates the
    beard from the face and the hat from the hair.
    """
    cells = set(layer.cells)
    for (x, y) in cells:
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if (nx, ny) in cells:
                continue
            if force_outline or art.get(nx, ny) is None:
                art.set(nx, ny, OUTLINE)
    for (x, y), colour in layer.cells.items():
        art.set(x, y, colour)


def draw_vincent(listening=False, blink=False, ouch=False) -> Pixels:
    art = Pixels()

    # --- Shoulders: a painter's coat, the one cool colour in the palette ---------------
    coat = Pixels()
    coat.round_rect(6, 34, 33, 39, COAT, corner=4)
    coat.rect(15, 33, 24, 35, COAT)
    stamp(art, coat)
    for (x, y) in ((12, 36), (12, 37), (11, 38), (27, 36), (27, 37), (28, 38)):
        art.set(x, y, COAT_DEEP)
    for (x, y) in ((9, 37), (10, 37), (10, 38), (8, 38)):
        art.set(x, y, COAT_LIGHT)
    # A cream shirt collar, so the neck is not a hole.
    art.rect(18, 33, 21, 35, BANDAGE)

    # --- Neck ---------------------------------------------------------------------------
    art.rect(17, 31, 22, 34, SKIN)
    art.rect(17, 34, 22, 34, SKIN_SHADOW)

    # --- Head: deliberately large, so the face still reads at 80 pt ---------------------
    head = Pixels()
    head.fill_ellipse(20.0, 21.5, 11.4, 11.6, SKIN)
    head.fill_ellipse(20.0, 27.5, 8.6, 6.0, SKIN)
    stamp(art, head)

    for (x, y) in ((10, 15), (10, 16), (9, 17), (11, 14), (12, 13), (13, 12)):
        art.set(x, y, SKIN_LIGHT)
    for (x, y) in ((29, 25), (29, 23), (28, 27), (28, 29), (26, 32), (25, 31)):
        art.set(x, y, SKIN_SHADOW)

    # --- Beard: the loudest thing about him ---------------------------------------------
    beard = Pixels()
    beard.fill_ellipse(20.0, 29.6, 9.2, 6.0, BEARD)
    beard.fill_ellipse(20.0, 25.4, 9.0, 1.8, BEARD)
    stamp(art, beard, force_outline=True)
    moustache = Pixels()
    moustache.fill_ellipse(16.4, 25.2, 3.0, 1.3, BEARD_LIGHT)
    moustache.fill_ellipse(23.6, 25.2, 3.0, 1.3, BEARD_LIGHT)
    for (x, y), colour in moustache.cells.items():
        if art.get(x, y) in (BEARD, OUTLINE):
            art.set(x, y, colour)
    for (x, y) in ((12, 32), (13, 34), (16, 36), (26, 33), (24, 35), (22, 32)):
        art.set(x, y, BEARD_DEEP)

    # The mouth sits under the moustache, wide enough to survive a 2x downscale.
    if ouch:
        # A rounded shout, not a black box.
        art.rect(19, 26, 21, 26, OUTLINE)
        art.rect(18, 27, 22, 29, OUTLINE)
        art.rect(19, 30, 21, 30, OUTLINE)
        art.rect(19, 27, 21, 29, MOUTH)
    elif listening:
        art.rect(18, 27, 22, 28, OUTLINE)
        art.rect(19, 28, 21, 28, MOUTH)
    else:
        art.rect(18, 27, 22, 27, OUTLINE)

    # --- Eyes and brows -----------------------------------------------------------------
    if ouch:
        for (x, y) in ((12, 20), (13, 19), (14, 19), (15, 20)):
            art.set(x, y, OUTLINE)
        for (x, y) in ((24, 20), (25, 19), (26, 19), (27, 20)):
            art.set(x, y, OUTLINE)
    elif blink:
        art.rect(13, 19, 15, 19, OUTLINE)
        art.rect(24, 19, 26, 19, OUTLINE)
    else:
        art.rect(13, 18, 15, 20, OUTLINE)
        art.rect(24, 18, 26, 20, OUTLINE)
        art.set(13, 18, BANDAGE)
        art.set(13, 19, BANDAGE)
        art.set(24, 18, BANDAGE)
        art.set(24, 19, BANDAGE)
    art.rect(12, 16, 16, 16, BEARD_DEEP)
    art.rect(23, 16, 27, 16, BEARD_DEEP)
    art.set(19, 22, SKIN_SHADOW)
    art.set(20, 22, SKIN_SHADOW)
    art.set(11, 20, SKIN_LIGHT)
    art.set(11, 21, SKIN_LIGHT)
    art.set(12, 21, SKIN_LIGHT)

    # --- The bandage over the ear he gave away ------------------------------------------
    # A compact gauze patch on the ear line, not a stripe across the face: at 80 pt the shape of
    # the patch is what says "bandage", and a wide wrap just reads as a second cheek.
    if not ouch:
        bandage = Pixels()
        bandage.round_rect(8, 19, 11, 25, BANDAGE, corner=1)
        stamp(art, bandage, force_outline=True)
        for (x, y) in ((8, 21), (10, 21), (8, 23), (10, 23)):
            art.set(x, y, BANDAGE_SHADE)
        art.set(9, 26, BANDAGE_SHADE)

    # --- Straw hat ----------------------------------------------------------------------
    brim = Pixels()
    brim.fill_ellipse(20.0, 11.4, 14.6, 2.5, HAT)
    stamp(art, brim, force_outline=True)
    crown = Pixels()
    crown.fill_ellipse(20.0, 6.6, 8.6, 5.2, HAT)
    stamp(art, crown, force_outline=True)
    for (x, y) in ((7, 12), (8, 12), (9, 13), (10, 13), (11, 13), (12, 13), (13, 13)):
        art.set(x, y, HAT_LIGHT)
    for (x, y) in ((28, 13), (29, 13), (30, 12), (31, 12), (32, 11), (33, 11)):
        art.set(x, y, HAT_SHADE)
    for (x, y) in ((25, 5), (26, 6), (26, 7), (24, 4), (23, 4)):
        art.set(x, y, HAT_SHADE)
    for (x, y) in ((15, 4), (16, 3), (16, 2), (17, 3)):
        art.set(x, y, HAT_LIGHT)
    art.rect(12, 7, 27, 8, HAT_BAND)
    # A small sunflower pinned to the coat: the one prop he is allowed.
    for (x, y) in ((9, 36), (11, 36), (10, 35), (10, 37)):
        art.set(x, y, FLOWER_PETAL)
    art.set(10, 36, FLOWER_HEART)

    # --- The ear that still works, on the other side of the bandage ----------------------
    ear = Pixels()
    ear.fill_ellipse(31.7, 23.4, 2.2, 3.3, SKIN)
    stamp(art, ear)
    # An ink edge on the inner side too, or at 8x the ear reads as a lump on the cheek.
    art.arc(31.7, 23.4, 2.2, 96, 264, OUTLINE, thickness=1.0)
    art.arc(32.6, 23.4, 1.3, 300, 60, SKIN_SHADOW, thickness=1.0)
    art.set(31, 22, EAR_INNER)
    art.set(31, 23, EAR_INNER)
    art.set(31, 24, EAR_INNER)
    if listening:
        art.set(31, 22, EAR_LIGHT)
        art.set(31, 23, EAR_LIGHT)
        art.set(31, 24, EAR_LIGHT)

    if ouch:
        # The click joke, drawn last so nothing covers it: the patch leaves his head and hangs
        # in the air beside him, with motion ticks back to the empty ear.
        patch = Pixels()
        patch.round_rect(1, 15, 6, 21, BANDAGE, corner=1)
        stamp(art, patch, force_outline=True)
        art.set(2, 17, BANDAGE_SHADE)
        art.set(4, 19, BANDAGE_SHADE)
        for (x, y) in ((8, 15), (9, 12), (7, 18)):
            art.set(x, y, WAVE)
        for (x, y) in ((9, 23), (7, 25)):
            art.set(x, y, WAVE)

    if listening:
        # Sound reaching the ear that is left.
        art.arc(30.0, 23.5, 6.4, -52, 52, WAVE, thickness=1.0)
        art.arc(30.0, 23.5, 8.8, -42, 42, WAVE, thickness=1.0)

    return art


def png_bytes(width, height, rows):
    """Minimal RGBA PNG encoder: no third-party imaging library needed."""
    raw = b"".join(b"\x00" + row for row in rows)
    compressed = zlib.compress(raw, 9)

    def chunk(kind, data):
        payload = kind + data
        return struct.pack(">I", len(data)) + payload + struct.pack(">I", zlib.crc32(payload) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", compressed)
        + chunk(b"IEND", b"")
    )


def hex_rgba(value):
    value = value.lstrip("#")
    return (int(value[0:2], 16), int(value[2:4], 16), int(value[4:6], 16), 255)


def main():
    # `--preview 2` writes build/vincent-preview.png at an integer scale, which is how the frames are
    # judged: the sprite must read at 80 px, not only at the 8x authoring scale.
    preview_scale = None
    if len(__import__("sys").argv) == 3 and __import__("sys").argv[1] == "--preview":
        preview_scale = int(__import__("sys").argv[2])

    frames = [
        draw_vincent(),
        draw_vincent(blink=True),
        draw_vincent(listening=True),
        draw_vincent(listening=True, blink=True),
        draw_vincent(ouch=True),
    ]

    scale = preview_scale or SCALE
    width = GRID * FRAMES * scale
    height = GRID * scale
    rows = []
    for y in range(GRID):
        row = bytearray()
        for art in frames:
            for x in range(GRID):
                colour = art.get(x, y)
                rgba = hex_rgba(colour) if colour else (0, 0, 0, 0)
                row.extend(bytes(rgba) * scale)
        for _ in range(scale):
            rows.append(bytes(row))

    root = Path(__file__).resolve().parent.parent
    if preview_scale:
        target = root / "build" / "vincent-preview.png"
    else:
        target = root / "site" / "assets" / "oreja-vincent.png"
    target.write_bytes(png_bytes(width, height, rows))
    print(f"wrote {target.name} — {width}x{height}, {FRAMES} frames")


if __name__ == "__main__":
    main()
