.PHONY: app run test clean

# 自己署名の証明書名。未設定なら ad-hoc 署名（ビルドのたびに権限が外れることがある）
SIGN_IDENTITY ?= -

app:
	SIGN_IDENTITY="$(SIGN_IDENTITY)" scripts/build-app.sh

run: app
	-pkill -x Kasane
	open build/Kasane.app

test:
	swift test

clean:
	rm -rf .build build
