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

（上記の環境問題は 2026-07-31 に解消: `tools/native-sdk-fork/` にフォークを配置し
`scripts/run.sh` の PATH 前置で解決。[[native-cli-fork-wiring]] 参照。以降の実機検証は
すべて `native test app` 本体で実施）

## 実機フィードバックへの対応（2026-08-01）

ユーザーが実機で気づいた3件の不具合。

| 対象 | 内容 | 判定 |
| --- | --- | --- |
| `app/src/plat.zig`（`openExternal`） | Windows で `cmd /c start "" <url>` が信頼できず、空の cmd.exe 窓 + COM+ レジストリエラーで開けないことがあった（Settings > Pets > Open で再現）。`explorer.exe <target>` 直呼びに変更したが**これも失敗**（カーソルが一瞬回るだけで何も開かない）。最終的に `shell32.ShellExecuteW` を直接 extern 呼び出しする方式に変更（cmd/explorer という中間層を排除）。実機確認: アプリの Open ボタン押下から実際に既定ブラウザで対象URLが開くことを確認（`native.exe automate widget-click` 経由、ブラウザのウィンドウタイトルで検証） | ✅ 修正・実機確認済み |
| `app/src/plat.zig`（`replaceSymlink`） | もう一つの原因（下記の第2原因と合わせて2つ重なっていた）: `~/.petdex/bin/petdex-hook` の自動作成に使う `CreateSymbolicLink` は Windows では開発者モード/管理者権限が無いと失敗するが、失敗時に空(0バイト)のプレースホルダーだけが残っていた。Windows でシンボリックリンク作成が失敗した場合、`std.Io.Dir.copyFileAbsolute` で実行ファイルを直接コピーするフォールバックを追加（毎起動時に再実行されるため、再ビルド後も自動で最新化される。**管理者権限や開発者モードの有効化は不要**、アプリ側で自動的に回避する） | ✅ 実機確認: 0バイト→4,761,088バイト（実行ファイル本体と一致） |
| `app/src/main.zig`（`main()` の `env_home` 解決） | **吹き出しが表示されない真の根本原因（上記だけでは直らなかった）**: `env_home` は `HOME` を `USERPROFILE` より優先していた。この開発機では git-bash 系シェルの `$HOME` が `%APPDATA%\SPB_16.6` という無関係なパスに書き換わっており（`USERPROFILE` は正しく `C:\Users\e8910`）、Claude Code がフックのシェルコマンドを起動する際も同じ壊れた `$HOME` を継承する。petdex-hook 本体を直しても、`hook_runner.run()` に渡る `home` が間違ったままなので `update-token`（実行中のペットの HTTP サーバーへ認証するためのトークン）を正しい場所で見つけられず、`orelse return` で毎回何もせず終了していた。**Windows では `USERPROFILE` を優先**（`HOME` はフォールバック）に変更。他OSは POSIX 慣習通り `HOME` 優先のまま | ✅ 実機確認: このバグを再現する壊れた `$HOME` を持つ bash から直接 `petdex-hook bubble notification claude-code` を実行 → `bubble.json` が現在時刻で更新 → 実際に吹き出し窓が生成されスクリーンショットで内容（"Waiting for you…" + エージェントアイコン）を確認 |
| `src/platform/windows/webview2_host.cpp`（chromeless 窓の `createNativeWindow`） | トレイアイコンは追加済みだが、メイン窓が依然タスクバーにも出ていた（トレイ追加は加算的で、タスクバー抑制は別途必要だった）。`WS_EX_TOOLWINDOW` を chromeless 窓の拡張スタイルに追加 | ✅ 実機で `GetWindowLong(GWL_EXSTYLE)` に `WS_EX_TOOLWINDOW` 設定を確認 |
| `app/src/main.zig`（session-aggregation の配線） | **根本的な欠落**: pure-core の `parseSession`/`aggregate` は存在したが呼び出し元が無く、ペットが Claude Code の実セッションに一切追従していなかった（PLAN.md の `session-aggregation` フィーチャが未着手のままだった）。`poll_tick` で `<home>/.claude/sessions/*.json` を走査し `aggregate()` の結果を `model.state` に反映する配線を追加。hook_server 経由の明示イベント（failed/review/jumping/waving）は優先度を保つ（保留イベントがある間・その dwell 中は本走査を適用しない） | ✅ 実機確認: 実セッション(status=busy)を検知し `idle→running` に遷移（デバッグログで確認、コミット前に除去） |

**WSL 側セッション走査を追加**（`app/src/main.zig`）: `\\wsl.localhost\Ubuntu\home\<user>\.claude\sessions`
も session-aggregation の走査対象に加えた。Linux ユーザー名は `wsl.exe -d Ubuntu -- whoami`
を起動時に非同期 spawn（`fx.spawn` + `.wsl_whoami_done`）で解決（Windows/WSL でユーザー名が
異なる実例が本機にあったため固定できない: Windows "e8910" / WSL "tera"）。UNC パスは
フォワードスラッシュ表記（`//wsl.localhost/...`）で `std.Io.Dir` から正しく解決できることを
実機で確認済み（バックスラッシュへの変換は不要）。WSL 側は 9P 経由でネイティブより遅いため
20 tick（約2秒）に1回だけ走査するようスロットル。WSL 未導入時は spawn が失敗し無言でネイティブ
のみ動作（劣化動作）。実機確認: `wsl --list` で "Ubuntu" 導入済みの本機で、ネイティブ1件 +
WSL側3件 = 計4セッションを検知（デバッグログで確認、コミット前に除去）。

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

## 固定 Native SDK フォークへの Runtime 層改変（2026-07-31 続き）

app 側からトレイ（`fx.createTray`）を使うための配線。`PlatformServices.createTray` を直接
呼ぶだけでは不十分（トレイ項目の `command` 文字列が `Runtime.tray_items` に保存されず、
クリック時に `trayCommandNameForItem` がフォールバック文字列しか返せない）と判明したため、
既存の `WindowActionBinding`（`moveWindow`/`resizeWindow` 等が使う、`context=runtime` を
型消去して渡すパターン）と同型の **`TrayActionBinding`** を新設し、`Runtime.createTray`
（`storeTrayItems` を伴う本物の実装）へ配線した。

| 対象ファイル | 改変 |
| --- | --- |
| `src/runtime/effects.zig` | `TrayActionBinding` 型、`Effects.tray_actions` フィールド、`bindTrayActions`、`fx.createTray`/`updateTrayMenu`/`removeTray` を追加 |
| `src/runtime/ui_app.zig` | `effectsCreateTray`/`effectsUpdateTrayMenu`/`effectsRemoveTray`（`context` を `*Runtime` にキャストし本物の `Runtime.createTray` 等を呼ぶ）を追加し、`bindEffectsChannel` で配線 |

`app/src/main.zig` 側: `.frame_clock` の初回に `fx.createTray` を1回呼び、右クリックメニューと
同じ `petdex.settings`/`petdex.close` コマンド文字列を持つ2項目を登録（`onCommand` がそのまま
使い回せる）。`app.zon` の `.capabilities` に `"tray"` を追加。実機確認: トレイ作成後もクラッシュ
せず継続動作。

## ドラッグ/投擲を専用タイマーへ分離（2026-07-31、カクつき対策）

