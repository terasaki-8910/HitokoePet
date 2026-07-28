# ACCEPTANCE — CLAUDE CODE PET

全項目は pass/fail で機械判定できること。判定手段を各項目に明記する。
`<TBD>` は criteria 段階（spike 完了後）に確定させる値。それまで build を開始しない。

判定コマンドは `## 判定コマンド` にまとめる。

---

## A. つまみモーションの保持（SPEC 3.1）

対象コードは `app/src/main.zig` のドラッグ中状態選択。テストのため純粋関数
`dragState(vel: ?Velocity, primary_down: bool) -> ?State` に切り出すこと。

| # | 基準 | 判定 |
| --- | --- | --- |
| A1 | `primary_down == true` かつ速度 `(0, 0)` のとき、返り値が `.idle` **ではない** | Zig unit test |
| A2 | `primary_down == true` のとき、速度の値によらず**常に同一の状態**を返す（`vel` を `(0,0)`, `(5,0)`, `(-5,0)`, `(500,0)`, `(-500,0)`, `null` で検証） | Zig unit test |
| A3 | `primary_down == true` のとき `.running-left` を返さない（片方向のみ） | Zig unit test |
| A4 | `primary_down == false` のとき、リリース時の投擲物理が現状と同じ挙動を保つ（速度 < `physics_min_vel` で `throwing` に入らない） | Zig unit test |
| A5 | 投擲の減速完了後に `.waving` へ遷移する既存挙動が維持されている | Zig unit test |
| A6 | `app/src/main.zig` 内に `dragging` 分岐から速度を参照する条件式が残っていない | `rg` パターン検査（下記） |

## B. 複数セッションの集約（SPEC 3.2）

**着手前ゲート**: 8セッション並走時の上流実装の挙動を実測し、結果を `state/BASE.md` に
記録すること。集約が不要と判断した場合、本セクション全体をスコープから削除する
（その場合 SPEC 3.2 を OUT へ移す）。

純粋関数 `aggregate(sessions: []const Session) -> State` に切り出すこと。

| # | 基準 | 判定 |
| --- | --- | --- |
| B1 | セッション0件で `.idle` を返す | Zig unit test |
| B2 | 1件でも `status == "waiting"` があれば、他に `busy` が何件あっても `waiting` 系状態を返す | Zig unit test |
| B3 | `waiting` が無く `busy` が1件以上なら作業中状態を返す | Zig unit test |
| B4 | 全件 `idle` なら `.idle` を返す | Zig unit test |
| B5 | 同じ入力に対し常に同じ出力を返す（順序非依存 — 入力配列をシャッフルしても結果不変） | Zig unit test |
| B6 | 未知の `status` 文字列を含む要素があってもクラッシュせず、その要素を無視して集約する | Zig unit test |
| B7 | 必須キー（`status`, `cwd`, `name`）を欠くJSONを与えたとき、例外を投げずに本機能を無効化して `false` を返す（劣化動作） | Zig unit test |
| B8 | `~/.claude/sessions/` が存在しない環境で、アプリが起動し既存のフック経路で動作する | 統合テスト（fixture HOME） |

## C. 音声通知（SPEC 3.3、`voice/`）

`app/` とは別成果物。**シェルスクリプトなので判定も shell ベース**（Zig テストではない）。
`voice/test.sh` に置く。

### C-1. イベント選別

| # | 基準 | 判定 |
| --- | --- | --- |
| C1 | `hook_event_name == "Stop"` のペイロードで音声再生が発火する | `PLAY_AUDIO_CMD` をスタブに差し替えて呼び出し記録を検査 |
| C2 | `hook_event_name == "SubagentStop"` で発火しない | 同上 |
| C3 | `PreToolUse` / `PostToolUse` / `Notification` / `SessionStart` / `PreCompact` / `UserPromptSubmit` すべてで発火しない | 同上 |
| C4 | 未知のイベント名で発火しない（フェイルクローズ） | 同上 |
| C5 | **`.type` キーを持つ Codex 形式のペイロードを与えたとき、誤って動作せず、かつ「Claude Code のペイロードではない」と判別できる** | 同上（SPEC 3.3.1 の失敗モード回帰テスト） |
| C6 | ペイロードが不正なJSONでも exit 0 し、Claude Code 本体を止めない | 終了コード検査 |

### C-2. 環境互換

| # | 基準 | 判定 |
| --- | --- | --- |
| C7 | `play_audio` が `afplay` / `pw-play` / `paplay` / `ffplay` / `powershell.exe` / `aplay` の順に探索し、最初に見つかったものを使う | PATH を差し替えた6ケースで検査 |
| C8 | 再生コマンドが1つも見つからない環境で exit 0 し、何も出力しない（ヘッドレス機での想定動作） | PATH を空にして検査 |
| C9 | `shellcheck` が警告0で通る | `shellcheck voice/*.sh` |
| C10 | NixOS 用の `writeShellApplication` 定義の `runtimeInputs` が、スクリプトが実際に呼ぶ外部コマンドを網羅している | スクリプトから抽出したコマンド一覧と突き合わせ |

