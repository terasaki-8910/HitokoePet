# PLAN — HitokoePet

Stage 3（plan）の成果物。SPEC.md / ACCEPTANCE.md をフィーチャ単位に分解し、依存と
ビルド順（wave）を定める。**実装はしない。** 次に組める wave は
[state/features.txt](state/features.txt)、各フィーチャの単独ゲートは `state/gates/<feature>`。

## 現状（main に何が入っているか）

- `app/src/main.zig` … 上流 petdex の描画・入力ループ。`State` enum（`main.zig:60`）は既存。
  **本プロジェクトの純粋関数（dragState / aggregate / mouthFrame / focusTarget ほか）と
  共有型（Velocity / Pid / Status / Session）はまだ無い。**
- `app/src/hitokoe_test.zig` … criteria 段の RED（A/B/D/H の純粋関数ユニット）。集約子
  `test { _ = @import("hitokoe_test.zig"); }` は `main.zig:2139` に配線済み。したがって
  現在 `native test app` はコンパイル不能＝意図した赤。
- `voice/test.sh` … C（音声フック）の RED。被テストの `voice/hitokoe-notify.sh` は未作成。
- `scripts/gate-lint.sh` `scripts/ui-check.sh` `scripts/measure-idle.sh` … 非機能ゲート（済）。

## 分解の要（なぜこの粒度か）

**単一の RED（`hitokoe_test.zig`）は全純粋関数が揃って初めてコンパイルできる。** この1ファイルが
`main.dragState` `main.aggregate` `main.mouthFrame` `main.focusTarget` `main.parseSession`
`main.parseTty` `main.rmsAt` `main.mouthFrameMotion` `main.enterThrow` `main.throwEnded`
と型 `Velocity/Session/Pid/Status` を**すべて**参照する。Zig のコンパイルはファイル単位で
不可分なので、A だけを実装した worktree では B/D/H のシンボルが未定義でこの1ファイルが
コンパイルできず、`native test app` はどの単一 A/B/D/H フィーチャでも緑にできない。

→ **純粋関数コアは分割不能な1ビルド単位（`pure-core`）**とする。SPEC 5.4 の「状態選択・
集約・口形決定・端末フォーカスを純粋関数に切り出す」を1つのフィーチャで満たす（〜160行）。
概念的な内訳（A/B/D/H）は下表に残すが、ビルドは束ねて出す。criteria の RED を書き換えて
分割することは plan/build ではしない（criteria の資産を壊さない）。

コアが main に入った後の **配線（wiring）フィーチャ**は、コアの純粋関数を呼び出して
実挙動に接続する。配線はいずれも `main.zig` の別々の領域を触るため**同一ファイル＝共有可変
状態**であり、1 wave に複数を並べられない（disjoint files 規則）。コアのマージ後に plan を
再実行すると次の wave（配線）へ自然に進む。

## フィーチャ一覧と依存

| # | feature | 触るファイル | 依存 | 判定（ACCEPTANCE） | wave |
| --- | --- | --- | --- | --- | --- |
| 1 | `pure-core` | `app/src/main.zig`（型 + 純粋関数追加）, `hitokoe_test.zig`（既存・不変） | State(既存)のみ | A1-A5 / B1-B7 / D4-D11 / H1-H2 / H6-H8 / F3 / G4 | **W1** |
| 2 | `voice-notify` | `voice/hitokoe-notify.sh`, `voice/hitokoe-notify.nix` | なし（独立ディレクトリ） | C1-C15 / C9 / C10 | **W1** |
| 3 | `drag-wiring` | `main.zig`（ドラッグ分岐 1420-1463 を dragState/enterThrow/throwEnded に置換） | pure-core | A6 / A（回帰） / G1-G4 | W2 |
| 4 | `session-aggregation` | `main.zig`（poll/tick で `~/.claude/sessions/` を読み aggregate で状態決定, 劣化動作） | pure-core, **B着手前ゲート** | B7 / B8 | W2 |
| 5 | `bubble-tap-focus` | `main.zig`（bubbleView に on_press → Msg → update で Effects.spawn osascript, focusTarget/parseTty） | pure-core | H3-H7 | W2 |
| 6 | `mouth-compositing` | `main.zig`（rootView に mouth.png 合成層, mouthFrame/rmsAt/mouthFrameMotion） | pure-core, **D着手前ゲート** | D1-D3 / D9 / D11 / D12 | W2 |