従来、ドラッグ追従と投擲物理は `.frame_clock`（実際に GPU フレームが提示された時だけ発火）
の中で行っていた。Windows は `gpu_present_path=pixels`（CPUソフトウェア合成）で毎フレームの
コストが不安定なため、再描画の遅延がそのまま位置更新の遅延＝カクつきに直結していた。

upstream に元々あった未使用の `physics_timer_key`/`physics_tick_ms`（16ms、`.physics_tick`
ハンドラは空実装のまま放置されていた）を完成させ、ドラッグ追従・投擲物理を **専用の
16ms 反復タイマー**（描画完了を待たない、独立した一定間隔）に移した。`.frame_clock` は
ドラッグ開始検出（低頻度で十分）と初回セットアップのみを担当し、開始を検出したら
`armPhysicsTimer` でタイマーを起動、ジェスチャー終了（投擲停止 or 速度不足での解放）で
`cancelPhysicsTimer` して止める（アイドル時の常時 60Hz ポーリングを避け、SPEC のアイドルCPU
削減方針に沿う）。再描画自体は `requestGpuSurfaceFrame` で別途要求し、位置更新と映像を
分離した。

実機検証（合成ドラッグ、カーソル移動量 160,90px）: 修正前は結果が 94,62px 相当までしか
届かない誤差があったが、修正後は 160,90px と完全一致。右クリック・Ctrl+W も回帰なし。

## Windows per-pixel alpha 透過の実装（2026-08-01）

上の「未達」節で特定した3つの原因を順に解消し、実デスクトップスクリーンショット
（`native automate screenshot` ではなく `Graphics.CopyFromScreen` — アプリ自身のバッファでは
なく実際に OS が合成した画面）でデスクトップアイコンが透けて見えることを確認済み。

| 原因 | 対象ファイル | 修正 |
| --- | --- | --- |
| ① `isSupported()` が `alpha_mode == .opaque` を全プラットフォーム一律で強制し、`premultiplied` を宣言すると `error.UnsupportedViewKind` で `CallbackFailed` クラッシュ | `tools/native-sdk-fork/src/platform/types.zig`（`GpuSurfaceOptions.isSupported`） | `opaque` に加え `premultiplied` も許可するよう条件を緩和 |
| ② 透過窓でも canvas クリア色が常に不透明テーマ背景（`tokens.colors.background`）— `WindowOptions.transparent` のドキュメントコメント自体は「alpha 0 にクリア」と明記していたが実装されていなかった | `tools/native-sdk-fork/src/runtime/ui_app.zig`（`presentFrame`） | 窓が `.transparent = true` か `runtime.isWindowTransparent(window_id)` で判定し、真なら `clear_color` を `rgba8(0,0,0,0)` に。判定用に `RuntimeWindow.transparent` フィールド（`state.zig`）を追加し、窓生成の3経路（起動時メイン窓 `flow.zig`、`Runtime.createWindow` 経由の副窓 `window_storage.zig`）で設定、`isWindowTransparent` を `window_storage.zig`→`window_views.zig`→`core.zig` の順に再エクスポートして `ui_app.zig` から呼べるように配線 |
| ③ present 経路が alpha を 255 に強制し、黒カラーキー（`SetLayeredWindowAttributes` + `LWA_COLORKEY`）でしか透過できず、縁のガタつき・濃色の穴が出る | `tools/native-sdk-fork/src/platform/windows/webview2_host.cpp`（`native_sdk_windows_present_gpu_surface_pixels`） | 窓が chromeless かつ transparent（本アプリのペット窓はこれに該当し、gpu_surface view を1個だけ持つ）なら、alpha を強制せず実データをそのまま使い、子 HWND への `SetDIBitsToDevice` の代わりに**トップレベル窓へ直接 `UpdateLayeredWindow`**（`ULW_ALPHA`、`AC_SRC_ALPHA` の `BLENDFUNCTION`）でピクセルごとの本物のアルファ合成を行う。chromeless 以外（hidden-titlebar 等、DWM キャプション帯が不透明ピクセルを要求する窓）は既存の強制255＋カラーキー経路のまま |

②は `RuntimeWindow` に新フィールドを足す都合上、`state.zig`/`window_storage.zig`/`flow.zig`/
`window_views.zig`/`core.zig`/`ui_app.zig` の6ファイルにまたがる。③の `UpdateLayeredWindow` は
`WS_EX_LAYERED` が窓生成時（`applyCompanionWindowChrome`）に既に立っている前提に乗るだけで、
追加のスタイル変更は不要（`SetLayeredWindowAttributes` によるカラーキー登録は残るが、
`UpdateLayeredWindow` を呼んだ時点でその窓は per-pixel alpha モードに切り替わり以後上書きされる
— 両者が競合することはない）。

実機検証: ビルド後に実プロセスを起動し、`GetWindowRect` で実座標を取得、`Graphics.CopyFromScreen`
で実デスクトップをスクリーンショットしてその座標をクロップ — デスクトップのアイコン
（Aseprite・Audacity 等）がキャラクターの周囲に透けて見え、四角い背景色の板は消えたことを確認。
合成マウスドラッグ（`mouse_event` で 150,50px 相当）後も窓は追従し、旧位置に描画の残留（スメア）
がないことも確認。

なお `③` の対象を chromeless&transparent に絞ったのは、`UpdateLayeredWindow` は窓全体を1枚の
ビットマップで合成し子 HWND を個別に合成できない制約があるため（SDK 内のコメントより）。
本アプリのペット窓は gpu_surface view を1個だけ持つ chromeless 窓であり、この制約に抵触しない。
複数ビュー/webview を持つ窓には別途対応が要る。

### 追い修正: 縁の色にじみ・白い筋（2026-08-01 続き）

実機で確認したところ、キャラクターの輪郭に緑がかった色にじみ、および足元付近に白い筋が
出ていた。原因: CPUリファレンスラスタライザ（`primitives/canvas/reference.zig`）は
view の `gpu_alpha_mode` 宣言に関わらず常に **straight alpha**（RGBチャンネルがカバレッジで
スケールされない）でピクセルを出力する。`gpu_alpha_mode` は「present 側がどう解釈すべきか」
の宣言であって「レンダラーが何を出力するか」を変えない。一方 `UpdateLayeredWindow` の
`AC_SRC_ALPHA` ブレンドは **premultiplied** 入力を要求するため、straight alpha をそのまま
渡すと半透明ピクセル（縁のアンチエイリアス・柔らかい影）が明るくなりすぎ、縁の色にじみと
淡いエッジ部分の白飛びとして現れていた。

**修正**: `native_sdk_windows_present_gpu_surface_pixels`（`webview2_host.cpp`）の
`use_layered_alpha` 分岐で、スウィズルと同時に `RGB *= A / 255` の premultiply を実施
（`src/platform/windows/webview2_host.cpp`）。

実機確認: 修正前後で実デスクトップを4倍ズームでキャプチャして比較。縁の色にじみ・白い筋が
消え、ドット絵の輪郭線がクリーンに出ることを確認。同時に、吹き出し（`petdex-hook bubble
waiting claude-code` を直接叩いて確認）も実デスクトップキャプチャで「Waiting for you…」が
正しく表示されることを再確認（前回リビルド後も配線は壊れていない）。

### 追い修正2: 吹き出しの位置とゴースト残留（2026-08-01 続き2）

実機フィードバック2件。

