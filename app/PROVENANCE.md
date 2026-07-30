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

## 固定 Native SDK フォークへの Windows プラットフォーム改変（2026-07-31）

app/ 本体ではなく**固定フォーク**（`tools/native-sdk-fork/`、[[native-cli-fork-wiring]] 参照）への
パッチ。フォークは git 管理外なので、再現用に **`patches/native-sdk-fork/*.patch`（追跡対象）**に
unified diff を保存済み。フォークを再取得・再ビルドしたら当て直す。原本は
`Railly/native@feat/floating-window-0.5.3`（65d4885）。

| 対象ファイル | 改変 | 判定（実機） |
| --- | --- | --- |
| `src/platform/windows/webview2_host.cpp` + `root.zig` | **`native_sdk_windows_move_window`** を新規実装（app駆動ドラッグ `fx.moveWindow` の Windows サービス。SetWindowPos + 作業領域クランプ + カーソル/左ボタン報告。A7-A10 相当）。`.services.move_window_fn` に配線 | ✅ 合成ドラッグで窓がカーソルに完全追従（dx/dy 一致） |
| `src/platform/windows/webview2_host.cpp` | **`emitMenuAcceleratorForWindow`** を追加し WM_KEYDOWN に配線。chromeless で無効だったメニューアクセラレータ（Ctrl+W=Close、Ctrl+,=Settings）を発火 | ✅ Ctrl+W でペットが閉じる |
| `src/platform/windows/webview2_host.cpp` | **`showWindowContextMenu`** を追加し gpu_surface WM_RBUTTONUP に配線。Win32 で非対応のコンテキストメニューを、app メニュー（Settings/Close Pet）を TrackPopupMenu で表示して代替 | ✅ 右クリックでメニュー（#32768）が出る |
| `src/platform/windows/webview2_host.cpp` + `root.zig` | **`native_sdk_windows_resize_window`** を新規実装し `.services.resize_window_fn` に配線（Windows未実装だった。macOS の `resizeWindow` 相当。bottom_center アンカーで SetWindowPos）。app 起動時の `fx.resizeWindow`（窓をスプライトの実寸 192x208×scale に fit）が Windows では無言で失敗し、窓が app.zon 宣言値のまま（230x250、実際のスプライトより大きい）だったのが原因 | ✅ 窓が 134x146（192x208×scale0.7）にきちんと縮む |
| `src/platform/windows/webview2_host.cpp` | **chromeless の `style` から `WS_SYSMENU`/`WS_MINIMIZEBOX` を削除**（`WS_POPUP` のみに）。このWindows実機では `WS_CAPTION` 無しで `WS_SYSMENU` を付けても「何も描かれない」という元コードの前提が外れ、実際は非クライアント領域が約20px追加され、キャプション相当の帯（タイトル文字入り）が見えていた | ✅ `GetWindowRect` == `GetClientRect`（非クライアント領域ゼロ）を実測確認 |
| `src/platform/windows/webview2_host.cpp` | **`applyMenusToWindow` を chromeless 窓では `SetMenu` しないよう変更**（`windowIsChromeless` で早期return）。上記フラグ修正後も20pxの帯が残ったのは、app.zon の `.menus`（"Pet"）が無条件で Win32 メニューバーとして貼られていたため（"Pet" の文字はこのメニューのタイトルそのもの）。メニュー項目自体（`host->menus`/`menu_commands`）は `native_sdk_windows_set_menus` が独立して登録するため、右クリックメニューとアクセラレータには影響なし | ✅ `GetMenu` が NULL、窓上部の帯が完全に消えた |

窓がスプライト実寸にフィットしたことで、ドラッグの当たり判定（`main.zig:1469-1470` の「窓＝スプライト」前提）が実際の見た目と一致し、キャラ本体をつまんでドラッグできるようになった（従来は窓が大きすぎたため、当たり判定の矩形とキャラの描画位置がズレ、上部の狭い帯状の領域しか掴めなかった）。

### 未達（build 段階で継続）: 透過（背景の抜き）

Windows での per-pixel alpha 透過は**未実装**。原因を特定済み:
- 透過窓でも canvas クリア色が不透明テーマ背景（`runtime/canvas_widget_display.zig:82`）。
- present は alpha を 255 強制、透過は黒カラーキーのみ（`webview2_host.cpp` の設計コメント `:5273-5308`）。
- `gpu_alpha_mode="premultiplied"` に変えると app が起動時 `CallbackFailed` でクラッシュ（app 側の深い改修が必要）。

クリーンな透過には UpdateLayeredWindow(per-pixel alpha) への present 経路書き換え（SDK 作者が
「アーキテクチャ書き換え」と明記）が要る。カラーキー方式（透過窓を黒クリア）は縁のガタつき・
濃色の穴が出るため不採用。動作中の上記3機能を壊さないため、透過は独立タスクとして分離。
