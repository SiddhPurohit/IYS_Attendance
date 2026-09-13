#!/usr/bin/env python3
"""Generates the IYS Attendance launcher icon.

A white lotus — Krsna's flower, and the app's existing motif — on a warm
saffron gradient, with peacock-teal shading on the outer petals and a gold
heart. Pure standard library: the PNG is encoded by hand so this needs no
Pillow/ImageMagick/cairo.

    python3 tool/generate_icon.py

Writes assets/icon/app_icon.png (full bleed, for iOS/web/legacy Android) and
assets/icon/app_icon_foreground.png (transparent, for the Android adaptive
icon, drawn smaller to sit inside the 66% safe zone). Then run:

    dart run flutter_launcher_icons
"""

import math
import os
import struct
import zlib

SIZE = 1024
SS = 2  # supersampling factor per axis

# Palette — matches AppColors in lib/core/theme/app_theme.dart
BG_INNER = (0xFF, 0xC1, 0x4D)
BG_OUTER = (0xD9, 0x78, 0x0A)
PETAL_OUTER = (0xE4, 0xF3, 0xF0)  # white with a peacock-teal cast
PETAL_INNER = (0xFF, 0xFF, 0xFF)
PETAL_EDGE = (0x00, 0x69, 0x5C)  # teal outline
HEART = (0xF0, 0xB4, 0x29)
HEART_RING = (0xC4, 0x85, 0x10)


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def over(dst, src, alpha):
    """Composite src over dst with the given alpha (both RGB tuples)."""
    return tuple(round(src[i] * alpha + dst[i] * (1 - alpha)) for i in range(3))


def petal_coverage(dx, dy, angle, length, half_width, aa):
    """How much of this sample falls inside a petal pointing along `angle`.

    The petal is the lens where two circles overlap — both pass through the
    flower's centre and the petal tip, so the shape comes to a point at each
    end the way a real lotus petal does. Returns 0..1, plus how far along
    the petal the point sits (for shading).
    """
    # Rotate into the petal's own frame: it then runs along +x.
    ca, sa = math.cos(angle), math.sin(angle)
    x = dx * ca + dy * sa
    y = -dx * sa + dy * ca

    if x < -aa or x > length + aa:
        return 0.0, 0.0

    # Circle centres sit at (length/2, +/-k); both pass through the tips.
    k = (length * length / 4.0 - half_width * half_width) / (2.0 * half_width)
    radius = half_width + k
    d1 = math.hypot(x - length / 2.0, y + k)
    d2 = math.hypot(x - length / 2.0, y - k)

    # Distance inside the lens boundary, negative outside.
    edge = min(radius - d1, radius - d2)
    if edge <= -aa:
        return 0.0, 0.0
    coverage = 1.0 if edge >= aa else (edge + aa) / (2.0 * aa)
    return coverage, min(1.0, max(0.0, x / length))


def nearest_petal(theta, phase):
    """Angle of the petal in this 8-fold row closest to `theta`."""
    step = math.pi / 4
    i = round((theta - phase) / step)
    return phase + i * step


def sample(x, y, cx, cy, scale, with_background):
    """Colour + alpha at one sample point. Returns (rgb, alpha)."""
    dx, dy = x - cx, y - cy

    if with_background:
        # Radial saffron gradient, lit slightly from above.
        g = min(1.0, math.hypot(dx, dy + scale * 0.10) / (scale * 0.80))
        rgb = lerp(BG_INNER, BG_OUTER, g ** 1.25)
        alpha = 1.0
    else:
        rgb = (0, 0, 0)
        alpha = 0.0

    dist = math.hypot(dx, dy)
    if dist > scale * 1.02:  # well outside the bloom
        return rgb, alpha

    theta = math.atan2(dy, dx)
    aa = scale * 0.004

    # Back row, offset half a step so it shows between the front petals.
    angle = nearest_petal(theta, math.pi / 8)
    cov, along = petal_coverage(dx, dy, angle, scale, scale * 0.20, aa)
    if cov > 0:
        body = lerp(lerp(PETAL_OUTER, PETAL_EDGE, 0.22), PETAL_OUTER, along)
        rgb = over(rgb, body, cov)
        alpha = max(alpha, cov)

    # Front row.
    angle = nearest_petal(theta, 0.0)
    cov, along = petal_coverage(dx, dy, angle, scale * 0.80, scale * 0.17, aa)
    if cov > 0:
        body = lerp(lerp(PETAL_INNER, PETAL_EDGE, 0.16), PETAL_INNER, along)
        rgb = over(rgb, body, cov)
        alpha = max(alpha, cov)

    # Gold heart with a thin darker ring.
    r_heart = scale * 0.10
    if dist <= r_heart:
        rgb, alpha = HEART, 1.0
    elif dist <= r_heart + scale * 0.014:
        rgb, alpha = HEART_RING, 1.0

    return rgb, alpha


def render(path, with_background, lotus_scale):
    cx = cy = SIZE / 2.0
    scale = SIZE * lotus_scale
    step = 1.0 / SS
    weight = 1.0 / (SS * SS)
    rows = bytearray()

    for py in range(SIZE):
        row = bytearray()
        for px in range(SIZE):
            r = g = b = a = 0.0
            for sy in range(SS):
                y = py + (sy + 0.5) * step
                for sx in range(SS):
                    x = px + (sx + 0.5) * step
                    rgb, alpha = sample(x, y, cx, cy, scale, with_background)
                    r += rgb[0] * alpha * weight
                    g += rgb[1] * alpha * weight
                    b += rgb[2] * alpha * weight
                    a += alpha * weight
            if a > 0:
                row += bytes((round(r / a), round(g / a), round(b / a),
                              round(a * 255)))
            else:
                row += b"\x00\x00\x00\x00"
        rows += b"\x00" + row

    def chunk(kind, data):
        return (struct.pack(">I", len(data)) + kind + data
                + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF))

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(rows), 9))
    png += chunk(b"IEND", b"")

    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(png)
    print(f"wrote {path}")


if __name__ == "__main__":
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    render(os.path.join(here, "assets/icon/app_icon.png"),
           with_background=True, lotus_scale=0.40)
    # Android adaptive foreground: transparent, and smaller so the system
    # mask never clips a petal.
    render(os.path.join(here, "assets/icon/app_icon_foreground.png"),
           with_background=False, lotus_scale=0.29)
