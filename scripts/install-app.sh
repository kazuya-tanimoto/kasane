#!/usr/bin/env bash
# build/Kasane.app を /Applications/Kasane.app に置き換える（make install / make run から呼ぶ）。
# Mac の中の Kasane を 1 つにして、Spotlight・Dock・ログイン時の起動がいつも今作ったものを開くようにする。
# 履歴（~/Library/Application Support/Kasane/）と設定（UserDefaults）はアプリの外にあるので消えない。
set -euo pipefail

BUNDLE_ID="io.github.kazuya-tanimoto.kasane"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/build/Kasane.app"
DEST="/Applications/Kasane.app"

if [ ! -d "$SRC" ]; then
  echo "error: $SRC がありません。先に make app を流してください。" >&2
  exit 1
fi

# 同じ名前の別のアプリを消さないよう、Kasane のときだけ置き換える（Info.plist が読めないときも止める）
if [ -e "$DEST" ]; then
  existing_id="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$DEST/Contents/Info.plist" 2>/dev/null || true)"
  if [ "$existing_id" != "$BUNDLE_ID" ]; then
    echo "error: $DEST は Kasane ではないので置き換えません（bundle ID: ${existing_id:-読めません}）。" >&2
    exit 1
  fi
fi

if [ ! -w /Applications ]; then
  echo "error: /Applications に書き込めません。管理者のユーザーで流してください。" >&2
  exit 1
fi

# 動いているままだと消せない・古い方が残るので、終わるのを待ってから置き換える
pkill -x Kasane || true
for _ in $(seq 50); do pgrep -x Kasane >/dev/null || break; sleep 0.1; done

rm -rf "$DEST"
mv "$SRC" "$DEST"
echo "Installed: $DEST"
