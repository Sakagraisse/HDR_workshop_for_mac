#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_DIR="$ROOT_DIR/Vendor/Sources/libultrahdr"
BUILD_DIR="$ROOT_DIR/Vendor/Builds/libultrahdr"
BUILD_CMAKE_DIR="$BUILD_DIR/cmake"
NOTICE_DIR="$BUILD_DIR/THIRD_PARTY_NOTICES"
MANIFEST_PATH="$ROOT_DIR/Vendor/Manifest/vendor-versions.json"

require_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Missing required tool: $1"
        exit 1
    fi
}

require_tool git
require_tool cmake
require_tool python3

if ! command -v ninja >/dev/null 2>&1; then
    echo "Missing required tool: ninja"
    echo "Install Ninja, for example with Homebrew: brew install ninja"
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

REPO_URL="$(/usr/bin/python3 - <<'PY'
import json, pathlib
manifest = pathlib.Path("Vendor/Manifest/vendor-versions.json")
print(json.loads(manifest.read_text())["libultrahdr"]["repo"])
PY
)"

if [[ ! -d "$SOURCE_DIR/.git" ]]; then
    echo "Cloning libultrahdr into $SOURCE_DIR"
    mkdir -p "$(dirname "$SOURCE_DIR")"
    git clone "$REPO_URL" "$SOURCE_DIR"
fi

echo "Updating libultrahdr to $VERSION"
git -C "$SOURCE_DIR" fetch --tags --force
git -C "$SOURCE_DIR" checkout "$VERSION"

mkdir -p "$BUILD_DIR"
mkdir -p "$NOTICE_DIR"

echo "Configuring CMake build in $BUILD_CMAKE_DIR"
cmake \
    -S "$SOURCE_DIR" \
    -B "$BUILD_CMAKE_DIR" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release

echo "Building libultrahdr"
cmake --build "$BUILD_CMAKE_DIR"

for name in LICENSE NOTICE; do
    if [[ -f "$SOURCE_DIR/$name" ]]; then
        cp "$SOURCE_DIR/$name" "$NOTICE_DIR/libultrahdr-$name"
    fi
done

/usr/bin/python3 - <<'PY' "$SOURCE_DIR" "$BUILD_CMAKE_DIR" "$MANIFEST_PATH" "$VERSION"
import json
import pathlib
import subprocess
import sys

source_dir = pathlib.Path(sys.argv[1])
build_dir = pathlib.Path(sys.argv[2])
manifest_path = pathlib.Path(sys.argv[3])
requested_version = sys.argv[4]

commit = subprocess.check_output(
    ["git", "-C", str(source_dir), "rev-parse", "HEAD"],
    text=True,
).strip()
resolved_version = subprocess.check_output(
    ["git", "-C", str(source_dir), "describe", "--tags", "--exact-match"],
    text=True,
).strip()

artifacts = {}
for artifact_name in ("ultrahdr_app", "libuhdr.dylib", "libuhdr.a"):
    artifact_path = build_dir / artifact_name
    if artifact_path.exists():
        artifacts[artifact_name] = {
            "path": f"Vendor/Builds/libultrahdr/cmake/{artifact_name}",
            "size": artifact_path.stat().st_size,
        }

manifest = json.loads(manifest_path.read_text())
entry = manifest.setdefault("libultrahdr", {})
entry["repo"] = "https://github.com/google/libultrahdr.git"
entry["version"] = resolved_version or requested_version
entry["commit"] = commit
entry["license"] = "Apache-2.0"
entry["buildSystem"] = "cmake+ninja"
entry["artifacts"] = artifacts
entry["noticeFiles"] = [
    "Vendor/Builds/libultrahdr/THIRD_PARTY_NOTICES/libultrahdr-LICENSE",
    "Vendor/Builds/libultrahdr/THIRD_PARTY_NOTICES/libultrahdr-NOTICE",
]
manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")

print(f"Resolved {resolved_version} ({commit})")
for name, metadata in artifacts.items():
    print(f"{name}: size={metadata['size']}")
PY

if [[ -f "$BUILD_DIR/ultrahdr_bridge" ]]; then
    echo "Found ultrahdr_bridge at $BUILD_DIR/ultrahdr_bridge"
else
    cat <<EOF
Build complete:
  $BUILD_CMAKE_DIR/ultrahdr_app
  $BUILD_CMAKE_DIR/libuhdr.dylib

ultrahdr_bridge is still missing.
When its source is added, place the built binary here:
  $BUILD_DIR/ultrahdr_bridge

Then run:
  $ROOT_DIR/Tools/package-vendors.sh
EOF
fi