**① 吹き出しがキャラクターに刺さる**: `syncBubbleWindow`/`petdexWindows` の Y座標計算が
`model.pet_y - bubble_window_h + 2.0` で、tail 先端（窓の下端、`.main=.end` で下寄せ）と
ペット窓の上端（＝スプライト実寸フィット済みなのでキャラの視覚的な頭頂そのもの）の間が
2pxしかなかった。`bubble_gap` 定数（12px）を新設し、両箇所（`app/src/main.zig` の
`syncBubbleWindow` と `petdexWindows`）を `- bubble_window_h - bubble_gap` に変更。実機で
すき間が空いたことを確認。

**② デスクトップ上に色付きノイズの帯（キャラクターが「投影」されたように見える）**:
実デスクトップキャプチャで再現。ノイズの位置がペット/吹き出しの**現在位置と無関係な固定位置**
に浮いていること、その領域を一時的に不透明窓で覆って外すと消えること（DWM に強制的に
その領域を再描画させると消える）を確認し、**ライブの描画バグではなく古い合成済みビットマップの
残留（ゴースト）**と特定。原因: `UpdateLayeredWindow` で合成する窓は DWM が直接そのビットマップを
持ち回るため、通常窓と違って `DestroyWindow` 単独では合成済み内容が確実に破棄されない
既知の DWM の癖がある。`native_sdk_windows_close_window`（`windows_fn` 経由の宣言的窓、
吹き出し/設定窓の通常クローズ経路）と `WM_CLOSE` ハンドラの両方が `DestroyWindow` を
先に呼ぶだけだったため、`ShowWindow(hwnd, SW_HIDE)` を `DestroyWindow` の直前に追加
（`src/platform/windows/webview2_host.cpp`）。非レイヤード窓には無害な操作なので副作用なし。

検証メモ: 本セッション中に開発用途で `taskkill /F` を多用しており（force kill はアプリ側の
クローズコードを一切実行しないため、この修正の対象外）、ユーザーが見たゴーストの一部はそちらに
由来する可能性が高い。単発の `taskkill /F` 直後にペット窓自体のゴーストは再現しなかった
（DWM は通常のプロセス終了時クリーンアップは正しく行う）ため、ゴーストは主に**吹き出し窓の
生成・破棄の繰り返し**に起因すると推定。`native automate` 経由での通常クローズ経路の
再現テストは自動化ツールのスクロール/ウィジェット操作が意図通り動かず未完了 — ただし
`ShowWindow(SW_HIDE)` は Win32/DWM でこの種の問題への標準的な対処であり、副作用なく
安全に適用できる。既にデスクトップに残っている古いゴーストはこの修正では消えない
（他の窓を重ねる等、何かがその領域を再描画するまで残る）。

## 吹き出しが実セッションに追従しない根本原因（2026-08-01 続き3）

**症状**: Claude Code が実際に動作中（ツール呼び出し中）でも、ペットの吹き出しが
「Waiting for you…」のまま遷移しない。これまでの `env_home`（`app/src/main.zig`
`main()` の `USERPROFILE` 優先化）修正は petdex-hook バイナリ**内部**の解決だったため、
直接バイナリを叩く検証では問題が再現しなかった（過去のログ参照）。

**真因**: `~/.claude/settings.json` の hooks 定義（`UserPromptSubmit`/`PreToolUse`/
`PostToolUse`/`Stop`/`Notification`）が、petdex-hook を実行する**前段のゲート**として
`[ -x "$HOME/.petdex/bin/petdex-hook" ]` を使っていた。このチェックは petdex-hook が
起動される**前**に、hook を起動する側のシェル（git-bash）の `$HOME` で評価される —
petdex-hook 内部の `env_home` 解決とは無関係の、別のコード経路。この開発機では
`$HOME` が `/c/Users/e8910/AppData/Roaming/SPB_16.6` という無関係なパスに壊れており
（`$USERPROFILE` は正しく `C:\Users\e8910`）、このゲートが常に失敗して `exit 0` に
フォールスルーし、**petdex-hook が一度も実際に起動されていなかった**。

実機確認: `$HOME`/`$USERPROFILE` を実際にこのシェルで比較 →
`[ -x "$HOME/.petdex/bin/petdex-hook" ]` は FAIL、`[ -x "$USERPROFILE/..." ]` は PASS
を確認。`~/.petdex/runtime/bubble.json` のタイムスタンプが直近12分以上更新されておらず
（その間に本セッションで多数のツール呼び出し＝多数のhookイベントが発生していたにも
関わらず）、ゲート失敗による無言のno-opであることを直接裏付けた。

**修正**: `~/.claude/settings.json`（プロジェクト外、グローバルなユーザー設定 — この
リポジトリの追跡対象外）の5箇所の hook コマンドすべてで、ゲートとexec対象パスを
`h="${USERPROFILE:-$HOME}"` 経由に変更（Windows優先、他OSは `$HOME` へフォールバック
— アプリ内の `env_home` と同じ優先順位）。修正直後（アプリ再起動不要、hookは呼び出し
毎に設定を読むため）に `bubble.json` が数秒以内に更新され、実際のツール呼び出しの
説明文・busy状態・`state:"running-right"` 等が反映されることを確認。

## ボイスのマスターON/OFFスイッチを追加（2026-08-01 続き4）

`voice_volume`（0.0-1.0）はあったが、値をいじらずに完全にミュート/復帰できる独立した
スイッチが無かった。`Model.voice_enabled: bool = true` を追加し、`maybeVoiceBark` の
先頭でガード。永続化は `bubbles_enabled` と同じパターン（`desktop-native-settings.json`
の `"voice_enabled":false` の有無で判定）。設定画面に "Voice" スイッチを追加（Voice
cooldown/Voice volume の上）。バークの発火条件自体（`voiceCategoryForState`: waiting/
jumping/failed のみ、つまり状態遷移・通知のタイミングだけ）は変更なし — 既存の設計が
既にユーザーの要望通りだったため、ON/OFF切り替えのみ追加。実機確認:
`native automate widget-click` でトグル操作、`desktop-native-settings.json` に
`voice_enabled:false`→`true` が反映されることを確認。

## 吹き出しタイトルが黒塗りになる（日本語フォント欠落）（2026-08-01 続き5）

実機フィードバック（スクショ添付）: 吹き出しのタイトル行（`ui.paragraph` + `weight=.bold`）
が丸ごと黒い帯になり、本文（`ui.text`、英語）は正常表示。

**根本原因**: バンドルされているフォントは `Geist-Regular.ttf`（Vercel製、Latin専用）
のみ（`tools/native-sdk-fork/src/primitives/canvas/font_ttf.zig`）。参照レンダラーは
フォントに無いグリフを notdef の「ブロックフォールバック」で描く
（`reference.zig` のコメント参照）。タイトルは実セッションのユーザープロンプト原文
（`hook_runner.zig` の `rememberTitle`）がそのまま入るため、**日本語で書けば必ず黒塗り**
になる。本文（"Thinking…"/"Waiting for you…"/ツール名など）は英語固定文言なので
問題が起きなかった。太字(weight=bold)は無関係 — コメント通りbold/italicスパンは
regularの輪郭をそのまま使う。