W2 の 3-6 は全て `main.zig` を触るため相互に非独立。**1 wave 1本ずつ**（マージ→再plan）で進める。
順序推奨: `drag-wiring`（原因特定済み・SDK知識ほぼ不要, SPEC 5.2）→ `session-aggregation` →
`bubble-tap-focus` → `mouth-compositing`（新規GPU描画, SPEC 5.2 により Opus 手動、ヘッドレス
修復ループに任せない）。

## wave の外にある作業（features.txt には載せない）

- **`moveWindow` プラットフォーム実装（A7-A10, SPEC 3.1 スコープ拡張）** — 実体は
  **Native SDK フォーク側**（`Railly/native@65d4885` の `root.zig` / `window_actions`）にあり、
  本リポジトリの `app/src` に無い（このリポジトリにSDKソースは vendoring されていない）。
  Windows は `SetWindowPos`、Linux(X11) は `XMoveWindow`、Linux(Wayland) は no-op 降格。
  判定は実機統合（OSレベル入力 + `GetWindowRect` 差分等）で、本リポジトリのビルドゲートで
  単体判定できない。着手時は `app/PROVENANCE.md` に固定 commit と改変を記録する。
- **アイドルCPU（E1-E3, SPEC 3.5）** — S5（原因特定）待ち。原因確定まで E1/E2 の閾値 `<TBD>`
  は未設定で、コード修正フィーチャを立てられない。原因確定後に `app.zon` / `main.zig` の
  小修正フィーチャ（`gpu_present_mode` 等）として起票する。`scripts/measure-idle.sh` が判定。
- **着手前の人間ゲート（スコープ判断, docs/human-gates.md）**
  - **B着手前**: 8セッション並走の上流挙動を実測し `state/BASE.md` に記録。集約不要なら
    ACCEPTANCE B を削除し SPEC 3.2 を OUT へ移す → feature 4 を落とす。
  - **D着手前**: `mouth.png` を1体分試作し 192×208 で開閉が視認できるか確認。不可なら
    ACCEPTANCE D を削除 → feature 6 を落とす。
  - どちらも配線フィーチャ（4/6）を止めるが、**pure-core の aggregate/mouthFrame は安価な
    純粋関数で既に RED があるため、W1 で先に実装して緑化してよい**（描画・実IO を伴う配線が
    人間ゲート対象）。
- **spike 残（S2 macOS 透過 / S5 CPU 原因 / Linux S1-S3, docs/human-gates.md, ACCEPTANCE S）** —
  人間レビュー。S1-S3 が通るまで E の閾値を確定しない。

## 依存グラフ（要約）

```
State(既存) ─┐
             ├─▶ pure-core ─┬─▶ drag-wiring
voice/(独立) ─▶ voice-notify │  ├─▶ session-aggregation   (要 B着手前)
                             │  ├─▶ bubble-tap-focus
                             │  └─▶ mouth-compositing      (要 D着手前, Opus手動)
SDKフォーク ─▶ moveWindow(A7-A10, 実機統合・リポジトリ外)
S5(spike) ──▶ idle-cpu(E, 閾値TBD)
```

## 次の wave（state/features.txt）

**`pure-core` と `voice-notify`。** 両者は disjoint（`app/src/*.zig` vs `voice/*`）で共有可変
状態が無く、並列 worktree で安全に組める。両者とも依存が main にすべて揃っている
（pure-core は既存 State のみ、voice-notify は依存なし）。
