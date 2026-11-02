#!/usr/bin/env python3
"""Paints the landing page's night: three pixel-art planes, written to site/assets/.

    python3 scripts/night-scene.py

The output is deliberately a *painting* rather than a gradient: the sky is built from short
brush strokes that follow spiral currents, which is the one thing that makes this read as a
Van Gogh night instead of a blue background. Everything is deterministic (random.Random with a
fixed seed), so re-running the script reproduces the exact same files.

Planes, back to front:
    night-sky.png     the sky, stars and the moon's light                      2400 x 1200
    night-hills.png   far ridge, village windows, the cypress, near ridge      2400 x 800
    night-front.png   the dark foreground the page sits on                     2400 x 500

Each is drawn on a coarse cell grid and scaled up with nearest-neighbour, which is what gives
the art its pixel edges. No third-party packages: PNG is written with zlib directly.
"""

import math
import random
import struct
import zlib
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "site" / "assets"

CELL = 5

# Sky ramp, top to horizon. Kept deep enough that cream type sits on it without a scrim doing
# all the work, and warm enough at the bottom to meet the hills.
SKY = [
    (0.00, (6, 8, 26)),
    (0.28, (10, 14, 42)),
    (0.52, (17, 22, 56)),
    (0.70, (26, 30, 72)),
    (0.84, (42, 40, 88)),
    (0.93, (64, 50, 96)),
    (1.00, (84, 58, 92)),
]

# Brush tones. Each stroke picks one of these by depth, so the sky has three flat values that
# overlap rather than a continuous blur.
STROKE = [
    (30, 38, 88),
    (42, 54, 116),
    (58, 72, 146),
    (78, 96, 176),
    (110, 126, 202),
]
STROKE_WARM = (108, 92, 158)
STROKE_GOLD = (196, 158, 92)
STAR = (250, 244, 226)
STAR_DIM = (186, 190, 214)


def ramp(stops, t):
    """Linear interpolation through an ordered list of (position, rgb) stops."""
    t = min(1.0, max(0.0, t))
    for i in range(len(stops) - 1):
        p0, c0 = stops[i]
        p1, c1 = stops[i + 1]
        if p0 <= t <= p1:
            k = 0.0 if p1 == p0 else (t - p0) / (p1 - p0)
            return tuple(round(a + (b - a) * k) for a, b in zip(c0, c1))
    return stops[-1][1]


def mix(a, b, k):
    return tuple(round(x + (y - x) * k) for x, y in zip(a, b))


class Canvas:
    """RGBA cell grid. Coordinates are cells, origin top-left."""

    def __init__(self, w, h, fill=(0, 0, 0, 0)):
        self.w = w
        self.h = h
        self.px = [[fill for _ in range(w)] for _ in range(h)]

    def set(self, x, y, color):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[y][x] = color if len(color) == 4 else (*color, 255)

    def get(self, x, y):
        if 0 <= x < self.w and 0 <= y < self.h:
            return self.px[y][x]
        return (0, 0, 0, 0)

    def blend(self, x, y, color, alpha):
        x, y = int(x), int(y)
        if not (0 <= x < self.w and 0 <= y < self.h):
            return
        base = self.px[y][x]
        alpha = max(0.0, min(1.0, alpha))
        self.px[y][x] = (
            round(base[0] + (color[0] - base[0]) * alpha),
            round(base[1] + (color[1] - base[1]) * alpha),
            round(base[2] + (color[2] - base[2]) * alpha),
            max(base[3], round(255 * alpha) if len(color) > 3 else base[3]),
        )

    def blob(self, cx, cy, rx, ry, color):
        for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
            for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
                if ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1.0:
                    self.set(x, y, color)

    def write(self, path, scale):
        w, h = self.w, self.h
        rows = bytearray()
        # Scale each cell to a SCALE x SCALE block, one scanline at a time.
        for row in self.px:
            line = bytearray()
            for r, g, b, a in row:
                line += bytes((r, g, b, a)) * scale
            for _ in range(scale):
                # Every PNG scanline starts with its filter byte; 0 means "none".
                rows += b"\x00" + line

        def chunk(tag, data):
            return (
                struct.pack(">I", len(data))
                + tag
                + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
            )

        header = struct.pack(">IIBBBBB", w * scale, h * scale, 8, 6, 0, 0, 0)
        png = (
            b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", header)
            + chunk(b"IDAT", zlib.compress(bytes(rows), 9))
            + chunk(b"IEND", b"")
        )
        path.write_bytes(png)
        print(f"{path.relative_to(OUT.parent.parent)}  {w * scale}x{h * scale}  {len(png) // 1024} KB")


def dither(color, rng, amount=3):
    shift = rng.randint(-amount, amount)
    return tuple(max(0, min(255, c + shift)) for c in color)


