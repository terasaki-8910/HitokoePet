# 追加調査・保留タスク

パイプライン正式ドキュメント（SPEC.md/ACCEPTANCE.md/PLAN.md）の外で見つかった、
後で確認・着手する項目のメモ。優先度は都度judgeする。

## README 用 GIF の撮影中に見つかった不具合（2026-10-12、未修正）

- **終了済みセッションのファイルを拾い続ける**: `aggregate()` は `status` だけを見て、pid が
  生きているかを確かめない。開発機の WSL 側 `~/.claude/sessions/` に 7 月・9 月の
  `1526.json`（busy）/ `1647.json`（waiting）が残っており、ペットはこれを拾う。WSL 側は
  20 tick に 1 回だけ走査するので、約 2 秒ごとに waiting へ切り替わり、waiting はボイスの
  クールダウン対象外のため、そのたびに鳴る可能性がある。対策候補: ネイティブ側は
  `OpenProcess` で生存確認、WSL 側は `procStart` / `updatedAt` との突き合わせか、
  `wsl.exe` 経由の生存確認を間引いて行う。
- **ドラッグ中に吹き出しが追従しない**: 離すとペットの上に戻る。`.physics_tick` は投擲中の
  分岐では `syncBubbleWindow` を呼ぶが、ドラッグ中の分岐では呼んでいない（`.frame_clock` 側は
  `dragging or throwing` の間は早期 return する）。ドラッグ中の分岐にも同じ呼び出しを足せば直る見込み。
- **`PETDEX_PET` を指定すると設定ファイルを読まない**: `resolveInitialPet` が
  `env_wanted_pet` のときに設定の読み込みを丸ごと飛ばす。`agents_prompted` も既定値
  （false）になるため、起動直後の `saveSettings` で設定ファイルが既定値に上書きされる。

## 【重大インシデント記録】petdex.dev の同名別キャラでユーザーの実キャラを上書き破壊・復旧済み（2026-08-01）

スプライト縁ノイズ調査中、petdex.dev の公開カタログから同名 "iroha"（実際は
別作品の別キャラ）を確認せず再取得・上書きし、ユーザーの実際の棗いろは
アセットを破壊した。ユーザーが手動で復元、以後の分析は復元後の正しい
ファイルに対して実施。絶対規則は memory `never-refetch-pet-assets-online`
に記録。詳細は `app/PROVENANCE.md`「重大インシデント: petdex.dev の同名別
キャラでユーザーの実キャラを上書き破壊（2026-08-01 続き16）」参照。

## ボイスのキャラ別分離 + 絵文字による抑揚付け — 実装済み、聴感確認は未（2026-08-01）

`app/assets/voice/script.json`（単一ファイル）を `app/assets/voice/<slug>/
script.json` へキャラ別に分離（`voiced_pet_slug` = `"iroha"`）。台詞は
`voice/samples/daihon.md` の作法（絵文字を擬音語・間投詞の直後に埋め込む）に
沿って全カテゴリ書き換え、`voice/samples/emoji_sweep/` の生成に使われていた
キャラ専用LoRA（`irodori_iroha_lora`）も `generate-voice.py` から使えるように
した。テキスト内容とビルド成功（`native test app` 25/25 green）は確認済みだが、
実際の聴感（抑揚が改善したかどうか）はユーザー自身の確認待ち。詳細は
`app/PROVENANCE.md`「ボイスをキャラごとに分離 + 絵文字による抑揚付け（SPEC 3.7
続き）（2026-08-01 続き13）」参照。

## 吹き出しタップでセッションの端末へ移動（3.6） — Windows/WSL実装・実機検証済み、macOSはコードのみ未検証（2026-08-01）

当初「macOSのみ対象」というSPEC上の判断を撤回し、実際のユーザー端末構成
（個別コンソールウィンドウ、Windows Terminalではない）を踏まえてWindows/WSLに
実装・実機検証した。macOSはSPEC既存の設計（iTerm2 windows/tabs/sessionsをtty
照合しselect）通りにコードは書いたが、開発機にmacOSが無いため未検証のまま。
詳細はSPEC.md 3.6を参照。

## スプライト縁ノイズ — 真因はレンダリング側のニアレストネイバー縮小、部分修正済み・完全解消は保留（2026-08-01）

「素材（白マット汚染・アルファ縁ノイズ）の問題」という続き9・続き12の診断は
半分誤りだった。実機フィードバックで強く反論され再調査した結果、真因は
`app/src/main.zig` `rootView` が既定scale=0.7（可変域0.4-1.2、初期値0.7は
**縮小**）でも `image_sampling = .nearest` 固定だったこと — ニアレストネイバーは
縮小方向にはエイリアシングを起こす。素材側のわずかな粒（続き12で対処済み）を
この縮小方式が可視ノイズへ増幅していた。

`model.scale < 1.0` なら `.linear` に切り替える修正を適用済み（設定のペット
選択サムネイルも同様）。ただし**完全解消ではない** — `reference.zig` の
`.linear` は2x2バイリニア1タップのみで、0.7倍相当の縮小率には本来必要な
box/mipmapフィルタより弱い。加えてこのマシンはDPI-aware宣言なしでDPI仮想化
スケーリングが効いている（続き8隣接記録参照）ため、アプリの描画後にさらに
別のスケーリングパスが挟まっている可能性が高い。完全な解消には (a) レンダラー
への box/mipmap 縮小フィルタ実装（native SDK フォーク追加パッチ）、または
(b) アプリの per-monitor DPI aware 化（窓位置計算全体に波及する大きめの変更）
が必要 — いずれも今回のスコープ外として保留。詳細は `app/PROVENANCE.md`
「スプライト縁ノイズ、続き12の診断が誤りだったと判明 — 真因はレンダリング側の
ニアレストネイバー縮小（2026-08-01 続き14）」参照。

なお続き9由来の「decode時の恒久修正」（`scripts/fix-sprite-matte.py` の
補正をアプリの `decodeSheet` に自動組み込む）は上記とは別の話として保留のまま
— そちらは素材の白マット汚染そのものへの対処で、無効化されたわけではない。

## Windows: 背景の透過 — 解消（2026-08-01）

`UpdateLayeredWindow`(per-pixel alpha) への present 経路書き換え、`isSupported()` の
`premultiplied` 許可、透過窓のクリア色を alpha 0 にする修正の3点で解消。実デスクトップ
キャプチャで確認済み。詳細は `app/PROVENANCE.md`「Windows per-pixel alpha 透過の実装
（2026-08-01）」節を参照。

## Windows: 吹き出し上部の色ノイズ — 解消（2026-08-01）

デバッグプリントで実ピクセルを直接観測し確定: 共有ピクセルバッファ
（`runtime/ui_app.zig` の `self.pixel_buffer`）の部分更新（`.load`）パスが、
音声サブシステムと同じプロセスヒープの確保/解放タイミングと重なったときに
未クリア領域へ音声関連データの残留を可視化していた。透過窓は毎フレーム強制的に
`full_repaint=true`（`force_full_repaint`）にすることで解消 — 対象窓は十分小さく
コストは無視できる。実機で11回のバブル生成・合成ドラッグ・CPU使用量とも異常なし
を確認済み。詳細は `app/PROVENANCE.md`「吹き出し上部の色ノイズ — 根本原因特定・解消
（2026-08-01 続き8）」節を参照。

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