### C-3. 並列実行

| # | 基準 | 判定 |
| --- | --- | --- |
| C11 | 同時に10回起動しても再生が重ならない（`flock` による直列化） | 並列起動してスタブの呼び出し時刻の重なりを検査 |
| C12 | ロック取得待ちが一定時間を超えたら諦めて exit 0 する（フック起動を滞留させない） | タイムアウト検査 |

### C-4. フォールバック

| # | 基準 | 判定 |
| --- | --- | --- |
| C13 | L3（母艦TTS）が応答しないとき、L1 の generic WAV にフォールバックして再生する | 到達不能なURLを指定して検査 |
| C14 | L3 が応答しないときの追加待ち時間が上限（`--max-time`）を超えない | 実時間計測 |
| C15 | L2 キャッシュにヒットしたとき、ネットワークアクセスが発生しない | スタブで検査 |

## D. 口パク（SPEC 3.4）

**着手前ゲート**: `mouth.png` を1体分人手で試作し、192×208 セルで開閉が視認できることを
確認する。視認できない場合、本セクション全体をスコープから削除する。

純粋関数 `mouthFrame(rms: f32) -> u8` に切り出すこと。振幅は**事前計算したエンベロープ**
（`<name>.env`）から読む。再生中の音声を観測しない（SPEC 3.4）。

| # | 基準 | 判定 |
| --- | --- | --- |
| D1 | `mouth.png` を持たないペットを読み込んだとき、エラーにならず口パク無しで描画される | 統合テスト |
| D2 | `mouth.png` を持たないペットの描画結果が、本機能導入前と同一である | `native automate screenshot` の比較 |
| D3 | 無改変の Codex アトラス（8列×9行、1536×1872）が従来通り読める | 統合テスト（既存 fixture） |
| D4 | `rms` が単調増加するとき `mouthFrame` の返り値が単調非減少である | Zig unit test（プロパティ） |
| D5 | `rms == 0` で閉口フレーム（`0`）を返す | Zig unit test |
| D6 | 返り値が常に `0..口形数-1` の範囲に収まる（`rms` に `NaN`, `inf`, 負値を与えても） | Zig unit test |
| D7 | 発話終了後、口が閉口フレームに戻る | Zig unit test |
| D8 | 同じ `.env` を2回再生したとき、口形の系列が完全に一致する（決定論性） | Zig unit test |
| D9 | `.wav` に対応する `.env` が存在しないとき、口パク無しで音声だけ再生される | 統合テスト |
| D10 | `.env` の長さが `.wav` の再生長と不整合でも範囲外アクセスしない | Zig unit test（境界値） |
| D11 | `reduce_motion` が有効なとき、口パクのアニメーションが抑制される（design_brief 4項） | Zig unit test |
| D12 | すべての `voice/` 同梱WAVに対応する `.env` が存在し、内容が現在のWAVから再生成したものと一致する | 生成スクリプトの再実行と diff |

## H. 吹き出しタップでセッションの端末へ移動（SPEC 3.6）

純粋関数 `focusTarget(sessions: []const Session) -> ?Pid` に切り出すこと
（B の `aggregate` と同一の優先度規則を使う）。

| # | 基準 | 判定 |
| --- | --- | --- |
| H1 | `focusTarget` が返す pid が、`aggregate` が状態を採用したセッションの pid と常に一致する | Zig unit test（B と同じ入力集合で照合） |
| H2 | セッション0件のとき `null` を返し、タップしても何も起きない | Zig unit test |
| H3 | 吹き出しタップで Effects チャネルに端末フォーカスの spawn 要求が1回だけ出る | fake executor で spawn を検査 |
| H4 | ペット本体（吹き出しではない）のタップでは spawn が発生しない | fake executor で検査 |
| H5 | 右クリックのコンテキストメニュー（上流の既存機能）がタップ追加後も従来通り開く | 統合テスト |
| H6 | 対象 pid が既に終了している場合、spawn せずに何も起きない | Zig unit test |
| H7 | 対応していない端末エミュレータ環境で、エラーを出さず何も起きない | 統合テスト（spawn を失敗させる） |
| H8 | pid → tty の解決が、tty を持たない pid（デーモン等）に対して `null` を返す | Zig unit test |

## S. spike（他のすべてに先行する。ここが落ちたら土台の選択自体が無効）

SPEC 5.1 参照。`app/` に SDK バージョンの固定が無く、`transparent` / `floating` が
現行SDKのマニフェストスキーマに存在しないため、まずここを確認する。

| # | 基準 | 判定 |
| --- | --- | --- |
| S1 | `native build app` が現行の `@native-sdk/cli` で成功する | 終了コード |
| S2 | 起動したウィンドウが実際に透過している（背景が抜けている） | `native automate screenshot` のアルファ検査 |
| S3 | ウィンドウが最前面に留まる | `native automate snapshot` |
| S4 | S1-S3 が通らない場合、通るSDKバージョンを特定し `app/` に固定する手段が存在する | バージョン固定後に S1-S3 を再実行 |
| S5 | アイドル時CPUの原因が特定され、`docs/prior-art.md` に記録されている | ファイル内容レビュー |

