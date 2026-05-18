#!/usr/bin/env python3
"""Generate root_chat Android launcher icons."""

import os
import sys

try:
    from PIL import Image, ImageDraw
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, '-m', 'pip', 'install', 'Pillow', '--quiet'])
    from PIL import Image, ImageDraw

BASE = 120  # SVG viewBox size

# Colours from the SVG
BG      = (0x0D, 0x0D, 0x0D, 255)
AMBER   = (0xFF, 0xAA, 0x00, 255)
DOT_CLR = (0x2A, 0x2A, 0x2A, 255)

def _blend(color, bg_rgb, opacity):
    return tuple(round(c * opacity + b * (1 - opacity)) for c, b in zip(color[:3], bg_rgb))

BG_RGB = BG[:3]
GREEN  = _blend((0x4A, 0x7C, 0x59), BG_RGB, 0.8)
GREY   = _blend((0x55, 0x55, 0x55), BG_RGB, 0.6)
BLUE   = _blend((0x5A, 0x8F, 0xAA), BG_RGB, 0.5)


def draw_icon(size: int, circular: bool = False) -> Image.Image:
    s = size / BASE
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # ── background ───────────────────────────────────────────────────────────
    radius = round(26 * s)
    if circular:
        # Fill full square then mask to circle
        draw.rounded_rectangle([0, 0, size - 1, size - 1], radius=size // 2, fill=BG)
    else:
        draw.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=BG)

    # ── top-bar dots ─────────────────────────────────────────────────────────
    dot_r = 4 * s
    for cx in (22, 36, 50):
        x, y = cx * s, 30 * s
        draw.ellipse([x - dot_r, y - dot_r, x + dot_r, y + dot_r], fill=DOT_CLR)

    # ── chevron  >  (two line segments) ──────────────────────────────────────
    stroke = max(2, round(4 * s))
    tip_x = 44 * s
    top    = (22 * s, 42 * s)
    point  = (tip_x,  55 * s)
    bottom = (22 * s, 68 * s)
    draw.line([top, point],    fill=AMBER, width=stroke)
    draw.line([point, bottom], fill=AMBER, width=stroke)

    # ── cursor (underscore rect) ──────────────────────────────────────────────
    cx, cy, cw, ch = 60 * s, 72 * s, 24 * s, max(2, round(4 * s))
    draw.rounded_rectangle([cx, cy, cx + cw, cy + ch], radius=round(s), fill=AMBER)

    # ── status-bar lines ──────────────────────────────────────────────────────
    bars = [
        (22, 87, 30, 2, GREEN),
        (56, 87, 18, 2, GREY),
        (78, 87, 20, 2, BLUE),
    ]
    for bx, by, bw, bh, color in bars:
        bh_scaled = max(1, round(bh * s))
        draw.rounded_rectangle(
            [bx * s, by * s, (bx + bw) * s, by * s + bh_scaled],
            radius=round(s),
            fill=(*color, 255),
        )

    return img


SIZES = [
    ('mipmap-mdpi',    48,  False),
    ('mipmap-hdpi',    72,  False),
    ('mipmap-xhdpi',   96,  False),
    ('mipmap-xxhdpi',  144, False),
    ('mipmap-xxxhdpi', 192, False),
]

here    = os.path.dirname(os.path.abspath(__file__))
res_dir = os.path.join(here, 'mobile', 'android', 'app', 'src', 'main', 'res')

for folder, size, circ in SIZES:
    out = os.path.join(res_dir, folder)
    os.makedirs(out, exist_ok=True)
    draw_icon(size, circular=False).save(os.path.join(out, 'ic_launcher.png'))
    draw_icon(size, circular=True ).save(os.path.join(out, 'ic_launcher_round.png'))
    print(f'  ok  {folder}: {size}x{size}')

print('\nAll launcher icons generated.')