def paint_sky(rng):
    """A stroke field, not a gradient.

    Every cell above the horizon is either base sky or part of a brush stroke whose direction
    comes from a flow field: three vortices pulling the paint around themselves over a slow
    horizontal drift. The tone of each stroke is chosen by a light field, so the vortices read as
    crests of moonlit cloud and the gaps between them stay near-black. This is the difference
    between a night sky and a blue rectangle.
    """
    w, h = 480, 240
    c = Canvas(w, h)

    for y in range(h):
        base = ramp(SKY, y / (h - 1))
        for x in range(w):
            c.set(x, y, dither(base, rng, 2))

    # x, y, radius, vertical squash, spin direction. Two big currents and one small eddy.
    vortices = [
        (92, 82, 74, 0.60, 1.0),
        (292, 64, 58, 0.34, -1.0),
        (396, 146, 46, 0.20, 1.0),
    ]

    def light(x, y):
        v = 0.02
        for cx, cy, r, squash, _ in vortices:
            d2 = (x - cx) ** 2 + ((y - cy) / squash) ** 2
            v += math.exp(-d2 / (2 * (r * 0.62) ** 2)) * 0.92
        # The horizon holds heat: a thin band of lighter air above the hills.
        v += 0.26 * math.exp(-(((h - y) / 30) ** 2))
        v += 0.05 * math.sin(x / 67.0) * math.sin(y / 41.0)
        return max(0.0, min(1.0, v))

    def flow(x, y):
        ax, ay = 1.0, 0.13 * math.sin(x / 58.0)
        for cx, cy, r, squash, spin in vortices:
            dx, dy = x - cx, (y - cy) / squash
            d = math.hypot(dx, dy) + 1.0
            weight = (r * r) / (d * d + r * 6.0) * 1.7
            ax += spin * (-dy / d) * weight
            ay += spin * (dx / d) * weight
        n = math.hypot(ax, ay) or 1.0
        return ax / n, ay / n

    tones = [
        (16, 20, 48),
        (24, 30, 66),
        (34, 43, 90),
        (50, 62, 118),
        (72, 86, 146),
        (102, 116, 174),
    ]
    warm = (96, 82, 132)

    for gy in range(6, h - 4, 3):
        for gx in range(-2, w, 3):
            x = gx + rng.uniform(-1.2, 1.2)
            y = gy + rng.uniform(-1.2, 1.2)
            value = light(x, y)
            idx = min(5, max(0, int(value * 5.4 + rng.uniform(-0.5, 0.5))))
            tone = tones[idx]
            if idx >= 3 and rng.random() < 0.16:
                tone = mix(tone, warm, rng.uniform(0.2, 0.5))
            if idx >= 4 and rng.random() < 0.03:
                tone = (170, 148, 114)

            length = rng.randint(4, 8)
            thick = 2 if idx >= 2 else rng.choice([1, 2, 2])
            dx, dy = flow(x, y)
            for i in range(length):
                sx, sy = x + dx * i, y + dy * i
                for t in range(thick):
                    c.set(int(sx - dy * t), int(sy + dx * t), tone)
                # A lighter crest on top of the stroke and a darker edge beneath: two values
                # per stroke is what gives flat pixel paint its sense of a loaded brush.
                c.set(int(sx - dy * thick), int(sy + dx * thick), mix(tone, (150, 168, 216), 0.22))
                c.set(int(sx + dy), int(sy - dx), mix(tone, (6, 8, 26), 0.5))

    # Stars. Fewer, larger, and only in the upper sky, so they read as points of light rather
    # than noise sprinkled over the whole field.
    for _ in range(80):
        x = rng.randrange(4, w - 4)
        y = rng.randrange(4, int(h * 0.72))
        halo = c.get(x, y)[:3]
        c.blend(x, y, STAR_DIM, 0.25)
        roll = rng.random()
        if roll > 0.86:
            for dx, dy in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):
                c.set(x + dx, y + dy, STAR)
            for dx, dy in ((2, 0), (-2, 0), (0, 2), (0, -2)):
                c.blend(x + dx, y + dy, STAR, 0.55)
            c.blend(x + 1, y + 1, STAR, 0.35)
            c.blend(x - 1, y - 1, STAR, 0.35)
        elif roll > 0.55:
            c.set(x, y, STAR)
            c.set(x + 1, y, mix(STAR, halo, 0.45))
        else:
            c.blend(x, y, STAR, 0.75)

    # The moon: small and high. Its light is a wide, very weak wash, drawn as a gradient of
    # alpha rather than a disc, so it lifts the sky around it without becoming a beige balloon.
    mx, my, mr = 352, 92, 8
    reach = 58
    for yy in range(my - reach, my + reach + 1):
        for xx in range(mx - reach, mx + reach + 1):
            d = math.hypot(xx - mx, yy - my)
            if d > reach:
                continue
            falloff = max(0.0, 1.0 - d / reach) ** 2.6
            c.blend(xx, yy, (206, 194, 176), 0.16 * falloff)
    c.blob(mx, my, mr, mr, (240, 226, 190))
    c.blob(mx - 2, my - 2, mr * 0.66, mr * 0.66, (250, 240, 212))
    for _ in range(7):
        c.blob(mx + rng.uniform(-4.5, 4.5), my + rng.uniform(-4.5, 4.5),
               rng.uniform(0.9, 1.9), rng.uniform(0.9, 1.9), (222, 204, 164))

    c.write(OUT / "night-sky.png", CELL)


