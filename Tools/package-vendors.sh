#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEST_DIR="$ROOT_DIR/Resources/EmbeddedTools"
NOTICE_DEST_DIR="$DEST_DIR/ThirdPartyNotices"

mkdir -p "$DEST_DIR"
mkdir -p "$NOTICE_DEST_DIR"

copy_if_present() {
    local src="$1"
    local dest_dir="${2:-$DEST_DIR}"
    if [[ -f "$src" ]]; then
        cp "$src" "$dest_dir/"
        echo "Copied $(basename "$src")"
    else
        echo "Skipping missing artifact: $src"
    fi
}

copy_if_present "$ROOT_DIR/Vendor/Builds/toGainMapHDR/toGainMapHDR"
copy_if_present "$ROOT_DIR/Vendor/Builds/toGainMapHDR/GainMapKernel.ci.metallib"
copy_if_present "$ROOT_DIR/Vendor/Builds/libultrahdr/ultrahdr_bridge"
copy_if_present "$ROOT_DIR/Vendor/Builds/libultrahdr/THIRD_PARTY_NOTICES/libultrahdr-LICENSE" "$NOTICE_DEST_DIR"
copy_if_present "$ROOT_DIR/Vendor/Builds/libultrahdr/THIRD_PARTY_NOTICES/libultrahdr-NOTICE" "$NOTICE_DEST_DIR"
