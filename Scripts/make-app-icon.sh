#!/usr/bin/env bash
#
# Render the app icon, in every size every platform needs, into Panop/Assets.xcassets.
#
#   Scripts/make-app-icon.sh
#
# The drawing is Scripts/icon/main.swift: change it there and run this again. The Contents.json
# files in the catalog are written by hand and name the images this script writes.
#
# The look is the modern one; PANOP_ICON_STYLE=classic draws the plain outline version instead.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CATALOG="$ROOT/Panop/Assets.xcassets"
TOOL="$(mktemp -t panop-make-icon)"
trap 'rm -f "$TOOL"' EXIT

swiftc -O "$ROOT/Scripts/icon/main.swift" "$ROOT/Scripts/icon/modern.swift" -o "$TOOL"

make() { "$TOOL" "$@"; }

# iPhone, iPad and the App Store: one square, which the system rounds.
make ios 1024 1024 "$CATALOG/AppIcon.appiconset/icon-1024.png"

# Mac: a rounded body in a margin, at each size the Mac asks for.
for size in 16 32 64 128 256 512 1024; do
    make mac "$size" "$size" "$CATALOG/AppIcon.appiconset/mac-$size.png"
done

# Apple TV: a back layer and a front layer, which move against each other as the icon is focused.
stack() { # name, width, height
    local dir="$CATALOG/App Icon & Top Shelf Image.brandassets/$1.imagestack"
    for layer in Front:tvFront Back:tvBack; do
        local name="${layer%%:*}" variant="${layer##*:}"
        local image="$dir/$name.imagestacklayer/Content.imageset"
        local extension=png
        [[ $variant == tvBack ]] && extension=jpg # flat and opaque: far smaller as a JPEG
        make "$variant" "$2" "$3" "$image/$name.$extension"
        make "$variant" "$(($2 * 2))" "$(($3 * 2))" "$image/$name@2x.$extension"
    done
}
stack "App Icon - Large" 1280 768
stack "App Icon - Small" 400 240

# The picture above the Apple TV home screen.
shelf() { # directory, width, height
    local dir="$CATALOG/App Icon & Top Shelf Image.brandassets/$1.imageset"
    make shelf "$2" "$3" "$dir/shelf.jpg"
    make shelf "$(($2 * 2))" "$(($3 * 2))" "$dir/shelf@2x.jpg"
}
shelf "Top Shelf Image" 1920 720
shelf "Top Shelf Image Wide" 2320 720

echo "Icon written to ${CATALOG#"$ROOT/"}"
