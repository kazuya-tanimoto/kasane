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

# 証明書が見つからないと codesign は「no identity found」としか言わないので、先に調べて対処を出す
if [ "$SIGN_IDENTITY" != "-" ]; then
  identities="$(security find-identity -p codesigning 2>/dev/null || true)"
  if ! grep -qF "\"$SIGN_IDENTITY\"" <<<"$identities"; then
    echo "error: 署名用の証明書「$SIGN_IDENTITY」がキーチェーンにありません。" >&2
    echo "  README の「権限が外れないようにする」の手順で、ログインキーチェーンに作成してください。" >&2
    exit 1
  fi
  if grep -F "\"$SIGN_IDENTITY\"" <<<"$identities" | grep -q "CSSMERR_TP_NOT_TRUSTED"; then
    echo "error: 証明書「$SIGN_IDENTITY」が信頼されていません。" >&2
    echo "  キーチェーンアクセスで証明書を開き、「信頼 > コード署名」を「常に信頼」にしてください。" >&2
    exit 1
  fi
fi

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
