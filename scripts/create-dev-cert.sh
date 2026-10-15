#!/usr/bin/env bash
# 開発用の自己署名のコード署名証明書「Kasane Dev」を、ログインキーチェーンに作る。
# キーチェーンアクセスの画面を使わずに済ませるためのもの。
#
#   scripts/create-dev-cert.sh
#   make run SIGN_IDENTITY="Kasane Dev"
#
# 最後に証明書を信頼する設定で、画面にパスワードの確認ダイアログが出る（ターミナルには入力しない）。
# 途中で止めた場合は、もう一度実行すれば信頼の設定からやり直す。
set -euo pipefail

NAME="${1:-Kasane Dev}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
# Homebrew の OpenSSL 3 で作った .p12 は security import で読めないことがあるので、macOS 標準のものを使う
OPENSSL=/usr/bin/openssl

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

trust() {
  echo "証明書を信頼する設定をします。画面に出る確認ダイアログで macOS のパスワードを入力してください。"
  echo "（ターミナルには入力しないでください。ダイアログはほかのウインドウの裏に出ることがあります）"
  security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$1"
}

finish() {
  echo
  security find-identity -p codesigning "$KEYCHAIN" | grep -F "\"$NAME\""
  echo "準備できました。次のコマンドで署名してビルドできます:"
  echo "  make run SIGN_IDENTITY=\"$NAME\""
}

existing="$(security find-identity -p codesigning "$KEYCHAIN" | grep -F "\"$NAME\"" || true)"
if [ -n "$existing" ]; then
  echo "証明書「$NAME」はすでにあります。"
  if grep -q "CSSMERR_TP_NOT_TRUSTED" <<<"$existing"; then
    security find-certificate -c "$NAME" -p "$KEYCHAIN" > "$WORK/cert.pem"
    trust "$WORK/cert.pem"
  fi
  finish
  exit 0
fi

cat > "$WORK/cert.cnf" <<EOF
[req]
distinguished_name = dn
prompt = no
x509_extensions = ext
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -config "$WORK/cert.cnf" -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null
"$OPENSSL" pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -name "$NAME" -passout pass:kasane -out "$WORK/cert.p12"

# codesign が鍵を使うたびに確認を出さないよう、codesign に鍵の利用を許可しておく
security import "$WORK/cert.p12" -k "$KEYCHAIN" -P kasane -T /usr/bin/codesign
trust "$WORK/cert.pem"
finish
