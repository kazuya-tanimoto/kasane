#!/usr/bin/env bash
# Kasane.app を組み立てる。
#
#   scripts/build-app.sh            # release ビルド、ad-hoc 署名
#   SIGN_IDENTITY="Kasane Dev" scripts/build-app.sh   # 自己署名の証明書で署名（権限が外れにくい）
#   CONFIG=debug scripts/build-app.sh
set -euo pipefail

CONFIG="${CONFIG:-release}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
BUNDLE_ID="io.github.kazuya-tanimoto.kasane"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Kasane.app"

cd "$ROOT"
swift build -c "$CONFIG" --product Kasane
BIN_DIR="$(swift build -c "$CONFIG" --product Kasane --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Kasane" "$APP/Contents/MacOS/Kasane"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# 依存パッケージのリソース（GRDB の PrivacyInfo など）
for bundle in "$BIN_DIR"/*.bundle; do
  [ -e "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"
done

codesign --force --deep --sign "$SIGN_IDENTITY" --identifier "$BUNDLE_ID" "$APP"
echo "Built: $APP (signed with: $SIGN_IDENTITY)"
