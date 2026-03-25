#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_DIR="$ROOT_DIR/Vendor/Sources/libultrahdr"
BUILD_DIR="$ROOT_DIR/Vendor/Builds/libultrahdr"

if [[ ! -d "$SOURCE_DIR/.git" ]]; then
    echo "Missing git checkout at $SOURCE_DIR"
    echo "Clone or add the vendor repo first."
    exit 1
fi

VERSION="${1:-}"

if [[ -z "$VERSION" ]]; then
    VERSION="$(/usr/bin/python3 - <<'PY'
import json, pathlib
manifest = pathlib.Path("Vendor/Manifest/vendor-versions.json")
print(json.loads(manifest.read_text())["libultrahdr"]["version"])
PY
)"
fi

echo "Updating libultrahdr to $VERSION"
git -C "$SOURCE_DIR" fetch --tags --force
git -C "$SOURCE_DIR" checkout "$VERSION"

mkdir -p "$BUILD_DIR"

cat <<EOF
Recommended build:
  cmake -S "$SOURCE_DIR" -B "$BUILD_DIR/cmake" -G Ninja -DCMAKE_BUILD_TYPE=Release
  cmake --build "$BUILD_DIR/cmake"
EOF
