<div align="right">

[![English](https://img.shields.io/badge/lang-English-2b7489?style=flat-square)](./README.en.md)

</div>

# HitokoePet

Claude Code のセッション状態に反応するデスクトップペット。1匹が全セッションを代表し、作業完了を声で伝えて口パクする（Codex pet アトラス規格と互換）。

このプロジェクトは**対応環境の異なる2つの成果物**からなる。混同しないこと。

| 成果物 | 中身 | 対応環境 |
| --- | --- | --- |
| `app/` | ペット本体（つまみ / 多セッション集約 / 口パク / アイドルCPU削減 / 吹き出しタップ） | spike で決定。現状 Windows 実機でビルド・最前面・透過を確認（透過領域に既知のノイズ課題あり）。macOS / Linux は未検証 |
| `voice/` | 音声通知フック（Stop フックで完了を発話） | macOS / Ubuntu / NixOS / Windows |

`app/` は上流 [petdex](https://github.com/crafter-station/petdex) の `packages/petdex-desktop-native` を subtree で取り込み（MIT、`app/PROVENANCE.md` 参照）、そこに本プロジェクト固有の機能を足したもの。

## 要件

- **Native SDK（`@native-sdk/cli`）** — ペット本体のビルド・テストに必須。
  ただし **npm 公開版（0.4.0〜0.6.1）は使えない**。`app/app.zon` の `.floating` /
  `.transparent` を unexpected field として拒否し `native build` が失敗する。
  `Railly/native@feat/floating-window-0.5.3`（commit `65d4885`）から自前ビルドした
  CLI が必要（固定内容は `app/PROVENANCE.md`）。SDK は pre-1.0 で破壊的変更が入る前提。
- **音声再生コマンド** — `voice/` は `afplay` / `pw-play` / `paplay` / `ffplay` /
  `powershell.exe` / `aplay` のいずれかを自動検出して使う。1つも無い環境（ヘッドレス機）
  では黙って何もしない。
- **Codex pet アトラス素材** — 下記のスプライトシートと `pet.json` を
  `~/.codex/pets/<id>/` に置く。
- **（任意）`shellcheck`** — `voice/` のシェルスクリプト検査に使う。

### スプライトシート規格（上流から継承、無改変で読める）

- 8列 × 9行、セル 192×208px、全体 1536×1872px、透過 PNG/WebP
- 行 = 状態、列 = フレーム。余りセルは完全透明
- 行順: `idle`(6) / `running-right`(8) / `running-left`(8) / `waving`(4) /
  `jumping`(5) / `failed`(8) / `waiting`(6) / `running`(6) / `review`(6)
- 配置: `~/.codex/pets/<id>/` に `pet.json` + `spritesheet.webp`

## セットアップ

1. **ペット本体をビルドする**（固定した CLI を使う）:

   ```sh
   native build app
   ```

   これでデスクトップ常駐のペットが得られる。ビルドが通ることは `native doctor` で
   環境を診断してから確認できる。

2. **音声フックを Claude Code に登録する** — `~/.claude/settings.json` の
   `hooks.Stop[].hooks[]` に `voice/` のスクリプトを設定する。**発火は `Stop` フックのみ**
   （`SubagentStop` は対象外）。

   > Codex 向けのスクリプトを流用しないこと。Claude Code の Stop ペイロードに `.type` は
   > 存在せず、`jq -r '.type'` は `null` を返す。「インストールされて動いているように
   > 見えたまま一度も鳴らない」失敗モードになる（詳細は SPEC 3.3.1）。

3. **（任意）口パクを有効にする** — ペットの隣に口レイヤー `mouth.png` を置く。
   無いペットは口パク無しで正常動作する（エラーにしない）。振幅は WAV の隣に事前計算した
   RMS エンベロープ（`done.wav` + `done.rms`）から読む。

4. **（任意）母艦 TTS（L3）を設定する** — キャッシュミス時のみ Tailscale 越しに
   母艦の TTS へ問い合わせる。母艦が落ちていれば L1 の generic WAV にフォールバックする。

## 使い方・挙動

- **1匹で全体を代表する。** `~/.claude/sessions/<pid>.json` を読み、全セッションを
  優先度 `waiting` > `busy` > `idle` で1つの表示状態に畳む。セッションが増えても
  ペットは増えない。スキーマ検証に失敗した場合は本機能を無効化し、既存のフック経路で
  動作を継続する（劣化動作）。
- **つまみ。** マウス押下が続く間は速度に依存せず単一のつまみ状態を保持する
  （ゆっくり動かしても掴んで止めてもモーションが止まらない）。リリース後は投擲物理が働き、
  減速後に `waving` へ戻る。ウィンドウ追従は macOS（実装済み）に加え Windows
  （`SetWindowPos`）/ Linux X11（`XMoveWindow`）で動く。Linux Wayland では何もしない。
- **完了通知の音声。** `Stop` フックが発話を再生する。層構成:

  | 層 | 内容 | 動く場所 |
  | --- | --- | --- |
  | L1 | イベント種別ごとの固定 WAV | 各マシン |
  | L2 | 文言ハッシュをファイル名にしたキャッシュ（`~/.cache/hitokoe/<sha1>.wav`） | 各マシン |
  | L3 | キャッシュミス時のみ Tailscale 越しに母艦の TTS へ | 母艦 |

  複数プロジェクトを同時に回しても通知が被らないよう、`mkdir` による原子ロックで
  直列化する。ロック取得待ちが上限を超えたら諦めて exit 0 する（フック起動を滞留させない）。
- **口パク。** `done.rms` エンベロープを読み、決定論的に口形（閉 / 半 / 開）を選ぶ。
  再生中の音声は観測せず、音声デバイスにも録音 API にも触らない。同じ WAV は常に同じ
  口の動きになる。
- **吹き出しタップ。** 吹き出しを押すと、集約規則の勝者（つまり表示中の状態を採った
  セッション）が動いている端末のタブへフォーカスを移す。「許可待ちがある → 吹き出しを押す
  → その端末に飛ぶ」が一直線になる。検証済みは macOS + iTerm2。対応していない端末では
  何もしない。

## 制約

- **Native SDK は pre-1.0。** 固定ビルドの CLI が必要（上記「要件」）。
- **`app/` の対応環境は spike の出力**であり、無条件の動作保証はしない。透過ウィンドウは
  Windows 実機で確認済みだが透過領域にノイズが乗る既知課題がある。macOS / Linux は未検証。
- **システムトレイ**は macOS / Windows にはあるが Linux には無い。`close_policy = "hide"`
  は Windows では `tray` capability が必須、Linux ではビルド時に拒否される。
- **端末フォーカス（吹き出しタップ）は macOS + iTerm2 のみ保証。** Ghostty / WezTerm /
  Alacritty / kitty は未調査。
- **内部パスへの依存。** `~/.claude/sessions/` は公開 API ではない内部パスのため、
  スキーマが変われば集約機能を無効化して動作を継続する。

## スコープ外（明示的に作らない）

- マイク入力 / STT / Claude Code へのプロンプト注入
- Claude の応答本文の読み上げ
- セッション数だけペットを表示する（N匹）／セッション一覧パネル
- ローカル TTS ランタイムの各環境への導入（生成は母艦 L3 に寄せる）
- iTerm2 以外の端末エミュレータへの対応保証
- Windows / Linux の端末フォーカス
- 音素（viseme）ベースの口パク
- Codex / Gemini CLI / opencode 向けの新機能（上流の既存対応は壊さないが拡張もしない）
- 上流への PR（v1 では行わない）
- コード署名 / 公証 / リリース配布
- Windows / Linux での無条件の動作保証（Wayland のドラッグ、Windows の透過ノイズは未解決のまま）

## ゲート付きパイプラインで開発する

本プロジェクトはゲート付きパイプラインで段階的に作られる。この README も SPEC.md から
自動生成される成果物であり、手書きしない。

```sh
sh scripts/run.sh from <stage>      # 指定ステージから進める
INTERACTIVE=1 sh scripts/run.sh from <stage>   # ヘッドレスでなく TUI で見ながら回す
```

- 段階（ゲート）の定義は `pipeline.yaml`。
- pass/fail の判定基準は `ACCEPTANCE.md`。
- テスト: `native test app`
- Lint: `native check app --strict && scripts/gate-lint.sh`
  （`native check` だけでは不足。このアプリは `.native` マークアップが0個のため
  no-emoji / design-tokens-only / a11y は `scripts/gate-lint.sh` で担保する）
