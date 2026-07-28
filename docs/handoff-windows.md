# Windows 機への引き渡し

Windows 側の Claude Code セッションに渡すプロンプト。下の「引き渡しプロンプト」を
そのままコピーして使う。

## なぜプロンプトが要るのか（git だけでは守れないもの）

`.gitattributes` を入れたので**改行コードは解決済み**。`* text=auto eol=lf` は
`core.autocrlf` より優先されるため、Windows 側の git 設定に関係なく作業ツリーは LF になる。

git が守れないものが3つ残る。プロンプトはこの3つのためにある。

| 問題 | git が守れない理由 | 症状 |
| --- | --- | --- |
| **文字コード** | git はファイルの中身を文字コード変換しない。Shift-JIS で保存されたら Shift-JIS のまま入る | **Zig は仕様上ソースが UTF-8 必須。** 日本語コメント（CLAUDE.md の言語方針で必ず入る）を Shift-JIS で保存するとコンパイルが通らない |
| **実行ビット** | Windows のファイルシステムに実行ビットが無い | Windows で新規作成した `voice/*.sh` が `mode 100644` で入り、Linux/macOS で `Permission denied` |
| **シェルの出力先文字コード** | git の管轄外 | PowerShell 5.1 の `>` と `Out-File` は既定が **UTF-16LE**。cmd は `chcp 932`。エージェントがリダイレクトでファイルを作ると化ける |

## 引き渡しプロンプト

以下をそのまま貼る。

---

```
このリポジトリは macOS で intake（Stage 0）まで完了している。Windows 側で作業を続ける。

## 最初に必ず読むもの（この順で）
- CLAUDE.md          プロジェクト方針、言語方針、コマンド、触ってはいけない場所
- SPEC.md            何を作るか。スコープ IN / OUT / 制約
- ACCEPTANCE.md      機械判定の受け入れ基準。特に「S. spike」が他の全てに先行する
- docs/prior-art.md  先行実装3つの調査結果と実測値。再調査しないこと
- app/PROVENANCE.md  app/ は上流 petdex からの subtree。改変は必ずここの表に記録する

これらに書いてあることを再調査・再議論しないこと。書かれていない前提で作業を始めないこと。

## この環境固有の制約（重要）

1. 文字コードは UTF-8（BOM なし）以外を使わない。
   Zig は仕様上ソースが UTF-8 必須。このプロジェクトは CLAUDE.md の言語方針により
   コード・コメント・コミットメッセージが日本語なので、Shift-JIS で保存すると
   コンパイルが通らない。.editorconfig を尊重するエディタを使うこと。

2. ファイル書き込みに PowerShell のリダイレクトを使わないこと。
   PowerShell 5.1 の `>` と `Out-File` は既定が UTF-16LE。
   ファイル作成は Write / Edit ツールを使う。どうしてもシェルから書くなら
   `Set-Content -Encoding utf8NoBOM` を明示するか、PowerShell 7 を使う。

3. コンソールが cmd なら最初に `chcp 65001` を実行する（既定は 932 = Shift-JIS）。
   日本語の出力が化けたまま作業判断をしないこと。

4. 改行コードは .gitattributes が強制するので触らない。
   core.autocrlf をいじらないこと。.gitattributes の eol=lf が優先される。

5. シェルスクリプトを新規作成したら実行ビットを立てること。
   Windows は実行ビットを持たないので、そのままだと Linux/macOS で起動しない。
       git update-index --chmod=+x <path>
   コミット前に `git ls-files -s <path>` が 100755 になっているか確認する。

6. app/ は上流からの subtree。
   - app/LICENSE を改変しない（MIT の著作権表示保持義務）
   - app/ を変更したら app/PROVENANCE.md の改変一覧に必ず追記する
   - app/ の改行正規化を変えない（上流は LF。ずれると subtree pull が全ファイル衝突になる）

## 作業を始める前に確認すること

ACCEPTANCE.md の「S. spike」が未達。以下が未確認のまま他の実装を始めない。

- native build app が現行の @native-sdk/cli で通るか
- 透過ウィンドウと最前面が実際に成立するか
  （transparent / floating は SDK の現行マニフェストスキーマに存在しない。
    それでも app/app.zon は宣言している。SPEC 5.1 参照）
- app/ に SDK バージョンの固定が無い

S1-S3 が通らなければ土台（petdex-desktop-native）の選択自体が無効になる。
その場合は実装を進めず、結果を報告すること。

## やらないこと
- git push（明示的な指示がある場合のみ）
- state/ の変更（runtime 用）
- デザイントークンの変更（design ゲート経由のみ）
- SPEC.md の OUT に書かれているものの実装
```

---

## 引き渡し後、macOS 側に戻すとき

Windows 側で作った成果物を取り込む前に、macOS 側で以下を確認する。

```sh
# 1. CRLF が混入していないか
git ls-files --eol | grep -v 'i/lf' | grep -v '^i/-text'

# 2. 非 UTF-8 ファイルが無いか
git ls-files | while read f; do
  enc=$(file --mime-encoding -b "$f")
  case "$enc" in us-ascii|utf-8|binary) ;; *) echo "$enc: $f";; esac
done

# 3. シェルスクリプトの実行ビット
git ls-files -s 'voice/*.sh' 'scripts/*.sh' | awk '$1!="100755"{print "実行ビット無し: "$4}'

# 4. shebang に ^M が残っていないか
head -1 voice/*.sh scripts/*.sh 2>/dev/null | cat -A | grep '\^M' && echo "CRLF 混入"
```

4項目すべて出力が空であること。
