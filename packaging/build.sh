#!/usr/bin/env bash
# Levelarium release build: .love, Windows zip + Setup.exe, Linux AppImage, SHA256SUMS.txt.
#
#   bash packaging/build.sh [VERSION]          # VERSION defaults to VERSION in scripts/settings.lua
#   TARGETS="love" bash packaging/build.sh     # only some targets: love win installer appimage
#
# Needs: bash, curl, unzip, python3, sha256sum. For `installer`: makensis (apt install nsis).
# For `appimage`: appimagetool is downloaded into $WORK (set APPIMAGETOOL=/path to use your own).
# The build downloads the official LÖVE 11.5 binaries from github.com/love2d/love (no credentials needed
# and none are read). Output goes to dist/ (git-ignored).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG="$ROOT/packaging"
cd "$ROOT"

VERSION="${1:-$(sed -n 's/.*VERSION *= *"\([^"]*\)".*/\1/p' scripts/settings.lua | head -1)}"
VERSION="${VERSION#v}"
[ -n "$VERSION" ] || { echo "cannot determine version" >&2; exit 1; }

LOVE_VERSION="${LOVE_VERSION:-11.5}"
LOVE_BASE="https://github.com/love2d/love/releases/download/$LOVE_VERSION"
WORK="${WORK:-$ROOT/dist/work}"
DIST="${DIST:-$ROOT/dist}"
TARGETS="${TARGETS:-love win installer appimage}"
APP=Levelarium
LOVE_FILE="$DIST/$APP-v$VERSION.love"

mkdir -p "$WORK" "$DIST"
has() { [[ " $TARGETS " == *" $1 "* ]]; }
fetch() { [ -s "$2" ] || curl -fL --retry 3 -o "$2" "$1"; }

echo "== $APP $VERSION (targets: $TARGETS)"

# ---- 1. .love: only what the game needs at run time (no tests, packaging, git data, levels) ----
build_love() {
    rm -f "$LOVE_FILE"
    python3 - "$ROOT" "$LOVE_FILE" <<'PY'
import os, sys, zipfile
root, out = sys.argv[1], sys.argv[2]
include = ["main.lua", "conf.lua", "LICENSE", "scripts", "assets"]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for item in include:
        p = os.path.join(root, item)
        if os.path.isfile(p):
            z.write(p, item)
        elif os.path.isdir(p):
            for d, _, files in os.walk(p):
                for f in sorted(files):
                    full = os.path.join(d, f)
                    z.write(full, os.path.relpath(full, root))
PY
    echo "built $LOVE_FILE"
}
build_love

# ---- 2. Windows: fused exe next to the LÖVE runtime DLLs, portable zip ----
build_win() {
    local zip="$WORK/love-$LOVE_VERSION-win64.zip" dir="$WORK/love-$LOVE_VERSION-win64"
    fetch "$LOVE_BASE/love-$LOVE_VERSION-win64.zip" "$zip"
    [ -d "$dir" ] || unzip -q "$zip" -d "$WORK"
    local stage="$WORK/win/$APP"
    rm -rf "$WORK/win"; mkdir -p "$stage"
    cat "$dir/love.exe" "$LOVE_FILE" > "$stage/$APP.exe"
    cp "$dir"/*.dll "$stage/"
    cp "$dir/license.txt" "$stage/license.txt"
    cp LICENSE "$stage/LICENSE-$APP.txt"
    cp README.md "$stage/README.md"
    python3 - "$stage" "$DIST/$APP-v$VERSION-windows-x64.zip" "$APP" <<'PY'
import os, sys, zipfile
stage, out, app = sys.argv[1:4]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for f in sorted(os.listdir(stage)):
        z.write(os.path.join(stage, f), app + "/" + f)
PY
    echo "built $DIST/$APP-v$VERSION-windows-x64.zip"
}

# ---- 3. Windows installer (NSIS, per-user, no admin rights) ----
build_installer() {
    command -v makensis >/dev/null || { echo "makensis not found (apt install nsis)" >&2; return 1; }
    [ -d "$WORK/win/$APP" ] || build_win
    makensis -V2 \
        -DVERSION="$VERSION" \
        -DSTAGE_DIR="$WORK/win/$APP" \
        -DICON_FILE="$WORK/love-$LOVE_VERSION-win64/game.ico" \
        -DOUT_FILE="$DIST/$APP-Setup-v$VERSION.exe" \
        "$PKG/installer.nsi"
    echo "built $DIST/$APP-Setup-v$VERSION.exe"
}

# ---- 4. Linux AppImage: the official LÖVE AppImage + our .love + a fusing AppRun ----
build_appimage() {
    local img="$WORK/love-$LOVE_VERSION-x86_64.AppImage" tool="${APPIMAGETOOL:-$WORK/appimagetool-x86_64.AppImage}"
    fetch "$LOVE_BASE/love-$LOVE_VERSION-x86_64.AppImage" "$img"
    if [ -z "${APPIMAGETOOL:-}" ]; then
        fetch "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage" "$tool"
    fi
    chmod +x "$img" "$tool"
    rm -rf "$WORK/appdir" "$WORK/squashfs-root"
    (cd "$WORK" && "$img" --appimage-extract >/dev/null)
    mv "$WORK/squashfs-root" "$WORK/appdir"
    cp "$LOVE_FILE" "$WORK/appdir/$APP.love"
    cp "$PKG/AppRun" "$WORK/appdir/AppRun"
    cp "$PKG/$APP.desktop" "$WORK/appdir/$APP.desktop"
    rm -f "$WORK"/appdir/love.desktop "$WORK"/appdir/love.svg
    cp assets/app-image.png "$WORK/appdir/$APP.png"
    chmod +x "$WORK/appdir/AppRun"
    # --appimage-extract-and-run: works on build machines without FUSE (CI containers)
    ARCH=x86_64 "$tool" --appimage-extract-and-run "$WORK/appdir" "$DIST/$APP-v$VERSION-linux-x86_64.AppImage"
    echo "built $DIST/$APP-v$VERSION-linux-x86_64.AppImage"
}

has win && build_win
has installer && build_installer
has appimage && build_appimage

( cd "$DIST" && rm -f SHA256SUMS.txt && sha256sum "$APP"-* > SHA256SUMS.txt && cat SHA256SUMS.txt )
