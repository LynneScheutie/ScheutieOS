#!/bin/zsh
# Builds the shareable distribution of ScheutieOS:
#   dist/ScheutieOS-<ver>.pkg   — double-click installer
#   dist/ScheutieOS-<ver>.dmg   — opens on a "drag into Applications" window
#   dist/ScheutieOS-<ver>.zip   — unzip, drag into 应用程序
#   dist/安装说明.txt            — what to tell the friend
#
# Run ./build.sh first. Everything lands in dist/.
set -e

APP_NAME="ScheutieOS"
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
BUILD="$ROOT/build"
DIST="$ROOT/dist"
STAGE="$(mktemp -d)"
# Only ever the temp dir. Keeping the staged payload out of the project means
# the teardown never has to recursively delete a workspace path.
trap 'rm -rf "$STAGE" >/dev/null 2>&1 || true' EXIT

# DMG 的窗口布局（背景图、图标坐标）依赖 mac_alias、ds_store 与 Pillow。
# 依次探测：PY 环境变量 → PATH 里的 python3 → 系统 python3。
PY=""
for p in "${PY_ENV:-}" python3 /usr/bin/python3; do
    [ -n "$p" ] || continue
    if "$p" -c "import mac_alias, ds_store, PIL" >/dev/null 2>&1; then PY="$p"; break; fi
done
[ -n "$PY" ] || {
    echo "✗ 没找到装了 mac_alias + ds_store + Pillow 的 Python"
    echo "  先安装："
    echo "    pip3 install mac_alias ds_store pillow"
    exit 1
}
echo "==> using python: $PY"

