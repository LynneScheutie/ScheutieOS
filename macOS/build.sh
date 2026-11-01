#!/bin/zsh
# Build ScheutieOS.app — a native macOS window shell for chat.deepseek.com
set -e

APP_NAME="ScheutieOS"
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
BUILD="$ROOT/build"

PY="${PY:-python3}"
SWIFTC="$(xcrun -f swiftc)"
SDK="$(xcrun --show-sdk-path)"

mkdir -p "$BUILD"

# 1) icon — assets/icon.png (custom) wins over the generated one.
# Regenerate whenever a source is newer than the built icns; a plain
# "only if missing" check would silently keep an old icon forever.
ICON_OUT="$BUILD/icon_1024.png"
ICNS="$BUILD/AppIcon.icns"
need_icon=0
[ ! -f "$ICNS" ] && need_icon=1
[ -f "$ROOT/assets/icon.png" ] && [ "$ROOT/assets/icon.png" -nt "$ICNS" ] && need_icon=1
[ "$ROOT/src/make_icon.py" -nt "$ICNS" ] && need_icon=1
[ "$ROOT/src/fit_icon.py" -nt "$ICNS" ] && need_icon=1

if [ $need_icon -eq 1 ]; then
  echo "==> generating icon"
  if [ -f "$ROOT/assets/icon.png" ]; then
    echo "    using custom icon: assets/icon.png"
    "$PY" src/fit_icon.py "$ROOT/assets/icon.png" "$ICON_OUT"
  else
    "$PY" src/make_icon.py "$ICON_OUT"
  fi
  rm -rf "$BUILD/AppIcon.iconset"
  mkdir -p "$BUILD/AppIcon.iconset"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$ICON_OUT" --out "$BUILD/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
    d=$((s * 2))
    sips -z $d $d "$ICON_OUT" --out "$BUILD/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$BUILD/AppIcon.iconset" -o "$ICNS"
fi

# The system icon cache lives at /Library/Caches/com.apple.iconservices.store and
# is root-owned, so it cannot be cleared without sudo — instead give the icon a
# content-hashed filename. A changed CFBundleIconFile is a changed cache key, so
# the launcher picks up new art immediately, no privileges required.
ICON_NAME="AppIcon-$(md5 -q "$ICON_OUT" | cut -c1-10)"

# 2) Info.plist from template (icon name injected here)
sed "s/@@ICON@@/$ICON_NAME/g" src/Info.plist.in > "$BUILD/Info.plist"
plutil -lint "$BUILD/Info.plist" >/dev/null

# 3) compile — arm64 only. Intel Macs are explicitly out of scope; a universal
#    build would promise x86_64 support that cannot even be smoke-tested here
#    (macOS 27 has no working Rosetta), and an untestable promise is worse than
#    a stated requirement.
#    The deployment target comes from Info.plist.in so the binary's minos and
#    the bundle's LSMinimumSystemVersion can never disagree.
MIN_OS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' src/Info.plist.in)"
echo "==> compiling for arm64 (macOS $MIN_OS)"
"$SWIFTC" -O -swift-version 5 \
  -target "arm64-apple-macosx$MIN_OS" -sdk "$SDK" \
  -framework Cocoa -framework WebKit \
  -o "$BUILD/$APP_NAME" src/main.swift src/Enhance.swift src/About.swift src/L10n.swift

lipo -info "$BUILD/$APP_NAME"

# 4) assemble bundle
echo "==> assembling $APP_NAME.app"
APP="$BUILD/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD/Info.plist" "$APP/Contents/Info.plist"
cp "$BUILD/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp "$ICNS" "$APP/Contents/Resources/$ICON_NAME.icns"

# Drop stale icon files so leftover art can never be resolved.
find "$APP/Contents/Resources" -name '*.icns' ! -name "$ICON_NAME.icns" -delete 2>/dev/null || true

codesign --force -s - "$APP" 2>/dev/null || true

echo "==> built $APP  (icon: $ICON_NAME.icns)"
