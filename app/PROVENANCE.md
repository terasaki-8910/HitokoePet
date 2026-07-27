# app/ の由来

このディレクトリは自作コードではない。上流プロジェクトの一部を取り込んだもの。

- 上流: https://github.com/crafter-station/petdex
- 取り込んだパス: `packages/petdex-desktop-native`
- 取り込み時点のコミット: `6e205e582786e8ab35660d722ce8d8ccfe9133f6` (`chore(desktop): 0.3.1`)
- ライセンス: MIT (`app/LICENSE`、Copyright (c) 2026 Crafter Station)
- 取り込み方法: `git subtree`（履歴7コミットを保持）

MIT のため利用・改変・再配布は可能だが、**`app/LICENSE` の著作権表示を削除してはならない**。
本プロジェクト自身の改変部分の著作権は別途本プロジェクトに属する。

## 上流の更新を取り込む手順

上流は活発に更新されている（本体は780コミット、日次push）。取り込みには
`packages/petdex-desktop-native` だけを切り出す必要がある。

```sh
# 1. 上流をどこかにフルクローンする（--depth 1 では subtree split できない）
git clone https://github.com/crafter-station/petdex.git /tmp/petdex

# 2. 対象パッケージだけの履歴を切り出す
cd /tmp/petdex
git subtree split --prefix=packages/petdex-desktop-native -b desktop-native

# 3. 本リポジトリに取り込む
cd <このリポジトリ>
git remote add petdex-upstream /tmp/petdex
git fetch petdex-upstream desktop-native
git subtree pull --prefix=app petdex-upstream desktop-native
git remote remove petdex-upstream
```

## 上流に無い、本プロジェクト固有の改変

改変はここに追記していく。上流へ PR を返す判断や、`subtree pull` の衝突解決で
「どちらが自分の変更か」を見失わないための記録。

| 対象 | 内容 | 理由 |
| --- | --- | --- |
| （未着手） | | |
