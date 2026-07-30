# 追加調査・保留タスク

パイプライン正式ドキュメント（SPEC.md/ACCEPTANCE.md/PLAN.md）の外で見つかった、
後で確認・着手する項目のメモ。優先度は都度judgeする。

## Windows: 背景の透過（優先度：低、後回しでよい）

`gpu_alpha_mode="premultiplied"` に変えると app が起動時 `CallbackFailed` でクラッシュする。
クリーンな透過には Native SDK フォークの present 経路を `UpdateLayeredWindow`
(per-pixel alpha) に書き直す必要がある（SDK作者コメントいわく「アーキテクチャの
書き直し」であり、フラグ1つの移植ではない）。詳細・原因は `app/PROVENANCE.md`
「固定 Native SDK フォークへの Windows プラットフォーム改変」節を参照。

## Windows: ドラッグ中のカクつき（2026-07-31 発見、要調査）

ドラッグは指定座標に正しく到達するが、追従がスムーズでない（カクカクする）。

**疑わしい原因**: `app/src/main.zig` のドラッグ追従ロジック（`fx.moveWindow` の
ポーリング）は `.frame_clock`（`onFrame`、実際に GPU フレームが提示された時だけ
発火）の中に同居している。つまりドラッグの更新頻度は「次の描画フレームがいつ来るか」
に完全に依存する。Windows は `gpu_present_path=pixels`（GPU本来の高速経路ではなく
CPU ソフトウェア合成のフォールバック）であり、`docs/prior-art.md` 5.1 / `app/PROVENANCE.md`
既知の課題いわく、差分転送の最適化（patch present）はこの経路に適用されない
＝ 毎フレーム全体を再送信するコストがかかる。これがフレーム提示の遅延・間引きを
招き、ドラッグ追従のカクつきとして体感されている可能性が高い。

これは ACCEPTANCE.md の **S5（アイドル時CPU原因特定, spike）** と根が同じ話
（`gpu_present_path=pixels` のコスト構造）。S5 の原因調査と合わせて確認するのが
効率的。原因確定後、E1-E3（アイドルCPU閾値）のフィーチャ化と合わせて着手を検討。

## 既存パイプラインの残タスク（PLAN.md より、参考に再掲）

- **build wave 2**（`pure-core` マージ後、1本ずつ）: `drag-wiring` → `session-aggregation`
  （要B着手前ゲート）→ `bubble-tap-focus` → `mouth-compositing`（要D着手前ゲート、
  GPU描画のためOpus手動、ヘッドレス修復ループに任せない）
- **moveWindow の他プラットフォーム実装**（wave外、A7-A10）: Windows は今回実装済み
  （`native_sdk_windows_move_window`、実機検証済み）。**Linux(X11) の `XMoveWindow`
  実装は未着手**。Linux(Wayland) は no-op 降格の想定。
- **spike残**（`docs/human-gates.md` / ACCEPTANCE.md「S. spike」）:
  - S2: macOS での透過の実機確認（未実施）
  - S5: アイドル時CPUの原因特定（上記カクつきと関連、未確定）
  - Linux: S1-S3（`native build`・透過・最前面の実機確認、未実施）
- **人間ゲート**（`docs/human-gates.md`）: B着手前（session-aggregation、8セッション
  並走の実測）、D着手前（mouth.png 試作、192x208で開閉が視認できるか）
