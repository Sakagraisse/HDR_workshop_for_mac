#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/Vendor/Builds/toGainMapHDR"
DEST_DIR="$ROOT_DIR/Resources/EmbeddedTools"
MANIFEST_PATH="$ROOT_DIR/Vendor/Manifest/vendor-versions.json"
OWNER="chemharuka"
REPO="toGainMapHDR"
ASSET_NAMES=("toGainMapHDR" "GainMapKernel.ci.metallib")

require_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Missing required tool: $1"
        exit 1
    fi
}

require_tool curl
require_tool python3

VERSION="${1:-}"

if [[ -z "$VERSION" ]]; then
    VERSION="$(/usr/bin/python3 - <<'PY'
import json, pathlib
manifest = pathlib.Path("Vendor/Manifest/vendor-versions.json")
print(json.loads(manifest.read_text())["toGainMapHDR"]["version"])
PY
)"
fi

echo "Updating toGainMapHDR to $VERSION"
mkdir -p "$BUILD_DIR"
mkdir -p "$DEST_DIR"

RELEASE_API_URL="https://api.github.com/repos/$OWNER/$REPO/releases/tags/$VERSION"
TMP_DIR="$(mktemp -d /tmp/togainmaphdr.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

RELEASE_JSON_PATH="$TMP_DIR/release.json"
if ! curl -fsSL \
    -H "Accept: application/vnd.github+json" \
    "$RELEASE_API_URL" \
    -o "$RELEASE_JSON_PATH"; then
    NORMALIZED_VERSION="${VERSION#v}"
    if [[ "$NORMALIZED_VERSION" == "$VERSION" ]]; then
        exit 1
    fi

    echo "Release tag $VERSION not found, retrying with $NORMALIZED_VERSION"
    VERSION="$NORMALIZED_VERSION"
    RELEASE_API_URL="https://api.github.com/repos/$OWNER/$REPO/releases/tags/$VERSION"
    curl -fsSL \
        -H "Accept: application/vnd.github+json" \
        "$RELEASE_API_URL" \
        -o "$RELEASE_JSON_PATH"
fi
while IFS=$'\t' read -r asset_name asset_url; do
    curl -fsSL "$asset_url" -o "$BUILD_DIR/$asset_name"
    cp "$BUILD_DIR/$asset_name" "$DEST_DIR/$asset_name"
    if [[ "$asset_name" == "toGainMapHDR" ]]; then
        chmod 755 "$BUILD_DIR/$asset_name" "$DEST_DIR/$asset_name"
    fi
done < <(
    python3 - <<'PY' "$RELEASE_JSON_PATH" "${ASSET_NAMES[@]}"
import json
import pathlib
import sys

release = json.loads(pathlib.Path(sys.argv[1]).read_text())
assets = {asset["name"]: asset for asset in release.get("assets", [])}

for name in sys.argv[2:]:
    print(f"{name}\t{assets[name]['browser_download_url']}")
PY
)

python3 - <<'PY' "$RELEASE_JSON_PATH" "$BUILD_DIR" "$MANIFEST_PATH" "${ASSET_NAMES[@]}"
import hashlib
import json
import pathlib
import sys

release = json.loads(pathlib.Path(sys.argv[1]).read_text())
build_dir = pathlib.Path(sys.argv[2])
manifest_path = pathlib.Path(sys.argv[3])
asset_names = sys.argv[4:]

downloaded = {}
for name in asset_names:
    target = build_dir / name
    downloaded[name] = {
        "url": next(asset["browser_download_url"] for asset in release["assets"] if asset["name"] == name),
        "sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
        "size": target.stat().st_size,
    }

manifest = json.loads(manifest_path.read_text())
entry = manifest.setdefault("toGainMapHDR", {})
entry["repo"] = "https://github.com/chemharuka/toGainMapHDR.git"
entry["version"] = release["tag_name"]
entry["releaseURL"] = release["html_url"]
entry["license"] = "MIT"
entry["assets"] = downloaded
manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")

print(f"Fetched {release['tag_name']}")
for name, metadata in downloaded.items():
    print(f"{name}: sha256={metadata['sha256']} size={metadata['size']}")
PY

cat <<EOF
Downloaded assets:
  $BUILD_DIR/toGainMapHDR
  $BUILD_DIR/GainMapKernel.ci.metallib
Copied assets:
  $DEST_DIR/toGainMapHDR
  $DEST_DIR/GainMapKernel.ci.metallib
EOF
