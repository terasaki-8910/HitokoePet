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

## Native SDK のバージョン固定（spike で確定、2026-07-29）

`app/app.zon` の `.floating = true` / `.transparent = true` は、公開されている
`@native-sdk/cli`（npm、0.4.0〜0.6.1 の全バージョン）の `ShellWindow` スキーマには
一度も存在したことがないフィールドである（ソースレベルで全バージョン確認済み）。
上流 petdex 自身も同じ理由でこの npm パッケージを使っていない
（`.github/workflows/desktop-native-ci.yml` に明記あり）。

**固定するSDK**:

```
remote: https://github.com/Railly/native.git
branch: feat/floating-window-0.5.3
commit: 65d4885cb5f76a5d1f33cace56b93a898f7b2cb3
```

このコミットから `zig build cli` で `native` バイナリを自前でビルドして使う
（上流CIと同じ手順）。npm 版の `@native-sdk/cli` は使わない。

**Windows で実機確認済み（2026-07-29）**:
- `native build app` 成功
- 実ウィンドウで `WS_EX_TOPMOST` / `WS_EX_LAYERED` を確認（最前面・透過とも実機能）
- 実デスクトップキャプチャで、ペットの背景越しに他ウィンドウが透けて見えることを確認

**macOS での同等確認（S2）は未実施**。上流CIはmac/linux/windows全てこのピンで
ビルドを通しているため通る可能性は高いが、実機未確認。

## 既知の課題（上流SDK起因、対応要否は build 段階で判断）

| 課題 | 内容 | 対応方針 |
| --- | --- | --- |
| Windows: 透過部分にノイズ | ペット背景の透過領域に、正しい合成がされていないような視覚的ノイズが乗る（実機確認、2026-07-29）。**追加調査で判明**: ウィンドウを全く異なるデスクトップ位置（VS Codeのファイルツリー上 → 何もない壁紙上）へ実際に移動して撮り比べたところ、背景内容がほぼ変わらなかった（`magick compare` RMSE 7%）。これは背後のデスクトップが透けているのではなく、**アプリ自身が持つ古い描画内容（前のUI状態の残留ピクセル）が透過されるべき領域に残っている**可能性を強く示す。実際のウィンドウ生成コード（`CreateWindowEx` 相当）がSDKのソースツリー内に見当たらず、正確な原因（アルファブレンドかカラーキーか、どこで再描画漏れが起きるか）は未特定 | build 段階で実機コードを追って調査。原因次第で本プロジェクト側での対応可否を判断 |
| つまみドラッグが macOS 以外で無効 | `fx.moveWindow`（ドラッグ中に毎フレーム呼ばれる、ウィンドウ追従エフェクト）は `runtime/effects.zig` の `window_actions` バインディングが macOS 起動コードでしか設定されず、Windows・Linux の `root.zig` には一切実装が無い。OSレベルでのマウスドラッグ実機シミュレーションで再現確認済み（2026-07-29、ウィンドウ移動量ゼロ） | 3.1 のスコープ拡張として対応（下記） |
| アイドル時CPU、Windows/Linuxはpixelsフォールバック経路 | `native automate snapshot` が `gpu_present_path=pixels` を報告。SDKソースのコメントにより、差分転送のCPU最適化（patch present）は `.packet`（実GPUバックエンド）専用で `.pixels`（CPUソフトウェアレンダラのフォールバック、Windows/Linuxの `gpu_backend=software` はこちらに固定的に該当）には適用されない。内容が変化していなくても毎ティック相応のコストがかかっている可能性が高い（`docs/prior-art.md` 5.1） | macOSで `gpu_present_path` が `packet`（期待通り）か `pixels`（要調査）かをS2確認と合わせて確認する |

## 上流に無い、本プロジェクト固有の改変

改変はここに追記していく。上流へ PR を返す判断や、`subtree pull` の衝突解決で
「どちらが自分の変更か」を見失わないための記録。

| 対象 | 内容 | 理由 |
| --- | --- | --- |
| `app/src/hitokoe_test.zig`（新規） | criteria 段階（Stage 1）の受け入れテスト。A/B/D/H の純粋関数を参照する RED テスト。build が純粋関数を切り出すまでコンパイルできない | SPEC 5.4「状態選択・集約・口形決定は純粋関数に切り出してテストする」。`main.zig` にテストが0個のため |
| `app/src/main.zig` 末尾 | `test { _ = @import("hitokoe_test.zig"); }` の集約子1つのみ追加。フィーチャコードは未変更 | 上記テストを `native test` の探索対象に入れるため。`test` ブロックは非テストビルドに無影響 |
| （build 以降で追記）3.1 のWindows/Linux(X11) moveWindow実装は app/ 本体ではなく、固定した Native SDK フォーク側への追加パッチになる見込み。置き場所は plan 段階で決定 | | |
| `app/src/main.zig`（`physics_max_duration_ms` の直後、`Effects` 定義の直前） | フィーチャ `pure-core`（PLAN.md）。`Velocity`/`Pid`/`Status`/`Session` 型と `dragState`/`enterThrow`/`throwEnded`/`post_throw_state`/`aggregate`/`parseSession`/`mouthFrame`/`mouth_shape_count`/`rmsAt`/`mouthFrameMotion`/`focusTarget`/`parseTty` を追加。既存の `update`/`dragging` 分岐など呼び出し側は未変更（配線は別フィーチャ drag-wiring 等の仕事）。`parseSession` は `hook_server.jsonStringPub`/`jsonNumberPub`（既存の軽量JSON抽出）を再利用 | SPEC 5.4「状態選択・集約・口形決定・端末フォーカスを純粋関数に切り出す」。ACCEPTANCE A1-A5/B1-B7/D4-D11/H1-H2/H6-H8/F3/G4 |

**build 段階の環境メモ（pure-core, 2026-07-29）**: この Windows 実行環境にグローバル導入済みの
`native`（0.6.1, commit `a7509a7`）は npm 公開版で、`app/app.zon` の `floating`/`transparent`
を未知フィールドとして拒否する（`error[manifest.invalid]: ... unexpected field 'floating'`）。
本セクション冒頭に固定した `Railly/native@65d4885` フォークがこの sandboxed worktree には
無く、ネットワーク経由の取得（`git clone`/`git ls-remote`）もこの実行環境のサンドボックスで
承認されなかったため、`native test app` を実行しての機械判定はこの build セッションでは
行えていない。代わりに、追加した純粋関数群（native_sdk に非依存）と
`app/src/hitokoe_test.zig` を丸ごと隔離ディレクトリへ複製し、`zig test`（0.16.0、単体）で
24件のテスト（A1-A5/B1-B6/B6b/B7/D4-D8/D10/D11/H1/H1b/H2/H6/H8）が全て通ることを確認した
（複製は検証後に削除、コミットしていない）。`native test app` そのものでの確認は、固定
フォークを導入できる環境で改めて行うこと。
