#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_DIR="$ROOT_DIR/Tools/ultrahdr_bridge"
BUILD_DIR="$ROOT_DIR/Vendor/Builds/libultrahdr/bridge"
OUTPUT_DIR="$ROOT_DIR/Vendor/Builds/libultrahdr"

cmake -S "$SOURCE_DIR" -B "$BUILD_DIR" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0
cmake --build "$BUILD_DIR" --target ultrahdr_bridge
cp "$BUILD_DIR/ultrahdr_bridge" "$OUTPUT_DIR/ultrahdr_bridge"
chmod 755 "$OUTPUT_DIR/ultrahdr_bridge"

echo "Built $OUTPUT_DIR/ultrahdr_bridge"
