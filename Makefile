.PHONY: app run test clean dev-cert

# 自己署名の証明書名。未設定なら ad-hoc 署名（ビルドのたびに権限が外れることがある）
SIGN_IDENTITY ?= -

app:
	SIGN_IDENTITY="$(SIGN_IDENTITY)" scripts/build-app.sh

run: app
	-pkill -x Kasane
	open build/Kasane.app

test:
	swift test

# 開発用の自己署名の証明書「Kasane Dev」をターミナルだけで作る
dev-cert:
	scripts/create-dev-cert.sh

clean:
	rm -rf .build build
