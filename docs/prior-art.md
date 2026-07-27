# 先行実装の調査 (2026-07-28)

intake 段階で実施。**Web検索の要約ではなく、実リポジトリを clone して読み、
実機で計測した結果**。再取得コストが高いのでここに残す。

`pipeline.yaml` の survey は `state/BASE.md` を想定しているが、`state/` は `.gitignore`
済みで git に残らないため、本ファイルに置いている。

## 1. Codex pet アトラス規格

本プロジェクトが互換を維持する対象。出典: [openai/skills hatch-pet](https://github.com/openai/skills/blob/main/skills/.curated/hatch-pet/SKILL.md)、
および clawdex が同梱する `skill/hatch-pet/`（`validate_atlas.py` 付き）。

- 配置: `~/.codex/pets/<pet-id>/` に `pet.json` + `spritesheet.webp` の2ファイル
- シート: 8列 × 9行、セル 192×208px、全体 1536×1872px、透過 PNG/WebP
- 行 = 状態、列 = フレーム。各行の有効フレーム以降のセルは完全透明

| 行 | 状態 | 有効列数 | 意味 |
| --- | --- | --- | --- |
| 0 | idle | 6 | 中立。呼吸／まばたき |
| 1 | running-right | 8 | 右方向の移動 |
| 2 | running-left | 8 | 左方向の移動 |
| 3 | waving | 4 | 挨拶／注意喚起 |
| 4 | jumping | 5 | 予備動作→跳躍→頂点→着地 |
| 5 | failed | 8 | エラー／落胆 |
| 6 | waiting | 6 | 待機（idle の変種） |
| 7 | running | 6 | 汎用／正面向きの走行 |
| 8 | review | 6 | 集中／調査／思考 |

**9行に空きが無い。** 口レイヤーも talking 行も存在しないため、口パクは必ず独自拡張になる
（SPEC 3.4）。

## 2. 既存実装の比較

| | [clawdex](https://github.com/danielkempe/clawdex) | [claude-code-pet](https://github.com/zzp1221/claude-code-pet) | [petdex](https://github.com/crafter-station/petdex) |
| --- | --- | --- | --- |
| 実装 | Swift / AppKit (NSPanel) | Tauri v2 + React Canvas | Zig (Native SDK) + Tauri |
| 対応OS | macOS のみ | 実質 Windows のみ | macos/windows/linux 宣言 |
| 状態取得 | hooks → Unix socket | hooks → `state.json` をポーリング | hooks → アプリ内蔵サーバー |
| つまみ | あり（速度駆動） | なし | あり（速度駆動） |
| Codex互換 | あり | あり | ネイティブ |
| ライセンス | MIT | **LICENSE 無し = 流用不可** | MIT |
| 規模 | 296K / Swift 7ファイル | — | 本体780コミット |
| **複数セッション** | **なし** | **なし** | **なし** |

### 確認した空白

- **3実装とも `~/.claude/sessions/*.json` を使っていない**（全リポジトリを grep してヒット0）。
  全てフック経由の単一グローバル状態に書き込む＝最後の書き込み勝ち
- **3実装とも複数セッションを扱わない**。claude-code-pet は `sessionId` を状態の1フィールドとして
  持つが（`hook/claude-pet-hook.mjs:177`）、集約はしていない

### webview からの離脱

- petdex はクロスプラットフォーム版デスクトップを WebView から降ろした。
  `packages/petdex-desktop-native` の README: *"Petdex on Native SDK (vercel-labs/native):
  no WebView, no Node sidecar."*
- clawdex は macOS で Swift/AppKit の NSPanel 直描き
- WebView(Tauri) を使うのは Windows 専用実装のみ（claude-code-pet、petdex-desktop-windows）

3プロジェクトが独立にクロスプラットフォーム透過オーバーレイから webview を外している。
Tauri の [Linux Graphics Issues](https://v2.tauri.app/develop/debug/linux-graphics/) に
webkitgtk 系の既知問題が文書化されている。

## 3. clawdex の状態マッピング（設計の参考）

`clawdex/docs/state-mapping.md` より。Claude Code のフックイベントを9行に畳む規則。
MIT。本プロジェクトが集約規則を設計する際の出発点になる。

| イベント | 行 | モード |
| --- | --- | --- |
| `SessionStart` | 3 waving | transient |
| `UserPromptSubmit` | 8 review | sticky |
| `PreToolUse` (Bash/Edit/Write/MultiEdit/NotebookEdit) | 7 running | sticky |
| `PreToolUse` (Read/Grep/Glob/WebFetch/WebSearch) | 8 review | sticky |
| `PreToolUse` (その他) | 7 running | sticky |
| `PostToolUse` | — | release |
| `Notification` | 6 waiting | sticky |
| `Stop`, `SubagentStop` | 3 waving | transient |
| `PreCompact` | 8 review | sticky |

意図的にやっていないこと（そのまま採用に値する判断）:

- **PostToolUse の非ゼロ終了で `failed` を出さない。** Claude Code は反復の一部として日常的に
  コマンドを失敗させる（デバッグ中の `make test` 等）。毎回悲しい顔を出すのはノイズ
- **`jumping` を使わない。** 祝いに見えるが、`Stop` と区別できる「成功」フックが無い
- **`running-right`/`left` をフック層から直接指定しない**

## 4. Claude Code のセッション登録簿（実機確認）

`~/.claude/sessions/<pid>.json`。確認時点で8セッションが並走していた。

```json
{"pid":67322,"sessionId":"cb3b1e73-...","cwd":"/Users/.../PixelArtAvator",
 "startedAt":1785173592988,"procStart":"Mon Jul 27 17:33:12 2026",
 "version":"2.1.220","peerProtocol":1,"kind":"interactive","entrypoint":"cli",
 "name":"pixelartavator-87","nameSource":"derived",
 "status":"busy","updatedAt":1785173665045,"statusUpdatedAt":1785173665045}
```

`status` は `busy` / `idle` / `waiting`。`waiting` のときは `waitingFor`（例 `"input needed"`）を伴う。

**公開APIではない内部パス。** `peerProtocol: 1` というフィールドがあることから上流も互換性を
意識しているが、保証は無い。スキーマ検証と劣化動作が必須（ACCEPTANCE B7/B8）。

## 5. 実測値

### 5.1 Petdex のアイドル時 CPU（macOS、上流 v0.3.1、2026-07-28）

```
/Applications/Petdex.app/Contents/MacOS/petdex-desktop-native
経過 1分31秒 / CPU時間 20.65秒 / RSS 111MB  →  1コアの約22.7%を継続消費
```

原因は `app.zon` の `gpu_present_mode = "timer"` + `gpu_vsync = true`。ディスプレイの
リフレッシュレートで再描画し続ける一方、スプライトのフレーム更新は120〜280ms間隔
（`uniform(8, 120, 220)` 等）。1スプライトフレームあたり15〜30回、同じ絵を描き直している。

> Activity Monitor に出る `https://petdex.dev` の各プロセスは Safari の WebContent
> （XPC、PPID=1）でありPetdexとは無関係。混同しないこと。

### 5.2 つまみモーションが止まる原因（`app/src/main.zig:1438-1446`）

```zig
if (releaseVelocity(model)) |vel| {
    if (vel.x >= physics_min_vel)        setThrowState(model, .@"running-right", fx);
    else if (vel.x <= -physics_min_vel)  setThrowState(model, .@"running-left", fx);
    else if (@abs(vel.x) < 20 and @abs(vel.y) < 20) setThrowState(model, .idle, fx);
}
```

押下中の表示行をリリース速度から導出しており、3行目が「ゆっくり動かす／掴んだまま止める」で
明示的に `.idle` を設定する。clawdex も同じ設計（`PetWindow.swift`: *"Called by the drag
handler. Forces a running-direction row"*）。**2実装に共通する設計判断の誤り。**

## 6. Native SDK (vercel-labs/native)

| 項目 | 値 |
| --- | --- |
| 作成 | 2026-05-08（調査時点で2.5ヶ月前） |
| npm | `@native-sdk/cli` v0.6.1（pre-1.0） |
| 週間DL | 3,241 |
| Star | 6,991 |
| ライセンス | Apache-2.0 |

pre-1.0 で破壊的変更が入る前提。ただし**エージェント運用を前提に設計されている**:

- `native test` / `native check --strict` が機械判定ゲートになる
- 各アプリに自動化サーバーが埋め込まれ、アクセシビリティスナップショット取得・ウィジェット操作・
  ライブ状態のアサート・決定論的スクリーンショットが可能（`native automate`）
- `native automate record` / `replay` で状態フィンガープリントによるフレーム単位の再生検証
- SDK 自身がエージェント用スキルを同梱（`native skills list`）

**注意**: `native check` の a11y／型付きバインディング検査は `src/**.native` マークアップが対象。
`app/` にマークアップは0個なので空振りする（SPEC 5.2.1）。

## 7. 取り込んだパッケージの新しさ

`packages/petdex-desktop-native` の全履歴は7コミット:

```
26111c5 feat(desktop-native): rewrite slice 1 on Native SDK, real pet without WebView or Node (#576)
3dc5768 feat(desktop-native): slice 2, in-process hook server replaces the Node sidecar (#577)
2ba9f5b feat: native desktop app rewrite on native-sdk (#578)
f20c55e docs: finish removing the commands v1 dropped
b677002 feat(desktop): petdex:// deep links switch the active pet
aac4eb0 feat(desktop): install pets from a deep link, and stop truncating the catalog
6e205e5 chore(desktop): 0.3.1
```

petdex 本体は780コミットあるが、**取り込んだ土台は先方も書き上げたばかりの新規実装**であり、
枯れた実装ではない。
