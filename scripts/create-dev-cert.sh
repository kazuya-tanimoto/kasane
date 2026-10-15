#!/usr/bin/env bash
# 開発用の自己署名のコード署名証明書「Kasane Dev」を、ログインキーチェーンに作る。
# キーチェーンアクセスの画面を使わずに済ませるためのもの。
#
#   scripts/create-dev-cert.sh
#   make run SIGN_IDENTITY="Kasane Dev"
#
# 最後に証明書を信頼する設定で、macOS のパスワードを聞かれる。
set -euo pipefail

NAME="${1:-Kasane Dev}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
# Homebrew の OpenSSL 3 で作った .p12 は security import で読めないことがあるので、macOS 標準のものを使う
OPENSSL=/usr/bin/openssl

if security find-identity -p codesigning "$KEYCHAIN" | grep -qF "\"$NAME\""; then
  echo "証明書「$NAME」はすでにあります。"
  security find-identity -p codesigning "$KEYCHAIN" | grep -F "\"$NAME\""
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

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
echo "証明書を信頼する設定をします。macOS のパスワードを入力してください。"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

echo
security find-identity -p codesigning "$KEYCHAIN" | grep -F "\"$NAME\""
echo "作成しました。次のコマンドで署名してビルドできます:"
echo "  make run SIGN_IDENTITY=\"$NAME\""