def paint_hills(rng):
    w, h = 480, 160
    c = Canvas(w, h)

    def ridge(base, amp, phase, color, rim):
        tops = []
        for x in range(w):
            y = base + math.sin(x / 74 + phase) * amp + math.sin(x / 23 + phase * 2) * amp * 0.3
            y = int(y)
            tops.append(y)
            for yy in range(y, h):
                c.set(x, yy, color)
            c.set(x, y, rim)
            if amp > 4:
                c.set(x, y + 1, mix(rim, color, 0.55))
        return tops

    far = ridge(74, 9, 0.6, (23, 26, 60), (52, 58, 106))

    # Village: the warm windows are the only light in the hills, and they are what makes the
    # distance feel inhabited rather than empty.
    for _ in range(44):
        x = rng.randrange(90, 330)
        y = far[x] + rng.randint(6, 22)
        bw = rng.randint(2, 5)
        bh = rng.randint(2, 4)
        for yy in range(y, y + bh):
            for xx in range(x, x + bw):
                c.set(xx, yy, (16, 18, 44))
        c.set(x, y, (38, 42, 82))
        if rng.random() < 0.8:
            c.set(x + bw // 2, y + max(1, bh - 1), (242, 189, 106))
            c.set(x + bw // 2, y + 1, (198, 140, 74))
    for _ in range(10):
        x = rng.randrange(100, 320)
        y = far[x] + 3
        c.set(x, y, (250, 206, 130))

    ridge(108, 6, 2.1, (13, 15, 38), (34, 38, 78))

    # The cypress: a dark flame rooted behind the near ridge, the one vertical on a horizontal
    # page. Wide at the base, tapering to a single point, with broken edges so it is painted
    # rather than vector.
    cx = 412
    base_y, crown_y = 132, 30
    for y in range(crown_y, base_y + 1):
        t = (y - crown_y) / (base_y - crown_y)
        half = 0.8 + 13.5 * t ** 1.5
        left, right = int(cx - half), int(cx + half)
        for x in range(left, right + 1):
            ragged = rng.random() < 0.10
            if ragged and (x == left or x == right):
                continue
            c.set(x, y, (7, 8, 22))
        c.set(left, y, (28, 33, 68))
        if rng.random() < 0.5:
            c.set(right, y, (18, 22, 50))
    for y in range(crown_y + 8, base_y):
        c.set(cx + 1, y, (5, 6, 18))
        if rng.random() < 0.22:
            c.set(cx + rng.randint(-6, 6), y, (12, 14, 34))

    # Near ridge, heavier and darker, so the character can stand behind it.
    ridge(126, 4, 4.4, (8, 9, 24), (26, 30, 62))

    c.write(OUT / "night-hills.png", CELL)


def paint_front(rng):
    w, h = 480, 100
    c = Canvas(w, h)

    tops = []
    for x in range(w):
        y = 34 + math.sin(x / 61 + 1.2) * 8 + math.sin(x / 19 + 0.4) * 2.2
        tops.append(int(y))
        for yy in range(int(y), h):
            c.set(x, yy, (10, 12, 30))
        c.set(x, int(y), (34, 39, 78))
        c.set(x, int(y) + 1, (20, 24, 52))

    # Wheat stalks: two cells wide, slightly bent, silhouette only. They give the foreground a
    # texture without becoming a field of clip art.
    for _ in range(90):
        x = rng.randrange(w)
        y = tops[x]
        height = rng.randint(4, 14)
        lean = rng.choice([-1, 0, 1, 1])
        for i in range(height):
            c.set(x + (lean if i > height * 0.6 else 0), y - i, (4, 5, 14))
        head = (y - height)
        c.set(x + lean, head, (12, 14, 32))
        c.set(x + lean + 1, head - 1, (12, 14, 32))

    c.write(OUT / "night-front.png", CELL)


def main():
    rng = random.Random(7)
    paint_sky(rng)
    paint_hills(rng)
    paint_front(rng)


if __name__ == "__main__":
    main()
