#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEST_DIR="$ROOT_DIR/Resources/EmbeddedTools"

mkdir -p "$DEST_DIR"

copy_if_present() {
    local src="$1"
    if [[ -f "$src" ]]; then
        cp "$src" "$DEST_DIR/"
        echo "Copied $(basename "$src")"
    else
        echo "Skipping missing artifact: $src"
    fi
}

copy_if_present "$ROOT_DIR/Vendor/Builds/toGainMapHDR/toGainMapHDR"
copy_if_present "$ROOT_DIR/Vendor/Builds/toGainMapHDR/GainMapKernel.ci.metallib"
copy_if_present "$ROOT_DIR/Vendor/Builds/libultrahdr/ultrahdr_bridge"
