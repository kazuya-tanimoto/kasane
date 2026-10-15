# Kasane

Mac 用のクリップボード管理アプリです。Raycast / Paste のような検索とプレビューの画面に、Clibor の FIFO / LIFO 連続ペーストを組み合わせています。

- macOS 26 以上、Apple Silicon のみ
- 履歴はローカルの SQLite に保存します（同期なし）
- ライセンス: MIT

> 開発中（MVP）です。設定画面や英語表示はまだありません。見た目は[デザインモック](https://claude.ai/artifact/Ln3dutffPpCU8sWcVu5c1L)の「C案 改訂版」をもとに、実機で微調整する前提です。

## できること

- クリップボードの履歴（テキスト、リッチテキスト、URL、画像、ファイル）を保存
- fzf と同じ考え方のあいまい検索。ローマ字でも日本語の項目にヒット（`kaigi` で「会議」）
- 画面中央に出る履歴ウインドウで、キーボードだけで選んで元のアプリに自動ペースト
- ピン留め、並び順の切り替え（コピー日時順 / 貼り付け回数順）
- FIFO / LIFO モード: コピーした順（または逆順）に、⌘V で 1 件ずつ貼り付け。全部貼り付けると自動で解除
  - モード中は履歴ウインドウの左のリストがキュー（スタック）に切り替わり、番号は貼り付ける順番
  - 履歴ウインドウを閉じている間は、画面の隅にキューの中身を小さく表示
- 見た目: メニューバーの「見た目」で不透明度、背景のぼかしの強さ、小さな表示の位置を変えられる

## ショートカット（仮）

| キー | 動作 |
| --- | --- |
| ⌃⌘V | 履歴ウインドウを開く / 閉じる |
| ⌃⌥⌘F | FIFO モードの開始 / 終了 |
| ⌃⌥⌘L | LIFO モードの開始 / 終了 |

履歴ウインドウの中:

| キー | 動作 |
| --- | --- |
| ↑ ↓ | 選択 |
| ⏎ | 元のアプリに貼り付け |
| ⇧⏎ | 書式なしで貼り付け |
| ⌥⏎ | コピーだけする |
| ⌘1〜⌘9 | 上から n 番目を貼り付け |
| ⌘I | プレビューの下に詳細（種類、コピー元、日時など）を出す / 隠す |
| Tab | FIFO / LIFO 中、キューと履歴の表示を切り替え |
| ⌘P | ピン留め / 解除 |
| ⌘⌫ | 削除 |
| Esc | 検索語を消す。空なら閉じる |

ショートカットは次のコマンドで変えられます（設定画面は今後追加します）。変えたらアプリを再起動してください。

```sh
defaults write io.github.kazuya-tanimoto.kasane hotkey.history "shift+cmd+v"
defaults write io.github.kazuya-tanimoto.kasane hotkey.fifo "ctrl+opt+cmd+f"
defaults write io.github.kazuya-tanimoto.kasane hotkey.lifo "ctrl+opt+cmd+l"
```

## ビルド

必要なもの: Xcode 26 以上（macOS 26 SDK と Swift 6.2）

```sh
git clone https://github.com/kazuya-tanimoto/kasane.git
cd kasane
make test   # ユニットテスト
make run    # build/Kasane.app を作って起動
```

### 権限が外れないようにする（開発時）

ad-hoc 署名だとビルドのたびに署名が変わり、アクセシビリティの許可が外れることがあります。自己署名の証明書で署名すると、ビルドし直しても許可が残ります。

1. 「キーチェーンアクセス」を開き、メニューの「キーチェーンアクセス > 証明書アシスタント > 証明書を作成…」を選ぶ
2. 名前を `Kasane Dev`、固有名の種類を「自己署名ルート」、証明書のタイプを「コード署名」にして作成する
3. その証明書で署名してビルドする

```sh
make run SIGN_IDENTITY="Kasane Dev"
```

## 初回起動時の権限

| 権限 | 用途 |
| --- | --- |
| 他のアプリからのペースト | クリップボードの履歴を取る |
| アクセシビリティ | 自動ペースト、FIFO / LIFO 中の ⌘V の検知 |

初回起動時に案内の画面が出ます。あとからメニューバーの「権限の設定…」でも開けます。

## 公証なしのアプリを開く

GitHub Releases から入手したアプリは公証していないため、初回起動時に警告が出ます。「システム設定 > プライバシーとセキュリティ」を開き、Kasane の「このまま開く」を選んでください。

## 構成

| ディレクトリ | 内容 |
| --- | --- |
| `Sources/KasaneCore` | あいまい検索、文字の正規化、FIFO / LIFO のキュー（OS に依存しない） |
| `Sources/KasaneStore` | 履歴の保存（SQLite / GRDB）。重複の統合、件数の上限、ピン留め |
| `Sources/Kasane` | アプリ本体（AppKit / SwiftUI）。監視、ペースト、ウインドウ、メニューバー |
| `docs/manual-test.md` | 実機での確認項目 |

データは `~/Library/Application Support/Kasane/` に保存します。
