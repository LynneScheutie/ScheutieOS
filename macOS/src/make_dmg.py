#!/usr/bin/env python3
# make_dmg.py — lays out the distribution DMG so it opens on the classic
# "drag the app into Applications" window.
#
#   make_dmg.py <mounted-volume> <app-name> <version> [alias-file]
#
# Why not AppleScript: Finder automation is denied in this environment
# (osascript → error -10004), so the layout is written straight into .DS_Store
# with the ds_store package instead. The background picture is drawn with Pillow
# so the DMG explains itself instead of relying on the user guessing.
#
# The optional alias-file holds a pre-minted background alias. It exists because
# the alias has to be minted at the path the volume will have on the *recipient's*
# Mac (/Volumes/<volname>), but writing to /Volumes is not permitted here — only
# reading. So make_dist.sh mounts the volume read-only at its canonical path,
# mints the alias there, and passes the bytes in here. An alias minted on a
# scratch mount point instead records /private/var/folders/... as the volume
# path and Finder then silently drops the background picture.

import os
import plistlib
import struct
import sys

from PIL import Image, ImageDraw, ImageFont

import mac_alias
from ds_store import DSStore

W, H = 700, 420
# The window frame is W x H (written into bwsp), but the background picture only
# has to cover the content area — the title bar takes ~28 points off the top.
# Drawing a 420-tall picture makes Finder scale it down, which is exactly how the
# instruction text ended up underneath the icon labels.
TITLEBAR = 28
CONTENT_H = H - TITLEBAR
ICON = 96.0
APP_X, APPS_X, ICON_Y = 170, 470, 150
ARROW_Y = ICON_Y + int(ICON) // 2
BG_NAME = ".background/background.png"
FONT = "/System/Library/Fonts/Supplemental/Arial Unicode.ttf"

INK = (28, 28, 30)
BODY = (60, 60, 67)
MUTED = (120, 120, 127)
ACCENT = (24, 95, 165)


def draw_background(path, app_name, version):
    """The picture Finder shows behind the icons: title, arrow, instructions."""
    img = Image.new("RGB", (W, CONTENT_H), (244, 244, 246))
    d = ImageDraw.Draw(img)
    title = ImageFont.truetype(FONT, 30)
    body = ImageFont.truetype(FONT, 19)
    small = ImageFont.truetype(FONT, 14)

    def center(text, font, y, fill):
        w = d.textlength(text, font=font)
        d.text(((W - w) / 2, y), text, font=font, fill=fill)

    center(f"{app_name} {version}", title, 32, INK)

    # Arrow between the two icons. Drawn at the icons' vertical centre, so it
    # lines up whether .DS_Store's Iloc is read as top-left or centre.
    ax0, ax1 = 296, 404
    d.line((ax0, ARROW_Y, ax1 - 16, ARROW_Y), fill=ACCENT, width=6)
    d.polygon([(ax1, ARROW_Y), (ax1 - 22, ARROW_Y - 14), (ax1 - 22, ARROW_Y + 14)],
              fill=ACCENT)

    # Finder draws the icon labels at about ICON_Y + ICON + 4, so the
    # instructions start well below that.
    center("把图标拖进右边的「Applications」文件夹", body, ICON_Y + int(ICON) + 42, BODY)
    center("完成后可推出本磁盘，之后从「应用程序」里启动", small,
           ICON_Y + int(ICON) + 74, MUTED)

    img.save(path)


def write_dsstore(volume, app_name, alias_bytes=None):
    """Window bounds, icon view with the background picture, icon positions."""
    if alias_bytes is None:
        alias_bytes = mac_alias.Alias.for_file(os.path.join(volume, BG_NAME)).to_bytes()
    # Four big-endian floats (r, g, b, a); unused while backgroundType is 2 but
    # Finder expects the key to be there.
    background_color = struct.pack(">ffff", 1.0, 1.0, 1.0, 1.0)

    bwsp = {
        "WindowBounds": "{{60, 60}, {%d, %d}}" % (W, H),
        "ShowStatusBar": False,
        "ShowToolbar": False,
        "ShowSidebar": False,
        "ContainerShowSidebar": False,
        "ShowTabView": False,
        "PreviewPaneVisibility": False,
        "SidebarWidth": 0,
    }
    icvp = {
        "viewOptionsVersion": 1,
        "arrangeBy": "none",
        "iconSize": ICON,
        "textSize": 14.0,
        "gridSpacing": 100.0,
        "labelOnBottom": True,
        "backgroundType": 2,
        "backgroundImageAlias": alias_bytes,
        "backgroundColor": background_color,
    }

    with DSStore.open(os.path.join(volume, ".DS_Store"), "w+") as d:
        d["."]["bwsp"] = bwsp
        d["."]["icvp"] = icvp
        d[app_name + ".app"]["Iloc"] = (APP_X, ICON_Y)
        d["Applications"]["Iloc"] = (APPS_X, ICON_Y)


def main():
    if len(sys.argv) not in (4, 5):
        sys.exit("usage: make_dmg.py <mounted-volume> <app-name> <version> [alias-file]")
    volume, app_name, version = sys.argv[1:4]

    alias_bytes = None
    if len(sys.argv) == 5:
        with open(sys.argv[4], "rb") as fh:
            alias_bytes = fh.read()
        if not alias_bytes:
            sys.exit("make_dmg.py: alias file is empty")

    bg = os.path.join(volume, BG_NAME)
    os.makedirs(os.path.dirname(bg), exist_ok=True)
    draw_background(bg, app_name, version)
    write_dsstore(volume, app_name, alias_bytes)

    # Both children must exist for the Iloc entries to mean anything.
    missing = [n for n in (app_name + ".app", "Applications")
               if not os.path.exists(os.path.join(volume, n))]
    if missing:
        sys.exit("make_dmg.py: missing on volume: " + ", ".join(missing))

    print("make_dmg.py: layout written to %s/.DS_Store" % volume)


if __name__ == "__main__":
    main()