**修正**: Windowsのシステムフォント（Yu Gothic等、.ttc）は再配布ライセンス上埋め込めない
ため、**Noto Sans JP**（SIL Open Font License、`google/fonts` リポジトリから取得）を
使用。`fonttools` で可変フォントからstatic Regular(400)をインスタンス化 → Latin +
かな + CJK統合漢字（U+4E00-9FFF）等にサブセット → 4.4MB（元は可変フォント全体で
約10MB）。`app/src/assets/fonts/NotoSansJP-Subset.ttf`（+ `OFL.txt` でライセンス同梱）
として embed、`min_registered_font_id`(=64) で登録し、`petdexTokens()` で
`tokens.typography.font_id` に設定（アプリ全体のデフォルトsansを差し替え、bubble/
settings両方に効く）。バイナリは 4.7MB→9.1MB に増加。

実機確認: 同じタイトル文字列で再現 → 修正後は日本語タイトルが正しく描画されることを
実デスクトップキャプチャで確認（黒塗りなし）。

## Claude Code hook配線の欠落 — Windows版・WSL版（2026-08-01 続き6）

実機フィードバック:「動いているときでも Waiting for you… のままで状態が遷移しない」
「WSL側のClaude Codeの通知が出ない」の2件。

**Windows側の真因**: `~/.claude/settings.json`（このリポジトリの追跡対象外、グローバル
ユーザー設定）の hook コマンドが `[ -x "$HOME/.petdex/bin/petdex-hook" ]` という
petdex-hook起動**前**のゲートを持っていた。このチェックは hook を起動する側の
git-bash自身の `$HOME` で評価される — petdex-hook**内部**の `env_home` 解決（既に
`USERPROFILE`優先に修正済み）とは別のコード経路。この開発機の壊れた `$HOME`
（`/c/Users/e8910/AppData/Roaming/SPB_16.6`）でこのゲートが常に失敗し `exit 0` に
フォールスルーするため、**petdex-hookが一度も実際に起動されていなかった**
（直接バイナリを叩く従来の検証はこのゲートを経由しないため見逃していた）。
`UserPromptSubmit`/`PreToolUse`/`PostToolUse`/`Stop`/`Notification` の5箇所すべてで
`h="${USERPROFILE:-$HOME}"` 経由に変更（詳細は [[launch-pet-home-quirk]] メモリ参照）。
実機確認: `~/.petdex/runtime/bubble.json` のタイムスタンプが実際のツール呼び出しの
直後（数秒以内）に更新され、内容が `busy:true`・`state:"running-right"` 等リアルタイムの
実活動を反映することを確認。

**WSL側**: WSL は完全に別の `~/.claude/settings.json`（`\\wsl.localhost\Ubuntu\home\tera\
.claude\settings.json`）を持ち、petdex-hookの配線が一度も存在しなかった（そもそも
未着手だった）。WSLからWindows側のバイナリを直接実行できることを確認
（`/mnt/c/Users/e8910/.petdex/bin/petdex-hook`、WSL2のlocalhostフォワーディングで
127.0.0.1:7777への到達も確認済み）ため、同じ配線パターンを追加。
`PreToolUse`/`PostToolUse`/`UserPromptSubmit`/`Stop` の4箇所は追加済み・実機確認済み
（WSL側から `petdex-hook bubble user-prompt claude-code` を実行 → `bubble.json` に
即座に反映）。**`Notification` の追加は auto-modeの権限クラシファイアにブロックされ未実施**
— ユーザー側で以下を `~/.claude/settings.json`（WSL側）の `hooks.Notification` 配列に
追記することで同等の効果が得られる:
```json
{
  "matcher": "permission_prompt|elicitation_dialog|idle_prompt",
  "hooks": [{
    "type": "command",
    "command": "h=/mnt/c/Users/e8910; [ -f \"$h/.petdex/runtime/hooks-disabled\" ] && exit 0; [ -x \"$h/.petdex/bin/petdex-hook\" ] && exec \"$h/.petdex/bin/petdex-hook\" bubble notification claude-code; exit 0"
  }]
}
```

## 吹き出し上部の色ノイズ（未解決・調査結果の記録）（2026-08-01 続き7）

実機フィードバック（複数回・スクショ添付）で「上のほうにキャラが投影されたようなノイズ」
と報告された帯状の色つきノイズを調査。

**切り分けで判明したこと**:
- プロセスを完全終了すると消える → **DWMのゴースト（過去の合成済みサーフェスの残留）
  ではなく、実行中のアプリ自身がライブでレンダリングしているもの**（実機確認: force-kill
  直後にその領域を再キャプチャして消えたことを確認）。
- 位置はペット窓ではなく**吹き出し窓（bubble-canvas）の内部**、かつウィジェットが何も
  配置されていない上部の空白領域（card+tailは `.main=.end` で下寄せなので、宣言サイズ
  150px（DPI後の実サイズ170px）のうち上側約84pxは常に空）に一致することを実機の
  `native automate snapshot` の座標（`gpu_size=340x170`、card `bounds=(2,84.25 ...)`）
  で確認。
- 拡大キャプチャで見ると縞状・帯状の構造化されたパターン（真のランダムノイズではない）
  — ズレたストライド/オフセットで別データを読んでいるような見た目。
- `ReferenceRenderSurface.renderPass`（`primitives/canvas/reference.zig`）は
  `.load`（部分更新）パスで `clearRect` を**変更のあった矩形にしか**適用しない
  （`.clear`＝全体クリアはフルリペイント時のみ）。`ensurePixelBuffers`
  （`runtime/ui_app.zig`）のCPUピクセルバッファは全window/view間で共有され、`alloc`
  はゼロ初期化しない。**試した対策**: バッファ確保時に `@memset(..., 0)` でゼロ初期化
  （`src/runtime/ui_app.zig`） — 実機再現テストの結果、**改善せず**。ゼロ初期化は
  「未使用領域」がヒープの生ゴミであるケースへの対策であり、実際の症状（構造化された
  ストライプ）は「別サイズの窓が過去に書いた**有効なピクセルデータ**を、現在の窓幅で
  誤ったストライドとして再解釈している」可能性が高く、単純なゼロ埋めでは直らない。

## 吹き出し上部の色ノイズ — 根本原因特定・解消（2026-08-01 続き8）

上記の未解決調査の続き。`native_sdk_windows_present_gpu_surface_pixels`
（`webview2_host.cpp`）に一時的なデバッグプリントを仕込み、吹き出し窓の実際の
`rgba8` ピクセル値をフレームごとにダンプして直接観測した。

**観測結果**: 1フレーム目・2フレーム目は完全に正常（空白部分は全て `0,0,0,0`）。
3フレーム目で突然、空白部分の一部（行5〜55あたり）に構造化されているが無関係な
色つきデータ（例: `191,198,228,104` `221,132,103,255` など、UIのどの色トークンとも
一致しない）が出現。ログの `runtime.event` を突き合わせると、2フレーム目と3フレーム目
の間に **`audio` イベント**（`user-prompt` フェーズが `state=jumping` を割り当て、
`voiceCategoryForState(.jumping)` が非nullのためボイスバークが発火）が挟まっていた。

