#!/usr/bin/env python3
"""More Vincent, more places: the desk diorama and the back view.

    python3 scripts/vincent-scenes.py

`scripts/vincent-sprite.py` draws Vincent himself. This script draws the two scenes the site
needs around him, in the same palette and on the same kind of pixel grid:

    site/assets/vincent-desk.png   56 x 44 cells, x8   Vincent listening at his desk, with a
                                                      record player, a mug and a small painting
    site/assets/vincent-back.png   32 x 40 cells, x8   Vincent from behind, watching the sunrise

Both are static images. The site animates the light around them (a lamp pulse, a rising sun),
never the character's pose, and the app keeps owning the real state frames.
"""

import math
import struct
import zlib
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "site" / "assets"

# The same palette as vincent-sprite.py, so the scenes and the sprite sheet cannot drift.
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

# Scene-only values.
WALL = "#0A0D24"
WALL_LIGHT = "#151A38"
WALL_GLOW = "#221C3C"
WOOD = "#4A3220"
WOOD_TOP = "#6B4A2C"
WOOD_DEEP = "#2C1D12"
VINYL = "#141119"
VINYL_LIGHT = "#201C28"
LABEL = "#E7B44C"
METAL = "#9A938A"
MUG = "#FFF6EC"
STEAM = "#D8CFC0"
FRAME = "#E7B44C"
NIGHT_PAINT = "#1B2450"
PAINT_LIGHT = "#3B4C8C"
PAINT_STAR = "#F7EFD9"
HEADPHONE = "#2E2C38"
HEADPHONE_LIGHT = "#4A4756"


class Pixels:
    """A paint surface in cells, origin top-left."""

    def __init__(self, w, h, fill=None):
        self.w = w
        self.h = h
        self.cells = {}
        if fill:
            for y in range(h):
                for x in range(w):
                    self.cells[(x, y)] = fill

    def set(self, x, y, color):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.cells[(int(x), int(y))] = color

    def get(self, x, y):
        return self.cells.get((int(x), int(y)))

    def rect(self, x0, y0, x1, y1, color):
        for y in range(int(y0), int(y1) + 1):
            for x in range(int(x0), int(x1) + 1):
                self.set(x, y, color)

    def ellipse(self, cx, cy, rx, ry, color):
        for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
            for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
                if ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1.0:
                    self.set(x, y, color)

    def line(self, x0, y0, x1, y1, color, thick=1):
        steps = int(max(abs(x1 - x0), abs(y1 - y0)) * 2) + 1
        for i in range(steps + 1):
            t = i / steps
            x = x0 + (x1 - x0) * t
            y = y0 + (y1 - y0) * t
            for d in range(thick):
                self.set(round(x) + d, round(y), color)

    def shade(self, points, color):
        for (x, y) in points:
            self.set(x, y, color)

    def write(self, path, scale):
        rows = bytearray()
        for y in range(self.h):
            line = bytearray()
            for x in range(self.w):
                hexval = self.cells.get((x, y))
                if hexval is None:
                    # Transparent cells scale like any other, or the row comes out short.
                    line += b"\x00\x00\x00\x00" * scale
                    continue
                r = int(hexval[1:3], 16)
                g = int(hexval[3:5], 16)
                b = int(hexval[5:7], 16)
                line += bytes((r, g, b, 255)) * scale
            for _ in range(scale):
                rows += b"\x00" + line

        def chunk(tag, data):
            return (
                struct.pack(">I", len(data))
                + tag
                + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
            )

        header = struct.pack(">IIBBBBB", self.w * scale, self.h * scale, 8, 6, 0, 0, 0)
        png = (
            b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", header)
            + chunk(b"IDAT", zlib.compress(bytes(rows), 9))
            + chunk(b"IEND", b"")
        )
        path.write_bytes(png)
        print(f"{path.relative_to(OUT.parent.parent)}  {self.w * scale}x{self.h * scale}  {len(png) // 1024} KB")


