#!/usr/bin/env python3
"""Generate the DeepSeek launcher app icon (gradient squircle + chat bubble)."""

import os
import sys
from PIL import Image, ImageDraw, ImageFilter

S = 1024
SS = 4                      # supersample factor
W = S * SS

BLUE_TOP = (110, 136, 255)
BLUE_BOT = (43, 62, 214)
ACCENT = (77, 107, 254)


def lerp(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def gradient(size, top, bottom):
    img = Image.new("RGB", (1, size), top)
    px = img.load()
    for y in range(size):
        px[0, y] = lerp(top, bottom, y / max(size - 1, 1))
    return img.resize((size, size), Image.BILINEAR)


def squircle_mask(size, radius_ratio=0.2355):
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)
    r = int(size * radius_ratio)
    d.rounded_rectangle([0, 0, size - 1, size - 1], radius=r, fill=255)
    return m


def main(out_png):
    # --- background ---
    bg = gradient(W, BLUE_TOP, BLUE_BOT).convert("RGBA")
    bg.putalpha(squircle_mask(W))

    # soft diagonal sheen
    sheen = Image.new("L", (W, W), 0)
    sd = ImageDraw.Draw(sheen)
    sd.ellipse([-W * 0.45, -W * 0.75, W * 0.95, W * 0.38], fill=62)
    sheen = sheen.filter(ImageFilter.GaussianBlur(W * 0.06))
    bg = Image.composite(Image.new("RGBA", (W, W), (255, 255, 255, 255)), bg, sheen.point(lambda v: v // 2))

    # --- chat bubble ---
    bubble = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    bd = ImageDraw.Draw(bubble)

    bw, bh = int(W * 0.60), int(W * 0.435)
    bx = (W - bw) // 2
    by = int(W * 0.235)
    br = int(bh * 0.30)

    # drop shadow under bubble
    shadow = Image.new("L", (W, W), 0)
    sh = ImageDraw.Draw(shadow)
    sh.rounded_rectangle([bx, by + W * 0.012, bx + bw, by + bh + W * 0.012],
                         radius=br, fill=90)
    sh.polygon([(bx + bw * 0.20, by + bh - br * 0.35),
                (bx + bw * 0.10, by + bh + W * 0.075),
                (bx + bw * 0.38, by + bh - br * 0.30)], fill=90)
    shadow = shadow.filter(ImageFilter.GaussianBlur(W * 0.018))
    bubble = Image.composite(Image.new("RGBA", (W, W), (26, 32, 84, 150)), bubble, shadow)

    # white bubble body
    solid = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    sd2 = ImageDraw.Draw(solid)
    sd2.rounded_rectangle([bx, by, bx + bw, by + bh], radius=br, fill=(255, 255, 255, 255))
    sd2.polygon([(bx + bw * 0.20, by + bh - br * 0.45),
                 (bx + bw * 0.11, by + bh + W * 0.062),
                 (bx + bw * 0.40, by + bh - br * 0.40)], fill=(255, 255, 255, 255))
    bubble = Image.alpha_composite(bubble, solid)

    # three dots inside the bubble
    dots = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    dd = ImageDraw.Draw(dots)
    dr = bw * 0.062
    cy = by + bh * 0.47
    gap = bw * 0.235
    for i, k in enumerate((-1, 0, 1)):
        cx = bx + bw / 2 + k * gap
        alpha = 255 if i in (0, 2) else 255
        dd.ellipse([cx - dr, cy - dr, cx + dr, cy + dr],
                   fill=lerp(ACCENT, BLUE_BOT, 0.25 * (i + 1)) + (alpha,))
    bubble = Image.alpha_composite(bubble, dots)

    out = Image.alpha_composite(bg, bubble)
    out = out.resize((S, S), Image.LANCZOS)

    os.makedirs(os.path.dirname(out_png), exist_ok=True)
    out.save(out_png)
    print("wrote", out_png, out.size)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "icon_1024.png")
