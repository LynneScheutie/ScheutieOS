#!/bin/zsh
# Rebuild ScheutieOS with a custom icon and flush the icon caches.
#
#   ./replace_icon.sh <path to png/jpg/webp/heic/svg?>
#
# svg is not handled by sips/Pillow here — convert to png first.
set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
APP_NAME="ScheutieOS"
PY="${PY:-python3}"

if [ $# -lt 1 ]; then
  echo "usage: $0 <image file>"
  exit 1
fi

SRC="$1"
if [ ! -f "$SRC" ]; then
  echo "no such file: $SRC"; exit 1
fi

mkdir -p assets
cp "$SRC" "assets/custom-icon-source.${SRC##*.}"
"$PY" src/fit_icon.py "$SRC" "assets/icon.png"

echo "==> rebuilding with assets/icon.png"
./build.sh

echo "==> reinstalling"
pkill -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" 2>/dev/null || true
sleep 1
rm -rf "/Applications/$APP_NAME.app"
cp -R "build/$APP_NAME.app" /Applications/

# Flush icon caches so the launcher picks up the new art immediately.
touch "/Applications/$APP_NAME.app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f -R "/Applications/$APP_NAME.app" 2>/dev/null || true
killall Dock 2>/dev/null || true
killall Finder 2>/dev/null || true

echo "==> done. open -a $APP_NAME to try it"
