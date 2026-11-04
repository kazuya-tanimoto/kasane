#!/usr/bin/env bash
# Kasane.app を組み立てる。
#
#   scripts/build-app.sh            # release ビルド。キーチェーンに「Kasane Dev」があればそれで、なければ ad-hoc で署名
#   SIGN_IDENTITY="Kasane Dev" scripts/build-app.sh   # 名前を指定して署名（無ければエラー）
#   SIGN_IDENTITY=- scripts/build-app.sh              # 証明書があっても ad-hoc で署名
#   CONFIG=debug scripts/build-app.sh
set -euo pipefail

CONFIG="${CONFIG:-release}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
DEV_IDENTITY="Kasane Dev"
BUNDLE_ID="io.github.kazuya-tanimoto.kasane"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Kasane.app"

cd "$ROOT"

# 指定がなければ「Kasane Dev」を探す。付け忘れで ad-hoc になり、アクセシビリティの許可が外れるのを防ぐ。
# 信頼されていない証明書もここでは「ある」とみなし、下の確認でエラーにする（黙って ad-hoc にすると、許可が外れた理由が分からなくなる）
# pipefail の下で grep -q が先に読み終えると security が SIGPIPE で失敗しうるので、先に変数に入れる
if [ -z "$SIGN_IDENTITY" ]; then
  found="$(command -v security >/dev/null && security find-identity -p codesigning 2>/dev/null || true)"
  if grep -qF "\"$DEV_IDENTITY\"" <<<"$found"; then
    SIGN_IDENTITY="$DEV_IDENTITY"
  else
    SIGN_IDENTITY="-"
  fi
fi

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
if [ "$SIGN_IDENTITY" = "-" ]; then
  echo "Built: $APP (signed with: ad-hoc)"
else
  echo "Built: $APP (signed with: $SIGN_IDENTITY)"
fi