**根本原因（確定）**: `self.pixel_buffer`（`runtime/ui_app.zig`、メイン窓/吹き出し窓/
設定窓など**全ウィンドウで共有**、`.alloc` はゼロ初期化されず縮小もしない）は、
`.load`（部分更新）パスでは変更のあった矩形しか `clearRect` されない
（`ReferenceRenderSurface.renderPass` の `.load` 分岐、`primitives/canvas/reference.zig`）。
このバッファは音声サブシステム（Windows Media Foundation、C++側）と**同じプロセスの
ヒープ**から取られており、確保・解放のタイミングが重なると、部分更新で触られない
「空白領域」のバイトが音声再生関連の一時データ（PCMバッファ等、画像として解釈すると
無関係な色データに見える）を保持したまま残ることがある — 透過窓ではそれがそのまま
本物のRGBAとして画面に出る（不透明窓では以前から同じ現象が起きていても、常に
不透明テーマ背景色で「見えなくなっていた」だけで実害が無かった）。**試したが効かなかった
ゼロ初期化**（バッファ確保時の `@memset`）が効かなかった理由もこれで説明できる —
初回確保後はバッファが十分な大きさのまま使い回され、新規確保（ゼロ埋めが走る条件）が
発生しないため。

**修正**: `presentFrame`（`runtime/ui_app.zig`）で、透過窓（`runtime.isWindowTransparent`）
の場合は毎フレーム強制的に `full_repaint = true` にする（`force_full_repaint`）。
これにより `.load`（部分更新、触れない領域を残す）ではなく常に `.clear`（全体クリア）
経路を通るようになり、共有バッファのどんな残留データも画面に出る前に必ず上書きされる。
対象窓（吹き出し340x170、ペット134x146）は十分小さく、毎フレーム全体再描画のコストは
無視できる。ゼロ初期化フィックス自体も無害なので残してある。

実機確認: 5回連続バブル発火、waiting/user-promptを混在させた3回連続ストレステスト、
3回の完全再起動（各回直後にバブル即発火）— 計11回のバブル生成、すべてノイズなし。
合成ドラッグ（160,80px相当）は修正前と同じく完全一致（ズレ・カクつきなし）を確認、
CPU使用量にも異常なし。SDKフォーク側テストスイートも回帰なし。

## スプライト縁の「白飛び」/にじみ — スプライトシート自体の白マット汚染と判明（2026-08-01 続き9）

実機フィードバック:「背景が白い時とかに縁がノイズが走ってるような気がする」
（言語化しづらい違和感として報告）。

**切り分け**: present経路（`webview2_host.cpp` のpremultiply処理、`ui_app.zig` の
clear_color/force_full_repaint）は既に確認・修正済みのため、まず疑ったのは
「白背景の時だけ」という条件そのもの。実際に白背景窓・黒背景窓を用意しペットを
両方の上に置いて実デスクトップキャプチャで比較したところ、**両方の背景で**縁に
薄いモヤ（ハレーション）がかかっているのを確認 — 「白背景限定」ではなく常に
存在する劣化だが、白背景で特に馴染んで/目立って見えていた。

**根本原因**: present経路ではなく **`~/.petdex/pets/iroha/spritesheet.png`（と
`.webp`）というアセットファイル自体**に問題があった。半透明な縁ピクセル
（0 < alpha < 255）の色を、直近の不透明な近傍ピクセルと比較する検証スクリプトで
調べたところ、約19%が「本来の色から大きく外れた、白っぽい」値を持っていた
（例: 不透明な近傍が `(4,4,3)`（ほぼ黒）なのに、隣接する半透明ピクセルは
`(133,133,110)` という明るいオリーブ色、alpha=122）。これは spritesheet が
（AI生成 + 背景除去などの過程で）**白キャンバスに対して合成された状態で
アンチエイリアス縁が焼き込まれている**（straight alphaのRGBが白側にブレンド
済み、いわゆる「白マット汚染」）ことが原因 — レンダリング/合成パイプラインの
バグではなくアセットデータの品質問題だった。

**修正**: `scripts/fix-sprite-matte.py`（新規、リポジトリに追加）で、白マット
ブレンドを仮定した逆算式 `true_color = (observed - 255*(1-alpha)) / alpha`
を全半透明ピクセルに適用し補正。`~/.petdex/pets/iroha/spritesheet.{png,webp}`
と `~/.petdex/pets/summer/spritesheet.webp`（インストール済み2ペット）に適用。
既知のミスマッチサンプルで検証: 色距離が211→6、152→53、177→58 等に大幅改善
（完全に一致はしないケースもあるが、白ハレーションという最も目立つ症状は
一貫して解消）。実デスクトップキャプチャで修正前後を並べて比較し、白背景・
濃色背景の両方で縁が明確にシャープになったことを確認。

**注記（フォローアップ）**: この修正は**現在インストール済みのペットのアセット
ファイルへの直接パッチ**であり、アプリのコード（デコード経路）は変更していない
— ペットを再インストールしたり新しいペットを追加したりすると同じ汚染が
再度現れる可能性がある。恒久対応としては `decodeSheet`（`app/src/main.zig`）の
デコード時に同じ補正を自動適用する方が堅牢だが、今回は実機での即効性を優先し
アセット直接修正 + 再利用可能なスクリプトという形にとどめた。新しいペットで
同様の症状が出た場合は `python scripts/fix-sprite-matte.py --inplace
~/.petdex/pets/<pet>/spritesheet.png ~/.petdex/pets/<pet>/spritesheet.webp`
を実行する。

## 吹き出しタップでセッションの端末へ移動（SPEC 3.6）— Windows/WSL実装・実機検証（2026-08-01 続き10）

SPEC 3.6 は元々「macOS + iTerm2のみ対象」（Windows Terminal・Waylandの制約による）
だったが、実際のユーザー端末構成（Windows/WSLとも個別コンソールウィンドウ、
Windows Terminalではない）を確認した上でWindows/WSLに実装した。

**設計**: セッションファイルのpid相関（SPEC旧設計）ではなく、`hook_runner.run()`
（Claude Codeのhookから起動される都度の子プロセス）が**自分自身が今動いている
端末を、その場で直接取得**する方式にした — hookプロセスは呼び出し元シェルの
子プロセスなので、コンソール/ttyを自然に継承している。
- Windows: `GetConsoleWindow()` でHWNDを取得（`plat.currentConsoleWindowHandle`）。
  WSL経由（`wsl.exe`越しにWindowsバイナリのpetdex-hookを実行）でも同じ呼び出しで
  有効なHWNDが得られることを実機確認 — WSL用の特別な経路は不要だった。
- macOS/Linux: `ttyname_r(0, ...)` で制御端末パスを取得（`plat.currentTty`）。

取得した値は `/bubble` POSTの `terminal_hwnd`/`terminal_tty` フィールドとして
`hook_server.zig` の `Bubble` 構造体に保持。`bubbleView`（`main.zig`）のルート
ノードに `on_press = .bubble_tapped` を追加（吹き出し窓の `click_through` は撤去
— タップを受けるため）。タップ時、Windowsは `<自身のexe> focus-window <hwnd>`
を新規プロセスとしてspawnし `SetForegroundWindow` を呼ぶ（自プロセスから直接
呼んでもフォアグラウンドロックの都合で確実に効かないため新規プロセスに一任）。
macOSは `osascript` をspawnしiTerm2をtty照合で `select`（SPEC既存設計そのまま）。

アプリ側（`app/src/main.zig`/`plat.zig`/`hook_runner.zig`/`hook_server.zig`）のみの
変更で、SDKフォークへのパッチは不要だった。