def vincent_head(p, cx, cy, hat=True, phones=False):
    """The same head as the sprite sheet: straw hat, rust beard, bandaged left ear."""
    # Beard first, so the face sits on top of it.
    p.ellipse(cx, cy + 6.2, 6.4, 5.2, BEARD_DEEP)
    p.ellipse(cx, cy + 5.4, 5.9, 4.6, BEARD)
    p.ellipse(cx - 1.6, cy + 4.6, 2.6, 2.2, BEARD_LIGHT)
    # Face.
    p.ellipse(cx, cy, 5.9, 6.2, SKIN)
    p.ellipse(cx - 2.2, cy - 1.0, 2.0, 2.4, SKIN_LIGHT)
    p.ellipse(cx + 3.2, cy + 0.6, 1.8, 2.6, SKIN_SHADOW)
    # Eyes and brows.
    p.rect(cx - 3, cy - 1, cx - 2, cy, OUTLINE)
    p.rect(cx + 2, cy - 1, cx + 3, cy, OUTLINE)
    p.rect(cx - 4, cy - 3, cx - 2, cy - 3, BEARD_DEEP)
    p.rect(cx + 2, cy - 3, cx + 4, cy - 3, BEARD_DEEP)
    # Nose and mouth.
    p.rect(cx, cy + 1, cx, cy + 2, SKIN_SHADOW)
    p.rect(cx - 1, cy + 4, cx + 2, cy + 4, MOUTH)
    # The bandage, on his left ear (viewer's left).
    p.rect(cx - 7, cy - 2, cx - 5, cy + 3, BANDAGE)
    p.rect(cx - 7, cy + 2, cx - 5, cy + 3, BANDAGE_SHADE)
    # The listening ear.
    p.ellipse(cx + 6.4, cy + 1.4, 1.7, 2.4, SKIN)
    p.ellipse(cx + 6.6, cy + 1.4, 1.0, 1.6, EAR_INNER)
    p.set(cx + 7, cy, EAR_LIGHT)

    if hat:
        p.ellipse(cx, cy - 7.6, 10.2, 2.6, HAT_SHADE)
        p.ellipse(cx, cy - 8.2, 9.6, 2.0, HAT)
        p.ellipse(cx, cy - 11.2, 6.6, 4.4, HAT)
        p.ellipse(cx - 2.4, cy - 11.8, 3.2, 2.2, HAT_LIGHT)
        p.rect(cx - 7, cy - 9, cx + 7, cy - 8, HAT_BAND)

    if phones:
        # Cups on both ears, hinged up to the hat brim. A band drawn over the crown would cover
        # the hat and read as a comb at this grid size, so it stays behind the brim.
        for side in (-1, 1):
            ex = cx + side * 7.1
            p.ellipse(ex, cy + 1.0, 2.5, 3.1, HEADPHONE)
            p.ellipse(ex, cy + 1.0, 1.6, 2.1, HEADPHONE_LIGHT)
            p.set(ex, cy + 1, LABEL)
            p.line(ex, cy - 1, ex + side * 1.0, cy - 5, HEADPHONE, thick=1)


def build_desk():
    w, h = 56, 44
    p = Pixels(w, h, WALL)

    # The wall glow: rings of slightly warmer indigo behind the desk.
    p.ellipse(34, 20, 26, 18, WALL_LIGHT)
    p.ellipse(34, 21, 18, 14, WALL_GLOW)
    p.ellipse(33, 21, 12, 10, "#33284F")
    # A warm pool from the little lamp on the desk, behind his shoulder.
    p.ellipse(44, 22, 8, 7, "#3E2A44")
    p.ellipse(44, 22, 5, 4, "#4A2E42")

    # A small painting on the wall: a night of his own, two cells of star and a swirl.
    p.rect(5, 6, 17, 18, FRAME)
    p.rect(6, 7, 16, 17, NIGHT_PAINT)
    p.ellipse(11, 13, 4, 3, PAINT_LIGHT)
    p.ellipse(11, 13, 2, 2, NIGHT_PAINT)
    p.set(13, 10, PAINT_STAR)
    p.set(9, 15, PAINT_STAR)
    p.set(8, 9, "#8E6A3A")
    p.set(16, 18, "#8E6A3A")

    # Desk slab: top edge, body, then a darker shadow under it.
    p.rect(0, 30, w - 1, 31, "#8A6238")
    p.rect(0, 32, w - 1, 37, WOOD)
    p.rect(0, 32, w - 1, 32, WOOD_TOP)
    p.rect(0, 38, w - 1, 40, WOOD_DEEP)

    # Record player, left of the desk.
    p.rect(3, 23, 23, 31, "#4E3520")
    p.rect(3, 23, 23, 23, "#8A6238")
    p.rect(4, 24, 22, 30, "#2A1D14")
    p.ellipse(12, 27, 7.4, 3.4, "#1F1B28")
    for r in (6.4, 5.2, 4.0):
        p.ellipse(12, 27, r, r * 0.46, "#2E2938" if int(r) % 2 == 0 else "#1F1B28")
    p.ellipse(12, 27, 2.0, 1.0, LABEL)
    p.set(11, 27, "#F7DFA6")
    p.set(12, 27, OUTLINE)
    # Tonearm: one clean L, arm down onto the record. Anything curvier reads as a scribble.
    p.rect(18, 23, 21, 23, "#CFC7BC")
    p.line(18, 23, 14, 26, METAL)
    p.set(21, 23, METAL)
    p.set(13, 26, "#CFC7BC")

    # Vincent, seated behind the desk.
    p.ellipse(36, 33, 12, 10, COAT)
    p.ellipse(36, 34, 11, 8, COAT_DEEP)
    p.ellipse(29, 33, 3.2, 7.0, COAT_LIGHT)
    # Arm forward, hand resting on the desk.
    p.line(30, 30, 26, 33, COAT_DEEP, thick=2)
    p.ellipse(25, 33, 1.8, 1.4, SKIN)
    vincent_head(p, 36, 19, hat=True, phones=True)
    # Coat collar around the beard, a lapel line and a button.
    p.ellipse(36, 28, 8.5, 3.0, COAT_DEEP)
    p.set(29, 27, COAT_LIGHT)
    p.line(31, 29, 34, 34, COAT_LIGHT)
    p.line(41, 29, 38, 34, COAT_DEEP)
    p.set(36, 33, HAT_SHADE)

    # Mug of something warm, in front of the record player, with two curls of steam.
    p.rect(25, 27, 28, 30, MUG)
    p.rect(29, 28, 30, 29, MUG)
    p.rect(25, 30, 28, 30, "#D9CCB8")
    p.set(26, 28, "#FFFFFF")
    for (sx, sy) in ((26, 26), (27, 25), (27, 24), (26, 23), (26, 22), (27, 21)):
        p.set(sx, sy, STEAM)
    for (sx, sy) in ((29, 26), (30, 25), (30, 24), (29, 23), (29, 22)):
        p.set(sx, sy, "#B9B0A2")

    # Stool legs under him, so he is sitting rather than floating.
    p.rect(32, 37, 33, 40, WOOD_DEEP)
    p.rect(40, 37, 41, 40, WOOD_DEEP)

    p.write(OUT / "vincent-desk.png", 8)


