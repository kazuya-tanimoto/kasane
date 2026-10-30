.PHONY: app run test clean dev-cert

# 署名に使う証明書名。未設定ならキーチェーンの「Kasane Dev」、無ければ ad-hoc（scripts/build-app.sh で決める）
SIGN_IDENTITY ?=

app:
	SIGN_IDENTITY="$(SIGN_IDENTITY)" scripts/build-app.sh

# 前の Kasane が終わりきる前に open すると -600 で失敗するので、終わるのを待つ。
# プロセスが消えたあとも macOS 側の後始末が残っていると -600 になることがあるので、少し待って開き直す
run: app
	@pkill -x Kasane || true
	@for i in $$(seq 50); do pgrep -x Kasane >/dev/null || break; sleep 0.1; done
	@for i in 1 2 3 4 5; do open build/Kasane.app 2>/dev/null && exit 0; sleep 0.5; done; open build/Kasane.app

test:
	swift test

# 開発用の自己署名の証明書「Kasane Dev」をターミナルだけで作る
dev-cert:
	scripts/create-dev-cert.sh

clean:
	rm -rf .build build