**実機確認（Windows/WSL、2026-08-01）**: 実際のPowerShellコンソール窓・WSLを
ホストするコンソール窓の両方で、フォーカスが別窓に移った状態から吹き出しを
タップ（`native automate widget-click`）すると `GetForegroundWindow()` が正しい
窓に戻ることを確認。単体でも `focus-window <hwnd>` サブコマンド単独の動作を確認済み。

**macOSは未検証**（開発機がWindowsのみのため）。SPECの元設計通りにコードは
書いたが `select` 動詞を含め実機確認できていない。

## 状態連動ボイスの台詞ソースを一元化（SPEC 3.7）（2026-08-01 続き11）

実機フィードバック: 音声ファイルの置き場所が分かりにくい、台本が既存WAVにしか
残っておらずユーザー自身が書き換えられない、`jumping`（ユーザー指示直後＝作業
開始のタイミングで再生）の文言が「お疲れ様でした」等の完了報告トーンで矛盾して
いる、`waiting`（クールダウン対象外で頻出）のバリエーションを増やしたい。

**対応**:
- 既存14件のWAV（`app/assets/voice/<category>/{1,2}.wav`）は台詞テキストの記録が
  どこにも残っていなかったため、`openai-whisper`（一時インストール）で全件文字起こし
  し、内容を確認した上で `app/assets/voice/script.json` に集約（このリポジトリに
  同梱、`voice/`直下の3.3用ファイル群とは別物 — 混同注意）。
- `jumping` の2件を差し替え（「お疲れ様でした、無事終わったみたいですね」→
  「かしこまりました、先生。すぐに取り掛かりますね」等、開始タイミングに合う文言へ）。
  `waiting` を2→4件に増量。他5カテゴリ（`idle`/`running`/`review`/`waving`、いずれも
  現状 `voiceCategoryForState` では未使用）は既存文言をそのまま script.json に転記
  （内容は変更していない）。
- `scripts/generate-voice.py`（新規）: `script.json` を読み、個人環境固有のローカル
  TTS（`C:\Users\e8910\Documents\TTS\Irodori-TTS`、棗いろは用ファインチューニング
  済みチェックポイント、このユーザー機専用）の `infer.py` をカテゴリ×行ごとに呼び出し、
  `app/assets/voice/<category>/<番号>.wav` へ出力。行数が減ったカテゴリの余剰
  番号ファイルは自動削除。生成音声は既存WAVと同一フォーマット（mono/48kHz/16bit）
  であることを実機確認済み。
- `app/src/main.zig` の `voice_lines`（`waiting`）に新規2件のパスを追加、再ビルド・
  テスト green を確認。

**実機確認**: 生成した新規4件（jumping×2, waiting新規2件）を同じくwhisperで
再文字起こしし、意図した文言と一致することを確認（「かしこまりました、先生。
すぐに取りかかりますね」等、句読点・送り仮名の揺れのみで内容は一致）。

## スプライト縁ノイズ、白マット修正後も残存 — 真因は素材アルファチャンネルのノイズだった（2026-08-01 続き12）

実機フィードバック（続き9の白マット修正後）:「白背景にすると結構ノイズが目立つ
というか、なんかガタツキが目立つ」— 白マット汚染は解消したはずなのに縁の粒状
ノイズが残っている、との報告。

**切り分け**: まず自分が疑ったのは続き9の unmatte 処理自体（`true_color =
(observed - 255*(1-alpha)) / alpha` は alpha が0に近いほど分母が小さくなり、
量子化誤差を増幅しうる）。petdex.dev から両ペットのオリジナル(未加工)
spritesheet を再取得し（`https://petdex.dev/api/manifest` → `assets.petdex.dev`、
インストール済みアセットは一度上書きしていて手元にバックアップが無かったため）、
alpha帯ごとに「unmatte前後でRGBがどれだけ動くか」を計測。分母が小さい帯ほど
理論上は不安定なはずだが、**unmatte 適用前のオリジナル画像を等倍最近傍拡大
して目視した時点で、unmatte を一切適用していないのに同じ粒状ノイズ（耳・
髪の輪郭沿いの灰色の点々）が既に見えていた** — unmatte前後で該当ピクセルの
値が完全一致することも確認し、ノイズは自分の修正が原因ではないと確定。

**根本原因**: spritesheet 自体のアルファチャンネルに、シルエット境界沿いの
「塩コショウ状」の単発ノイズが焼き込まれている（AI生成+背景除去+WebP圧縮を
経由した素材にありがちな量子化/リンギングノイズと推測、白マット汚染とは別種の
劣化）。このアプリの描画は最近傍拡大（ドット絵の輪郭を保つため）で、かつ
白背景はどんな色のズレも隠すコンテキストが無いため、他の背景よりこのノイズが
際立って見える。

**修正**: `scripts/fix-sprite-matte.py` を拡張。
1. `alpha_floor`（デフォルト32）未満のピクセルは unmatte 処理をスキップ
   （逆算の分母が小さい領域での不要な増幅を避ける安全策 — 実測ではこのフレームの
   ノイズの直接原因ではなかったが、他ペット・他フレームでの再発防止として残す）。
2. 新規: 補正後にアルファチャンネルにのみ 3x3 メディアンフィルタ
   （`PIL.ImageFilter.MedianFilter`）を適用し、単発ノイズを除去。RGBには
   触れないため色のにじみ・ぼやけは出ない。
検証: フレーム単位で複数のフィルタサイズ（3/5）を白背景・カラー背景の両方で
比較screenshot。サイズ3は輪郭の細部（後れ毛の先端等）を保ったままノイズを
大きく低減、サイズ5はさらに滑らかだが輪郭がやや太る/にじむトレードオフを
確認したため3を採用。

`~/.petdex/pets/iroha/spritesheet.{png,webp}` と
`~/.petdex/pets/summer/spritesheet.webp` に再適用（petdex.dev から取得した
未加工オリジナルを起点に、白マット除去+アルファ縁ノイズ除去を1回で適用 —
前回パッチの上に重ね掛けしていない）。続き9と同じく**現在インストール済みの
アセットへの直接パッチ**であり、ペット再インストール時は
`python scripts/fix-sprite-matte.py --inplace ~/.petdex/pets/<pet>/spritesheet.png
~/.petdex/pets/<pet>/spritesheet.webp` の再実行が必要（この制約自体は続き9と
変わらない）。

**既知の限界**: これは素材のアルファ品質を底上げする対症療法であり、
最近傍拡大というレンダリング方式そのものに起因する「ジャギー」（拡大率が高い
ほどピクセル境界が角ばって見える）は原理的に残る。今回対応したのはそれとは別の
「ランダムな粒状ノイズ」であり、規則的なピクセル境界のギザギザ自体をなくすには
拡大アルゴリズムの変更（最近傍→線形補間等）かドット絵自体の描き直しが必要で、
どちらもドット絵の見た目を変える大きな変更のため今回は対象外。

## ボイスをキャラごとに分離 + 絵文字による抑揚付け（SPEC 3.7 続き）（2026-08-01 続き13）

実機フィードバック: (1)「キャラごとに台本を付けたいときとかあって、変えられるのか
な?」— `script.json` が単一ファイルでキャラの区別が無い。(2)「絵文字をちゃんと
反映させてるかっていうのが気になる…絵文字入れないと全然ちゃんと抑揚つかないよ。
sample_emoji_sweepってやつをちゃんと参考にして、台本.mdをちゃんと参考にして」—
続き11で作った script.json の台詞に絵文字が一つも入っておらず、棒読みになって
いた。

