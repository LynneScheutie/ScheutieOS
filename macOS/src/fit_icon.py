#!/usr/bin/env python3
"""Fit an arbitrary image into a 1024x1024 transparent canvas (contain, centered).

Usage: fit_icon.py <input image> <output png>

Keeps aspect ratio, never crops. The macOS squircle shape is NOT applied —
if the source is a plain square photo it will render as a square tile.
"""

import sys
from PIL import Image

SIZE = 1024


def main(src, dst):
    im = Image.open(src)
    im = im.convert("RGBA")

    # Animated formats (gif/webp): take the first frame.
    if getattr(im, "n_frames", 1) > 1:
        im.seek(0)

    # Scale down to fit inside the canvas, preserving aspect ratio.
    im.thumbnail((SIZE, SIZE), Image.LANCZOS)

    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    x = (SIZE - im.width) // 2
    y = (SIZE - im.height) // 2
    canvas.alpha_composite(im, (x, y))
    canvas.save(dst)
    print(f"icon: {src} -> {dst}  ({im.width}x{im.height} fitted into {SIZE}x{SIZE})")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("usage: fit_icon.py <input image> <output png>")
    main(sys.argv[1], sys.argv[2])
