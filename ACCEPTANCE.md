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

## C. 音声通知（SPEC 3.3）

純粋関数 `shouldSpeak(hook_event: []const u8) -> bool` に切り出すこと。

| # | 基準 | 判定 |
| --- | --- | --- |
| C1 | `"Stop"` に対して `true` を返す | Zig unit test |
| C2 | `"SubagentStop"` に対して `false` を返す | Zig unit test |
| C3 | `"PreToolUse"`, `"PostToolUse"`, `"Notification"`, `"SessionStart"`, `"PreCompact"`, `"UserPromptSubmit"` すべてに対して `false` を返す | Zig unit test |
| C4 | 未知のイベント名に対して `false` を返す（フェイルクローズ） | Zig unit test |
| C5 | 音声が無効設定のとき、`Stop` でも音声を再生せず、ペットの状態遷移は従来通り行われる | Zig unit test |
| C6 | 音声の生成方式が確定していること（`state/AUDIO.md` に決定と根拠が記録されている） | ファイル存在＋内容レビュー |

## D. 口パク（SPEC 3.4）

**着手前ゲート**: `mouth.png` を1体分人手で試作し、192×208 セルで開閉が視認できることを
確認する。視認できない場合、本セクション全体をスコープから削除する。

純粋関数 `mouthFrame(rms: f32) -> u8` に切り出すこと。

| # | 基準 | 判定 |
| --- | --- | --- |
| D1 | `mouth.png` を持たないペットを読み込んだとき、エラーにならず口パク無しで描画される | 統合テスト |
| D2 | `mouth.png` を持たないペットの描画結果が、本機能導入前と同一である | スクリーンショット比較 |
| D3 | 無改変の Codex アトラス（8列×9行、1536×1872）が従来通り読める | 統合テスト（既存 fixture） |
| D4 | `rms` が単調増加するとき `mouthFrame` の返り値が単調非減少である | Zig unit test（プロパティ） |
| D5 | `rms == 0` で閉口フレーム（`0`）を返す | Zig unit test |
| D6 | 返り値が常に `0..口形数-1` の範囲に収まる（`rms` に `NaN`, `inf`, 負値を与えても） | Zig unit test |
| D7 | 発話終了後、口が閉口フレームに戻る | Zig unit test |

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
```