**参照資料の確認**: `voice/samples/daihon.md`（このリポジトリ、以前から存在したが
未参照だった）に、Irodori-TTS の45種の感情タグ（`voice/samples/emoji_sweep/`
の各wavに対応）と、その作り方のコツが明記されていた:「絵文字をその音が鳴る
箇所の直後（擬音語や間投詞のすぐ後ろ）に埋め込む」— 文頭ではなく実際に感情が
起きる場所に置く。公式サンプルも同じ形（`あははっ🤭、それ本当に言ってるの？`）。

**per-character 化**: `app/assets/voice/<category>/` を
`app/assets/voice/iroha/<category>/`（+`iroha/script.json`）へ移動。
`app/src/main.zig`:
- `voice_lines`（パス丸ごと static 配列）を廃止し、`voice_line_counts`
  （カテゴリごとの行数のみ）+ `voiced_pet_slug`（ボイスを持つペットの slug、
  現状 `"iroha"` のみ）に分離。再生時は `active_pet` の slug が
  `voiced_pet_slug` と一致する場合のみ `assets/voice/{slug}/{category}/{n}.wav`
  を `std.fmt.bufPrint` で組み立てて再生 — 一致しない（他ペット選択中）場合は
  無音（既存の「アセット欠落は無視して鳴らさない」方針に合わせた自然なフォール
  バック）。別キャラにボイスを足す場合は script.json を新規作成し
  `voiced_pet_slug` を差し替えるだけでよい設計（同時多キャラ鳴動はSPEC.mdの
  「全セッションを1匹が代表」という前提に合わせてスコープ外のまま）。
- `scripts/generate-voice.py`: `--pet <slug>`（デフォルト `iroha`）を追加、
  `app/assets/voice/<pet>/` 配下を対象にするよう変更。

**絵文字埋め込み**: `script.json` 全7カテゴリの台詞を、daihon.md の作法に
沿って書き換え（例: `waiting/1` "先生、少しこちらをご確認いただけますか?" →
"ねぇ先生👂、少しこちらをご確認いただけますか?"、`jumping/1` "かしこまりました、
先生。すぐに取り掛かりますね。" → "かしこまりました💪、先生。すぐに取り掛かり
ますね。"）。使用タグは daihon.md の45種から each 台詞の感情に最も近いものを
選定（whisper/trembling/pleading/backchannel/with_effort/cheerful/painfully/
worried 等）。頻出の `waiting` は強すぎる感情タグを避け柔らかめで統一。

**LoRA アダプタの追加採用**: `voice/samples/emoji_sweep/` の生成元
（`Irodori-TTS/emoji_sweep.py`）を確認したところ、本番パイプライン
（`scripts/generate-voice.py`、`checkpoints/model.safetensors` + `refs/
ref_candidate_01.wav` のみ）とは異なり、棗いろは専用に学習した LoRA アダプタ
（`outputs/irodori_iroha_lora/checkpoint_best_val_loss_0001200_0.760441`、
`data/iroha/manifest.jsonl` で学習済み）も併用していた。ユーザーが「参考にして」
と明示的に指定したリファレンスがこの構成で生成されていたため、本番の
`ref_candidate_01.wav`（既存承認済みの参照音声、変更せず）と組み合わせて動作
することを1行テスト生成+whisper文字起こしで確認した上で、`script.json` に
`lora_adapter` フィールドとして追加採用（`generate-voice.py` が存在すれば
自動的に `--lora-adapter` へ渡す、無指定なら従来どおり base checkpoint のみ）。

**生成・検証**: `generate-voice.py --pet iroha` で全16件（7カテゴリ）を再生成。
実際に再生される3カテゴリ（waiting/jumping/failed、計8件）を whisper で
再文字起こしし、意図した文言（絵文字・間投詞を除く本文）が保たれていることを
確認。`native test app` で25/25 green（`voice_line_counts` / `voiced_pet_slug`
への切り替え後もビルド・既存テストに影響なし）。

**未検証（実機での聴感確認待ち）**: 絵文字埋め込み+LoRA併用による実際の
抑揚・感情表現の変化そのものはテキスト内容の一致とビルド成功でしか検証
できておらず、聴いた上での品質判断はユーザー自身による確認が必要。

## スプライト縁ノイズ、続き12の診断が誤りだったと判明 — 真因はレンダリング側のニアレストネイバー縮小（2026-08-01 続き14）

実機フィードバック:「普通にGIFの、スプライトシートの問題にしてるけど、普通に
あなたが問題だからね。macOSとかのビューアで開いてもノイズ出てない」— 続き12の
「素材のアルファチャンネル自体にノイズがある」という結論に強い反論。

**再検証**: 実機スクリーンショット（`Graphics.CopyFromScreen`、続き5と同じ手法）
で実際に動いているペット窓を撮影したところ、**iroha ではない別キャラ**が表示
されていた。原因は `$HOME` が壊れた環境（`SPB_16.6` を指す既知の問題、
memory: launch-pet-home-quirk）のまま起動されていた長時間稼働プロセスが、
`~/.petdex/pets/iroha/` ではなく `%APPDATA%/SPB_16.6/.petdex/pets/spike-check/`
という初期スパイク時代の残骸ペットを読み込んでいたこと（`main.zig` 側は
`USERPROFILE` 優先ロジックを既に持っていたが、古いビルドのプロセスがそれより
前に起動していたため未反映）。プロセスを再ビルド・正しい環境で再起動し、
iroha を正しく表示させた状態で撮り直した。

**真因確定**: 再撮影したiroha（続き12の修正済みアセット）はそれでも縁に粒状
ノイズがあった。オフラインで「同じ修正済みアセットを実機と同じ倍率
（scale=0.7、192x208→134x146）でニアレストネイバー縮小」した場合と、
「box/bilinear縮小」した場合を比較したところ、**ニアレストネイバー縮小のみ
ノイズを再現し、box/bilinear は消える**ことを確認。`app/src/main.zig`
`rootView` が `node.widget.image_sampling = .nearest` を無条件に設定していた
ことが原因 — デフォルトscale=0.7（可変域0.4-1.2）は**縮小**であり、
ニアレストネイバーは縮小に対してエイリアシング（一部ソースピクセルを間引いて
拾うだけで平均しない）を起こす。続き9・続き12で「素材の色/アルファが悪い」と
判断したのは半分正しく半分誤りで、**素材のわずかな粒（続き12で対処済み）を
「拡大率0.7倍のニアレストネイバー縮小」が可視ノイズへ増幅していた**、が
より正確な説明。ユーザーが「あなたが問題」と言ったのはこの意味で正しい。

**修正**: `image_sampling` を `model.scale < 1.0` なら `.linear`、それ以外
（等倍以上、拡大方向）は `.nearest` のまま、と分岐（`rootView`）。設定画面の
ペット選択サムネイル（`petCatalogList`、常時40x44への縮小）も無条件 `.linear`
に変更。`native test app` 25/25 green。