def build_back():
    w, h = 26, 38
    p = Pixels(w, h)
    cx = 13

    # Legs and boots.
    p.rect(cx - 5, 27, cx - 1, 33, COAT_DEEP)
    p.rect(cx + 1, 27, cx + 5, 33, COAT_DEEP)
    p.rect(cx - 5, 33, cx - 1, 35, HAT_BAND)
    p.rect(cx + 1, 33, cx + 5, 35, HAT_BAND)

    # Coat from behind: a wide back, narrow shoulders, a hem that flares.
    p.ellipse(cx, 25, 9.5, 7.5, COAT)
    p.rect(cx - 9, 20, cx + 9, 28, COAT)
    p.ellipse(cx, 21, 7.6, 4.6, COAT)
    p.ellipse(cx - 4, 24, 4.2, 7.0, COAT_LIGHT)
    p.line(cx, 20, cx, 31, COAT_DEEP)
    p.rect(cx - 9, 28, cx + 9, 29, COAT_DEEP)
    # Arms, hands in pockets.
    p.rect(cx - 10, 21, cx - 8, 29, COAT_DEEP)
    p.rect(cx + 8, 21, cx + 10, 29, COAT_DEEP)
    # Scarf: the one warm line on him.
    p.rect(cx - 6, 18, cx + 6, 20, HAT_SHADE)
    p.rect(cx - 6, 18, cx + 6, 18, HAT_LIGHT)

    # Head from behind: neck, hair, bandage edge, hat.
    p.rect(cx - 3, 15, cx + 3, 18, SKIN_SHADOW)
    p.ellipse(cx, 13, 5.4, 5.0, BEARD_DEEP)
    p.rect(cx - 5, 14, cx - 4, 17, BEARD)
    p.rect(cx + 4, 14, cx + 5, 17, BEARD)
    # The bandage peeks past his left ear, one cell wide so it reads as cloth and not a tab.
    p.rect(cx - 6, 13, cx - 6, 15, BANDAGE)
    p.rect(cx - 6, 16, cx - 6, 16, BANDAGE_SHADE)
    # Hearing ear, on the other side: two cells, tucked against the head.
    p.rect(cx + 5, 12, cx + 6, 14, SKIN)
    p.set(cx + 6, 13, EAR_INNER)

    p.ellipse(cx, 7, 10.4, 2.4, HAT_SHADE)
    p.ellipse(cx, 6.6, 9.8, 1.8, HAT)
    p.ellipse(cx, 3.4, 6.4, 3.8, HAT)
    p.ellipse(cx - 2.2, 2.6, 3.0, 2.0, HAT_LIGHT)
    p.rect(cx - 7, 5, cx + 7, 6, HAT_BAND)

    # Sunrise rim: the page behind him is on his right, so only that edge catches the light.
    for y in range(2, 34):
        for x in range(w - 1, 0, -1):
            if p.get(x, y) is not None:
                if x > cx and p.get(x + 1, y) is None:
                    p.set(x, y, "#F3BE86")
                break

    p.write(OUT / "vincent-back.png", 8)


def main():
    build_desk()
    build_back()


if __name__ == "__main__":
    main()