**S1-S3 が通るまで、E1/E2 の目標値は設定しない。**

## E. アイドル時 CPU（SPEC 3.5）

**ベースライン実測値**（上流 v0.3.1、macOS、2026-07-28）: 91秒で CPU時間 20.65秒 = **22.7%**

| # | 基準 | 判定 |
| --- | --- | --- |
| E1 | ペット表示・無操作・セッション無しの状態で60秒間放置したとき、CPU時間の増分が `<TBD>` 秒未満 | 計測スクリプト |
| E2 | 同条件で RSS が `<TBD>` MB 未満 | 計測スクリプト |
| E3 | ベースライン（22.7%）比で CPU が減少していること | 計測スクリプト |

> `<TBD>` は spike で present-on-demand が実際に効くと確認した後、criteria 段階で確定する。
> 現時点で数値を約束しない。E3 のみ spike 前でも成立する基準。

## F. 上流との関係（SPEC 5.3）

| # | 基準 | 判定 |
| --- | --- | --- |
| F1 | `app/LICENSE` が存在し、上流の著作権表示が改変されていない | `diff` |
| F2 | `app/PROVENANCE.md` の改変一覧が空でなく、`app/` への各変更が記載されている | `git diff --stat app/` と突き合わせ |
| F3 | `app/` 配下の既存 Zig テスト18個がすべて通る | テストコマンド |

## G. 全体の品質ゲート（CLAUDE.md 由来）

| # | 基準 | 判定 |
| --- | --- | --- |
| G1 | 本プロジェクトが追加したソース・UI文字列に絵文字が含まれない | lint（no-emoji） |
| G2 | 本プロジェクトが追加したコードに色リテラルが直書きされていない。色は `petdexTokens()`（`app/src/main.zig:209`）経由のみ | lint（design-tokens-only） |
| G3 | `app/app.zon` の全 view 宣言に `accessibility_label` が設定されている（既存の `"Petdex pet"` に倣う） | `app.zon` の構造検査（下記） |
| G4 | `main.zig` に本プロジェクトが追加した純粋関数（A/B/C/D で切り出したもの）それぞれに1つ以上のテストが存在する | テスト一覧の突き合わせ |

---

## 判定コマンド

Native SDK 公式ドキュメントで確認済み（`vercel-labs/native` の `docs/src/app/cli/page.mdx`、
`docs/src/app/testing/page.mdx`）。**SDK 未インストールのため実行はまだしていない。**
criteria 段階の最初の作業として、これらが実際に通ることを確認する。

```sh
# テスト: アプリのテストスイートを実行し、最後に `native test: passed` を出す。
# 同時に native check が読むモデル契約成果物を更新する。
native test app

# check: ビルドせずにツリー全体を検証。--strict は警告を失敗に昇格させる。
native check app --strict

# 環境診断（criteria 段階の最初に1回）
native doctor
```

### `native check` の a11y 検査はこのアプリでは空振りする

`native check` のアクセシビリティ検査は `src/**.native` マークアップファイルが対象。
**`app/` にマークアップは0個**（Zig 6ファイル + `app.zon` のみ、gpu_surface 直描画）。
したがって G3 は `native check` では判定できず、独自検査が必要。

```sh
# G3: app.zon の全 view 宣言に accessibility_label があること
#     （view 宣言数と accessibility_label 出現数が一致すること）
test "$(rg -c 'kind = "gpu_surface"|kind = "webview"' app/app.zon)" \
   = "$(rg -c 'accessibility_label' app/app.zon)"

# G1: 本プロジェクトが追加した行に絵文字が無いこと
git diff 6e205e5..HEAD -- app/ | rg '^\+' | rg -P '[\x{1F300}-\x{1FAFF}\x{2600}-\x{27BF}]'
# ヒット0であること

# G2: 追加した行に色リテラルが無いこと（色は petdexTokens() 経由のみ）
git diff 6e205e5..HEAD -- app/src/ | rg '^\+' | rg -i '0x[0-9a-f]{6,8}|#[0-9a-f]{6}'
# ヒット0であること（petdexTokens() 内の定義を除く）

# A6: dragging 分岐から速度参照が消えていること
rg -n -A6 'if \(model\.dragging\)' app/src/main.zig | rg 'vel|velocity'
# ヒット0であること

# F1: 上流の著作権表示が改変されていないこと
git diff 6e205e5..HEAD -- app/LICENSE   # 出力が空であること

# F3: 上流の既存 Zig テスト18個が通ること（native test の出力に含まれる）
native test app

# E1-E3: アイドル時 CPU 計測（macOS）
scripts/measure-idle.sh   # criteria 段階で作成

# C: 音声フックの検査（voice/ は shell 成果物なので Zig テストではない）
voice/test.sh             # criteria 段階で作成
shellcheck voice/*.sh     # C9

# D2: 口パク導入前後の描画一致（mouth.png 無しのペット）
native automate screenshot pet-canvas
```
