#!/usr/bin/env python3
"""Generate assets/AppIcon.ico from assets/icon-source.png.

Windows .ico that bundles real multi-resolution entries:
16/24/32/48/64/128/256. Entries of 64px and above are stored as
PNG (Vista+ supports this and keeps the file small); the small ones are
stored as raw BMP the way classic tools do, so every renderer is happy.

Usage: make_ico.py [source.png] [output.ico]
"""

import os
import struct
import sys

from PIL import Image

SIZES = [16, 24, 32, 48, 64, 128, 256]
PNG_FROM = 64  # store entries this size and larger as PNG


def fit_square(im: Image.Image, size: int) -> Image.Image:
    """Contain the source into a transparent square canvas (no crop)."""
    im = im.convert("RGBA")
    if getattr(im, "n_frames", 1) > 1:
        im.seek(0)
    im.thumbnail((size, size), Image.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.alpha_composite(im, ((size - im.width) // 2, (size - im.height) // 2))
    return canvas


def bmp_entry(im: Image.Image) -> bytes:
    """Encode one icon image as a 32-bit BGRA DIB (BITMAPINFOHEADER + pixels)."""
    w, h = im.size
    header = struct.pack(
        "<IiiHHIIiiII",
        40,                 # biSize
        w,                  # biWidth
        h * 2,              # biHeight (XOR + AND masks stacked)
        1,                  # biPlanes
        32,                 # biBitCount
        0, 0, 0, 0, 0, 0,   # compression / size / res / res / colors / important
    )
    px = im.load()
    # Rows are bottom-up, BGRA.
    rows = []
    for y in range(h - 1, -1, -1):
        row = bytearray()
        for x in range(w):
            r, g, b, a = px[x, y]
            row += bytes((b, g, r, a))
        rows.append(bytes(row))
    xor = b"".join(rows)
    # AND mask: 1 bit per pixel, rows padded to 4 bytes, bottom-up. All zero
    # because we carry real alpha in the 32-bit data.
    stride = ((w + 31) // 32) * 4
    and_mask = b"\x00" * (stride * h)
    return header + xor + and_mask


def main(src: str, dst: str) -> None:
    im = Image.open(src)
    entries = []
    for s in SIZES:
        e = fit_square(im, s)
        if s >= PNG_FROM:
            data = e.save_in_memory() if False else _png_bytes(e)
        else:
            data = bmp_entry(e)
        entries.append((s, data))

    out = struct.pack("<HHH", 0, 1, len(entries))
    offset = 6 + 16 * len(entries)
    body = bytearray()
    for s, data in entries:
        w = 0 if s >= 256 else s  # 0 means 256 in the directory entry
        out += struct.pack("<BBBBHHII", w, w, 0, 0, 1, 32, len(data), offset)
        body += data
        offset += len(data)

    os.makedirs(os.path.dirname(dst) or ".", exist_ok=True)
    with open(dst, "wb") as f:
        f.write(out + bytes(body))
    total = 6 + 16 * len(entries) + sum(len(d) for _, d in entries)
    print(f"icon: {src} -> {dst}  ({total} bytes, sizes {SIZES})")


def _png_bytes(im: Image.Image) -> bytes:
    import io
    buf = io.BytesIO()
    im.save(buf, "PNG", optimize=True)
    return buf.getvalue()


if __name__ == "__main__":
    src = sys.argv[1] if len(sys.argv) > 1 else os.path.join("assets", "icon-source.png")
    dst = sys.argv[2] if len(sys.argv) > 2 else os.path.join("assets", "AppIcon.ico")
    main(src, dst)
