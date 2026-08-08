#!/bin/bash
# 打包 unsigned IPA。
# 用法: bash ./Scripts/package_unsigned_ipa.sh <derived-data-path> <version>
set -euo pipefail

DERIVED_DATA=${1:-build}
VERSION=${2:-0.1.0}

APP_PATH=$(find "$DERIVED_DATA/Build/Products/Release-iphoneos" -maxdepth 1 -name "*.app" | head -n 1)
if [ -z "$APP_PATH" ]; then
  echo "error: app bundle not found under $DERIVED_DATA/Build/Products/Release-iphoneos" >&2
  exit 1
fi
echo "found app: $APP_PATH"

mkdir -p artifacts Payload
rm -rf Payload/*.app
cp -R "$APP_PATH" Payload/
zip -qry "artifacts/LiDARMeasure-v${VERSION}-unsigned.ipa" Payload
rm -rf Payload
echo "packaged artifacts/LiDARMeasure-v${VERSION}-unsigned.ipa"