APP="$BUILD/$APP_NAME.app"
[ -d "$APP" ] || { echo "✗ $APP not found — run ./build.sh first"; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILDTAG="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
# Straight from the bundle, so the installer's minimum and the app's can never
# drift apart.
MIN_OS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist")"
PKG_ID="local.scheutieos.app"

echo "==> ScheutieOS $VERSION (build $BUILDTAG)"
# Explicit file removals rather than `rm -rf "$DIST"`: the project tree should
# never be the target of a recursive delete.
rm -f "$DIST/$APP_NAME-$VERSION.pkg" \
      "$DIST/$APP_NAME-$VERSION.dmg" \
      "$DIST/$APP_NAME-$VERSION.zip" \
      "$DIST/安装说明.txt"
mkdir -p "$DIST"

# 1) A clean copy, re-signed so the payload is never a stale half-signed bundle.
#    This one copy feeds the zip, the pkg root and the DMG.
PAYLOAD="$STAGE/payload"
mkdir -p "$PAYLOAD"
ditto "$APP" "$PAYLOAD/$APP_NAME.app"
codesign --force -s - "$PAYLOAD/$APP_NAME.app" 2>/dev/null
codesign --verify --strict "$PAYLOAD/$APP_NAME.app"
cmp "$APP/Contents/MacOS/$APP_NAME" "$PAYLOAD/$APP_NAME.app/Contents/MacOS/$APP_NAME" \
  || { echo "✗ payload differs from the build"; exit 1; }

# 2) The zip. --keepParent so it unzips to ScheutieOS.app, ready to drag.
echo "==> zipping"
( cd "$PAYLOAD" && ditto -c -k --sequesterRsrc --keepParent "$APP_NAME.app" "$DIST/$APP_NAME-$VERSION.zip" )

# 3) Installer scripts. They only ever touch this one bundle path.
SCRIPTS="$STAGE/scripts"
mkdir -p "$SCRIPTS"
cat > "$SCRIPTS/preinstall" <<'EOF'
#!/bin/bash
# Quit a running copy first — installing over a live app can half-replace it.
osascript -e 'quit app "ScheutieOS"' >/dev/null 2>&1 || true
sleep 1
# Drop the previous bundle so no stale resource can survive an upgrade.
APP="/Applications/ScheutieOS.app"
if [ -d "$APP" ]; then rm -rf "$APP" 2>/dev/null || true; fi
exit 0
EOF
cat > "$SCRIPTS/postinstall" <<'EOF'
#!/bin/bash
APP="/Applications/ScheutieOS.app"
[ -d "$APP" ] || exit 0
# Installer payloads carry no quarantine, but strip it anyway in case the app
# was dragged in by hand over an existing install.
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
# Ask LaunchServices to notice the new bundle right away.
LSREG="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREG" -f "$APP" >/dev/null 2>&1 || true
exit 0
EOF
chmod +x "$SCRIPTS/preinstall" "$SCRIPTS/postinstall"

echo "==> building pkg"
COMPONENT="$STAGE/$APP_NAME-$VERSION-component.pkg"
# pkgbuild emits four harmless "write: Permission denied" lines on this machine
# (it probes a location it cannot write to) and still produces a valid package,
# so keep its noise in a log and only surface it on failure.
if ! pkgbuild --root "$PAYLOAD" \
         --identifier "$PKG_ID" \
         --version "$VERSION" \
         --install-location /Applications \
         --scripts "$SCRIPTS" \
         --ownership recommended \
         "$COMPONENT" >"$STAGE/pkgbuild.log" 2>&1; then
    cat "$STAGE/pkgbuild.log"
    echo "✗ pkgbuild failed"
    exit 1
fi

# The system requirement is declared, NOT scripted.
#
# Do not put it back in JavaScript. `productbuild --resources` only copies
# .lproj directories — a plain file like a check.js is silently dropped — so
# `<installation-check script="check.js"/>` ships a reference to a file that is
# not in the archive and Installer dies on open with
#   "评估软件包的JavaScript时发生错误" /
#   "Exception thrown while running installation check. ReferenceError:
#    Can't find variable: check"
# (both messages are in /var/log/install.log). `<allowed-os-versions>` gives the
# same protection through Installer's own native, localized message and needs no
# script file at all.
cat > "$STAGE/dist.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>ScheutieOS $VERSION</title>
    <organization>local.scheutieos</organization>
    <options hostArchitectures="arm64"/>
    <options customize="never" require-scripts="false"/>
    <volume-check>
        <allowed-os-versions>
            <os-version min="$MIN_OS"/>
        </allowed-os-versions>
    </volume-check>
    <choices-outline>
        <line choice="default"/>
    </choices-outline>
    <choice id="default" title="ScheutieOS" description="安装到「应用程序」文件夹">
        <pkg-ref id="$PKG_ID"/>
    </choice>
    <pkg-ref id="$PKG_ID" version="$VERSION" onConclusion="none">$APP_NAME-$VERSION-component.pkg</pkg-ref>
</installer-gui-script>
EOF
# productbuild has no ad-hoc signing identity ("-"), so the pkg ships unsigned.
# That is the expected state for an app without a paid Developer ID: Installer
# shows one "unidentified developer" prompt, which 安装说明.txt covers.
productbuild --distribution "$STAGE/dist.xml" \
             --package-path "$STAGE" \
             "$DIST/$APP_NAME-$VERSION.pkg" >"$STAGE/productbuild.log" 2>&1
grep -q "Supported OS versions: \[Min: $MIN_OS" "$STAGE/productbuild.log" \
  || { cat "$STAGE/productbuild.log"; echo "✗ the pkg does not declare macOS $MIN_OS"; exit 1; }
pkgutil --check-signature "$DIST/$APP_NAME-$VERSION.pkg" | head -3

# 4) Prove the payload is byte-identical to the built app.
#    `--expand-full` on the *distribution* pkg leaves the nested component alone,
#    so the payload check runs against the component pkg, and the distribution is
#    checked to actually carry that component.
echo "==> verifying pkg payload"
pkgutil --expand-full "$COMPONENT" "$STAGE/xcomp"
FOUND="$STAGE/xcomp/Payload/$APP_NAME.app/Contents/MacOS/$APP_NAME"
[ -f "$FOUND" ] || { echo "✗ no binary in pkg payload"; exit 1; }
cmp "$APP/Contents/MacOS/$APP_NAME" "$FOUND" || { echo "✗ pkg payload differs"; exit 1; }

pkgutil --expand "$DIST/$APP_NAME-$VERSION.pkg" "$STAGE/xdist"
ls "$STAGE/xdist" | grep -q '\.pkg$' || { echo "✗ distribution pkg lost its component"; exit 1; }
grep -q "$PKG_ID" "$STAGE/xdist/Distribution" || { echo "✗ Distribution does not reference the component"; exit 1; }

# Every script the Distribution names has to be inside the archive. productbuild
# drops plain resource files without a word, so a dangling reference here is
# exactly how this pkg became un-openable once already.
for s in $(grep -o 'script="[^"]*"' "$STAGE/xdist/Distribution" | cut -d'"' -f2); do
    [ -f "$STAGE/xdist/Resources/$s" ] || {
        echo "✗ Distribution references $s but Resources/$s is not in the pkg"
        exit 1
    }
done

# And prove Installer itself can evaluate the thing — the same code path that
# runs when the recipient double-clicks, and the only way to catch a broken
# distribution locally without installing anything.
echo "==> verifying Installer can open the pkg"
if ! installer -pkg "$DIST/$APP_NAME-$VERSION.pkg" -showChoicesXML -target / \
        >"$STAGE/choices.plist" 2>"$STAGE/choices.err"; then
    cat "$STAGE/choices.err"
    echo "✗ Installer cannot evaluate this pkg"
    exit 1
fi
grep -q '<plist' "$STAGE/choices.plist" || { echo "✗ Installer returned no choices"; exit 1; }
rm -rf "$STAGE/xcomp" "$STAGE/xdist"

# 5) The DMG — the one that opens with a "drag into Applications" window.
#
# Three things this block has to get right, all learned the hard way:
#
#   · Build the image blank, as HFS+. `hdiutil create -srcfolder … -format UDRW`
#     now produces an APFS image that mounts *empty* and then refuses the
#     .DS_Store write with Errno 30 — which is how an earlier run "succeeded"
#     while shipping a 1.6 MB DMG that contained nothing at all.
#
#   · Write the layout on a scratch mount point. Writing under /Volumes is not
#     permitted here, so the volume is mounted on a temp directory where it is.
#
#   · But *mint the background alias* at the canonical /Volumes path. The alias
#     records where the volume was mounted when it was made: minted on the
#     scratch mount point it says /private/var/folders/…, and Finder on the
#     recipient's Mac cannot resolve that, so the window opens with the icons
#     positioned but no background picture at all. Reading /Volumes is allowed
#     even though writing is not, so the alias is minted there and then written
#     back through the scratch mount.
echo "==> building dmg"
VOL="$APP_NAME $VERSION"
RAW="$STAGE/dmg-rw.dmg"
MP="$STAGE/mnt"            # scratch mount point — writable
CANON="/Volumes/$VOL"      # where the volume lands on the recipient's Mac
BG=".background/background.png"

# A volume already parked on that name would push ours to "/Volumes/<name> 1"
# and we would mint the alias for the wrong path.
if [ -d "$CANON" ]; then hdiutil detach "$CANON" -force >/dev/null 2>&1 || true; fi

# No -format: on macOS 27 `-format` demands -srcfolder, and -srcfolder is exactly
# what must not be used. The default format is already read/write.
hdiutil create -size 32m -fs HFS+ -volname "$VOL" -ov "$RAW" >/dev/null

# --- pass 1: content, on the scratch mount point ---------------------------
mkdir -p "$MP"
hdiutil attach "$RAW" -readwrite -noverify -noautoopen -mountpoint "$MP" >/dev/null
ditto "$PAYLOAD/$APP_NAME.app" "$MP/$APP_NAME.app"
ln -s /Applications "$MP/Applications"
"$PY" src/make_dmg.py "$MP" "$APP_NAME" "$VERSION"
hdiutil detach "$MP" >/dev/null 2>&1 || hdiutil detach "$MP" -force >/dev/null 2>&1 || true

# --- pass 2: mint the alias at the canonical path (read-only) --------------
hdiutil attach "$RAW" -readonly -nobrowse >/dev/null
if [ ! -e "$CANON/$BG" ]; then
    hdiutil detach "$CANON" -force >/dev/null 2>&1 || true
    echo "✗ $BG is missing from the volume"
    exit 1
fi
"$PY" - "$CANON/$BG" "$STAGE/bg.alias" <<'PYEOF'
import mac_alias
import sys

with open(sys.argv[2], "wb") as fh:
    fh.write(mac_alias.Alias.for_file(sys.argv[1]).to_bytes())
PYEOF
hdiutil detach "$CANON" >/dev/null 2>&1 || hdiutil detach "$CANON" -force >/dev/null 2>&1 || true

# --- pass 3: final layout, alias included ----------------------------------
hdiutil attach "$RAW" -readwrite -noverify -noautoopen -mountpoint "$MP" >/dev/null
if ! "$PY" src/make_dmg.py "$MP" "$APP_NAME" "$VERSION" "$STAGE/bg.alias"; then
    hdiutil detach "$MP" -force >/dev/null 2>&1 || true
    echo "✗ dmg layout failed"
    exit 1
fi

sync
# Spotlight and Finder can hold the volume briefly after the layout lands.
for _ in 1 2 3 4 5; do
    hdiutil detach "$MP" >/dev/null 2>&1 && break
    sleep 1
done
if hdiutil info | grep -qF "$MP"; then
    hdiutil detach "$MP" -force >/dev/null 2>&1 || true
    sleep 1
fi

hdiutil convert "$RAW" -format UDZO -o "$DIST/$APP_NAME-$VERSION.dmg" -ov >/dev/null

# Re-mount the compressed image to prove what the recipient will actually see.
MNT="$(hdiutil attach "$DIST/$APP_NAME-$VERSION.dmg" -readonly -nobrowse \
        | grep -o '/Volumes/.*' | head -1 | sed 's/[[:space:]]*$//')"
[ -n "$MNT" ] || { echo "✗ could not mount the finished dmg"; exit 1; }

if ! cmp -s "$APP/Contents/MacOS/$APP_NAME" "$MNT/$APP_NAME.app/Contents/MacOS/$APP_NAME"; then
    hdiutil detach "$MNT" -force >/dev/null 2>&1 || true
    echo "✗ dmg payload differs"
    exit 1
fi
for f in "Applications" ".DS_Store" "$BG"; do
    [ -e "$MNT/$f" ] || {
        hdiutil detach "$MNT" -force >/dev/null 2>&1 || true
        echo "✗ dmg missing $f"
        exit 1
    }
done

# The layout is only worth anything if Finder can act on it: the window must be
# sized, the icons positioned, and the background alias must point at the
# volume's real location, not at a scratch directory.
if ! "$PY" - "$MNT" "$APP_NAME" "$VOL" "$STAGE/bg.alias" <<'PYEOF'
import os
import sys
from ds_store import DSStore

vol, app_name, volname, alias_file = sys.argv[1:5]
with DSStore.open(os.path.join(vol, ".DS_Store"), "r") as d:
    win = d["."]["bwsp"]["WindowBounds"]
    ic = d["."]["icvp"]
    ax, ay = d[app_name + ".app"]["Iloc"]
    bx, by = d["Applications"]["Iloc"]
    alias = ic["backgroundImageAlias"]

with open(alias_file, "rb") as fh:
    expected = fh.read()

bad = []
if b"/Volumes/" + volname.encode() not in alias:
    bad.append("background alias does not point at /Volumes/%s" % volname)
if alias != expected:
    bad.append("background alias is not the canonical one")
if ic.get("backgroundType") != 2:
    bad.append("backgroundType is not a picture")
if ax >= bx:
    bad.append("the app icon is not left of Applications")
if ay != by:
    bad.append("the two icons are not on the same row")

print("dmg layout: iconSize=%g window=%s app=(%d,%d) Applications=(%d,%d)"
      % (ic["iconSize"], win, ax, ay, bx, by))
if bad:
    sys.exit("✗ dmg layout unusable: " + "; ".join(bad))
PYEOF
then
    hdiutil detach "$MNT" -force >/dev/null 2>&1 || true
    echo "✗ dmg layout verification failed"
    exit 1
fi
hdiutil detach "$MNT" >/dev/null 2>&1 || hdiutil detach "$MNT" -force >/dev/null 2>&1 || true

# 6) What the friend actually needs to read.
cat > "$DIST/安装说明.txt" <<EOF
ScheutieOS $VERSION（build $BUILDTAG）安装说明
================================================

这是一个套着原生窗口的 DeepSeek 网页客户端：有独立图标、独立窗口、
不依赖浏览器标签页。登录状态、聊天记录都存在你的账号里，换机器登录即可。

【系统要求】
  · Apple Silicon 的 Mac（M1 / M2 / M3 / M4 系列）
  · macOS 13.0 或更高版本
  （Intel 芯片的 Mac 不支持）

【三种安装方式，任选其一】
  想要"拖进去"的那个窗口 → 发 .dmg；只求最快装好 → 发 .pkg。
  .zip 解压后是光秃秃一个 app，【不会】出现拖拽窗口。

▲ 方式 A · 最省事：pkg 安装包
  1. 双击 ScheutieOS-$VERSION.pkg
  2. 一路「继续」→「安装」，输入开机密码
  3. 完成后在「应用程序」里找到 ScheutieOS
  ※ 这种方式装出来的 app 不会被标记为"来自网络"，以后打开不会再询问。

▲ 方式 B · 有拖拽提示窗口：DMG 磁盘映像
  1. 双击 ScheutieOS-$VERSION.dmg，会弹出一个窗口：
     左边是 ScheutieOS 图标，右边是 Applications 文件夹，中间一个箭头
  2. 把左边的图标拖到右边的「Applications」上
  3. 拖完推出磁盘（桌面上的磁盘图标 → 右键 → 推出），然后从「应用程序」启动
  ※ 因为是从网上下载的，第一次打开时 macOS 可能仍会问一次，见下方「安全提示」。

▲ 方式 C：zip 解压拖入（没有拖拽窗口）
  1. 解压 ScheutieOS-$VERSION.zip，得到 ScheutieOS.app
  2. 把它拖进「应用程序」文件夹

【安全提示 —— 为什么 macOS 会拦一下】
  本 app 没有加入 Apple 的付费开发者计划（99 美元/年），所以没法通过
  Apple 的公证。macOS 对"没有公证"的软件都会多一次确认，这是系统保护，
  不代表文件有问题。介意的话可以不装。
  如果提示"无法验证开发者"或"已损坏"，任选其一：
    · 系统设置 → 隐私与安全性 → 往下找到提示 → 「仍要打开」
    · 或在「终端」里粘贴并回车（只去掉网络下载标记，不改动 app 本身）：
      xattr -dr com.apple.quarantine "/Applications/ScheutieOS.app"
  用方式 A（pkg）安装则通常不会遇到这一步。

【常用快捷键】
  ⌘N 新建窗口（一个窗口一个页面，没有标签页）
  ⌘R 重新载入     ⇧⌘H 回到首页     ⌘F 页内查找     ⌃⌘F 全屏
  对话菜单：⇧⌘W 导出 Markdown · ⇧⌘E 复制 Markdown · ⇧⌘R 复制选中内容
           ⇧⌘T 复制全文 · ⇧⌘Y 导出 txt · ⇧⌘U 字数统计 · ⌘P 打印/存 PDF
  界面语言：增强 → 语言（中/英/法/俄/西/阿/日/韩）。只影响本 app 自己的
  菜单和提示文字，对话内容、你的输入、AI 的回复一律不会被改动。
EOF

echo "==> done"
ls -lh "$DIST" | tail -n +2
