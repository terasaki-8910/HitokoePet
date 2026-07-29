# human-gates — 機械判定できない / 実機・SDK・表示が要る受け入れ項目

Stage 1 の指示「機械判定できない項目は人間ゲートにする」に対応する一覧。二種に分ける:

- **[人]** 人間の判断が要る（視認・レビュー・スコープ判断）。自動化できない。
- **[実機]** 機械判定できるが、criteria/build のゲート CI では回せない（実機 OS / Native SDK /
  表示デバイス / ネットワークが要る）。integration_accept 段で実機オペレータが実行する。

該当する Zig 単体・shell・lint は [docs/criteria-notes.md](criteria-notes.md) の対応表参照。

## spike（S1-S5, SPEC 5.1）— [人]

ACCEPTANCE S 表の状態を人間がレビューして確定する。**S1-S3 が通るまで E1/E2 の閾値を
設定しない。** 未了:

- **S2**: 透過が macOS 実機で出るか（Windows は確認済みだが透過領域のノイズが既知課題）。
- **S5**: アイドル CPU の原因特定。macOS 側の `gpu_present_path` が `packet`/`pixels` の
  どちらかを確認するまで 22.7% の原因を確定できない（`docs/prior-art.md` 5.1）。
- Linux 版 S1-S3 は未実施。

## 着手前ゲート（スコープ判断）— [人]

- **B 着手前**: 8セッション並走時の上流挙動を実測し `state/BASE.md` に記録。集約不要と判断
  したら ACCEPTANCE B 全体を削除し SPEC 3.2 を OUT へ移す。
- **D 着手前**: `mouth.png` を1体分試作し、192x208 セルで口の開閉が視認できるか確認。
  視認できなければ ACCEPTANCE D 全体を削除。

## A. つまみ / moveWindow — [実機]

- **A7**: Windows でドラッグ中に実ウィンドウがマウス追従（`SetWindowPos`）。OSレベル入力
  シミュレーション + `GetWindowRect` 差分。
- **A8**: Linux(X11) で同（`XMoveWindow`）。
- **A9**: Linux(Wayland) で `moveWindow` がエラーにならず no-op（劣化）。環境検出の単体 +
  実機。Wayland 検出（`XDG_SESSION_TYPE=wayland` / `WAYLAND_DISPLAY`）は単体化できるので
  build 時に `hitokoe_test.zig` へ足すことを検討。
- **A10**: A7/A8 の実装が A2（速度非依存の単一つまみ状態）と組んでも A4/A5 の投擲・waving
  復帰を壊さない。

## A4 文言の整合 — [人]

ACCEPTANCE A4 括弧書き「速度 < physics_min_vel で throwing に入らない」は現行コード
（閾値約 1, `main.zig:1457`）と食い違う。テストは A4 本文「現状維持」に忠実に閾値約 1 で
符号化済み。ACCEPTANCE の文言を現行実装に合わせて直すか、意図的な仕様変更なら SPEC を
更新するか、人間が判断する。

## B8 / D1 / D9 — [実機]

- **B8**: `~/.claude/sessions/` が無い環境でアプリが起動し既存フック経路で動く（fixture HOME）。
- **D1**: `mouth.png` を持たないペットがエラーにならず口パク無しで描画される。
- **D9**: `.wav` に対応する `.rms` が無いとき、口パク無しで音声だけ再生。

## D2 / D3 / D12 — [実機]

- **D2 / D3**: `scripts/ui-check.sh` に配線済み。`HITOKOE_UI_E2E=1` かつ `native` がある実機で
  実行する。D2 は導入前ペットの baseline スクリーンショットを
  `app/.native/baseline/pet-canvas.png`（`HITOKOE_SCREENSHOT_BASELINE` で上書き可）に採取して
  固定してから比較する。
- **D12**: `voice/` 同梱 WAV すべてに `.rms` があり、現在の WAV から再生成した内容と一致。
  素材（WAV）確定後に生成スクリプトを再実行して diff。WAV が揃うまで保留。

## H3 / H4 / H5 / H7 — [実機 / fake executor]

- **H3**: 吹き出しタップで Effects チャネルに端末フォーカスの spawn が1回だけ。
- **H4**: ペット本体タップでは spawn しない。
- **H5**: 右クリックのコンテキストメニュー（上流既存）がタップ追加後も従来通り開く。
- **H7**: 未対応端末エミュレータで、エラーを出さず何も起きない（spawn を失敗させる）。

SPEC 3.6 では Effects の fake executor で機械判定可能。build 段階で fake executor 用の
純粋な spawn 判定 seam を切り出せれば、H3/H4 は `hitokoe_test.zig` に移せる（そのときは
criteria-notes の対応表を更新する）。現時点では SDK の fake executor API 未確認のため実機扱い。

## 音声フックのシェル未確認 — [人 / 実機]

SPEC 3.3: Windows ネイティブの Claude Code がフックをどのシェル（cmd / PowerShell / Git Bash）
で起動するか未確認。`.sh` がそのまま起動しないなら `.ps1` 版が要る。criteria/build で実機確認。

## E1 / E2 / E3 — [実機]

macOS 実機で `scripts/measure-idle.sh`。**E1/E2 の閾値は S5 後に確定する `<TBD>`**
（`HITOKOE_E1_MAX_CPU_S` / `HITOKOE_E2_MAX_RSS_MB`）。未設定のうちは同スクリプトが赤を返す。
E3（ベースライン 22.7% 未満）は spike 前でも成立。

## F1 / F2 / F3 — [実機 / 人]

- **F1** [実機/自動]: `git diff <BASE>..HEAD -- app/LICENSE` が空（上流著作権表示の無改変）。
- **F2** [人]: `app/PROVENANCE.md` の改変一覧が空でなく、`git diff --stat app/` の各変更が
  記載されているかを人間がレビュー。
- **F3** [実機]: `native test app` で上流既存18テストが通る（SDK 必須）。