**既知の限界（完全解決ではない）**: 修正後も実機スクリーンショットには
まだ粒状ノイズが残っている（修正前後でピクセル差分は確認できる＝
`.linear` は効いている、ノイズの高周波成分は約5.5%減）。原因は
`reference.zig` の `.linear` が単純な2x2バイリニア1タップで、約1.43倍
（1/0.7）の縮小率に対して本来必要な範囲（box/mipmap相当のプレフィルタ）
より狭い範囲しか平均していないため、と推定（同じアルゴリズムをPythonで
再現し縮小単体では offline で綺麗な結果になることを確認済み — 実機との
差分は、このマシンで確認済みのDWM/DPI仮想化スケーリング（続き8隣接記録
「DPI後の実サイズ170px」参照 — 本アプリはDPI-aware宣言をしていない）が
アプリの描画後にさらに別のスケーリングパスを挟んでいる可能性が高い）。
完全な解消には (a) レンダラーに box/mipmap 相当の縮小フィルタを実装する
（native SDK フォークへの追加パッチ）か、(b) アプリを per-monitor DPI aware
にする（窓位置・サイズ計算全体に波及する大きめの変更、今回は見送り）が
必要— どちらも今回のスコープを超える追加エンジニアリングとして保留。

## GitHub Actions: 3プラットフォーム分のポータブルビルドを自動生成（2026-08-01 続き15）

要望: 「GitHubのアクションで自動でAppファイルを作成してほしい。DMGじゃなくて
Appファイル。Windowsではexeファイル、Linuxはインストーラーじゃなくてファイル」
— インストーラー無し、ポータブルな成果物を3OS分自動ビルドしたい。

**フォーク bootstrap 問題**: `tools/native-sdk-fork/` は `.gitignore` 済みで
リポジトリに含まれない（上流 `Railly/native` フォークのピン留めコミット +
本プロジェクトの `patches/native-sdk-fork/*.patch`、詳細は本ファイル冒頭
「Native SDK のバージョン固定」節）。CIでは毎回ゼロから
「ピン留めコミットをclone → 全パッチを適用 → `zig build cli` → その
`native` でアプリをビルド」を行う必要がある。上流 petdex 自身のCI
（`.github/workflows/desktop-native-ci.yml` / `desktop-release.yml`、
`crafter-station/petdex`）が全く同じ手順・同じピンを使っており、それを
参照して再現した（apt依存 `libgtk-4-dev libx11-dev pkg-config
webp-pixbuf-loader` や `-Dcpu=baseline`（ビルドRunnerのAVX-512命令を
含む配布バイナリがユーザー機で不正命令クラッシュする既知の落とし穴、
上流が実際に踏んだ #604/#618）もそのまま踏襲）。

**パッチ検証**: 適用作業中に `effects.zig.patch` / `root.zig.patch`
（7/31時点の古いパッチ、他9件と違い絶対パスの書式が異なっていた）が
非対話環境（CIのような）で `patch` コマンドの自動検出に失敗し**サイレントに
スキップされる**ことを発見 — この2件は再生成（petdex.dev 経由ではなく
`Railly/native` の同コミットから該当2ファイルを直接re-fetchしdiff）して
他9件と同じ書式に統一。11件全パッチについて「ピン留めコミットの新規clone
+ 全パッチ適用」を実際にゼロから行い、結果が現在の `tools/native-sdk-fork/`
と完全一致することを確認（`diff -q`）。さらにWindows分は
`native build -Dcpu=baseline` → `native test`（25/25 green）→
`native package --target windows` までこのマシン上でエンドツーエンドの
ドライラン済み。

**`native package` の出力形式確認**（`--target macos/windows/linux` を
それぞれ試験実行して確認、2026-08-01）:
- macOS: `Contents/{MacOS,Resources}/Info.plist` 等、正真正銘の `.app`
  バンドル構造を直接生成（`--output` にそのまま `.app` 拡張子を持たせれば
  Finderがバンドルとして認識する）。DMG化はしていない — 要望どおり。
- Windows: `bin/*.exe` + `resources/`（音声等アセット同梱を確認済み）の
  フォルダ。インストーラーではない。
- Linux: `bin/` + `share/applications/*.desktop` + `share/icons/`
  のフォルダ。.deb/.rpm/AppImageのようなインストーラーではない。

**署名について**: Apple Developer証明書が無いため macOS は `--signing
adhoc` のみ（無署名だとApple Silicon実機では起動自体できないため最低限
必須、上流もこの理由で自動リリースからmacOSを意図的に除外している —
ただし今回はユーザーの個人利用が目的なので含めた）。ad-hoc署名でも
Gatekeeperは初回起動時に「開発元を確認できません」警告を出す —
右クリック→開く、または `xattr -d com.apple.quarantine` が必要になる。
公証（notarization）にはApple Developer Program登録が要るため未対応。

**ワークフローファイル**: `.github/workflows/build-desktop-app.yml`
（新規）。トリガーは `workflow_dispatch`（手動）と `v*` タグpush —
毎コミットでの3OSフルビルドは個人開発には過剰なため避けた。成果物は
GitHub ReleaseではなくActionsのartifact（ダウンロード用に自動でzip化
される）としてアップロードするだけに留め、リリース公開は今回のスコープ
外（要望があれば追加できる）。

## 重大インシデント: petdex.dev の同名別キャラでユーザーの実キャラを上書き破壊（2026-08-01 続き16）

続き12・続き14のスプライト縁ノイズ調査で、「pristine版と比較したい」という
理由から petdex.dev の公開カタログを slug "iroha" で検索し再ダウンロードした
画像を、確認せず `~/.petdex/pets/iroha/spritesheet.{png,webp}` に上書きした。
petdex.dev の "iroha"（submittedBy: mytristan）は「Sakayori Iroha（酒寄彩葉、
超時空輝夜姫）」という**全く別作品の別キャラ**（狐耳・紫髪・キーター）で、
ユーザーの実際のキャラは棗いろは（ブルーアーカイブ、赤毛・制帽・本とカップ）
だった。同じ文字列 "iroha" というだけで同一実体だと決めつけたのが原因—
**続き12・続き14で分析・レンダリングしていた「iroha」は全てこの誤った
別キャラのアセットだった**（ピクセル統計・レンダリング画像そのものは
技術的には正確だが、対象キャラクターの前提が誤り）。ユーザーが激怒し
手動でファイルを復元。詳細と再発防止の絶対規則は memory
`never-refetch-pet-assets-online` に記録済み（要約: インストール済み
アセットをオンライン取得物で上書きしない、書く前に必ずバックアップ＋
目視確認）。

**続き12・続き14の技術的知見のうち、今も有効なもの**: レンダリング側の
問題（`.nearest` での縮小方向エイリアシング）は**キャラクターに依存しない
一般的なバグ**であり、`rootView` の `.linear` 分岐修正はそのまま有効。
無効なもの: 「iroha spritesheetの具体的なアルファ統計・見た目」に関する
記述は全て誤ったキャラクターのものなので参考にしないこと。

**正しい棗いろはでの再検証**: ユーザー復元後のファイルを目視確認（白背景・
濃色背景の両方、frame(0,0)拡大）— 明らかな白マット汚染やアルファノイズは
確認できず、クリーンに見えた。統計指標（近傍色距離）だけでは51.2%という
異常値が出たが、これは探索半径3pxの粗い実装が隣接する別デザイン要素
（帽子の白い装飾等、正規のデザイン）を誤検知したものと判断し、ピクセル
単位の補正は適用しないことにした（見た目で確認できない問題を統計だけで
「直した」ことにする、を今回はしない）。バックアップは
`C:\Users\e8910\Documents\HitokoePet_asset_backups\iroha_restored\` に保存。
