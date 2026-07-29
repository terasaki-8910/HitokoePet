# SPEC — HitokoePet

## 1. これは何か

Claude Code のセッション状態に反応するデスクトップペット。既存の
[petdex](https://github.com/crafter-station/petdex) の `packages/petdex-desktop-native`
を `app/` に取り込み（MIT、`app/PROVENANCE.md` 参照）、そこに本プロジェクト固有の4点を足す。

ゼロから作らない理由は、調査で「ペットの描画・オーバーレイ・フック導入・Codexペット互換は
既に3実装で解かれている」ことが確認できたため（`state/BASE.md`）。**未解決なのは
本SPECのスコープIN 4点だけ**で、そのすべてが描画・入力ループの内側にある。

## 2. 前提となる既存仕様（上流から継承、変更しない）

Codex pet アトラス規格。本プロジェクトはこれを**無改変で読めることを維持する**。

- スプライトシート: 8列 × 9行、セル 192×208px、全体 1536×1872px、透過 PNG/WebP
- 行 = 状態、列 = フレーム。余りセルは完全透明
- 行順: `idle`(6) / `running-right`(8) / `running-left`(8) / `waving`(4) / `jumping`(5) /
  `failed`(8) / `waiting`(6) / `running`(6) / `review`(6)
- 配置: `~/.codex/pets/<id>/` に `pet.json` + `spritesheet.webp`

## 3. スコープ IN

### 3.1 つまみモーションの保持

**現状の不具合**（`app/src/main.zig:1438-1446`）: ドラッグ中の表示行を**リリース速度から
導出**しており、`@abs(vel.x) < 20 and @abs(vel.y) < 20` の分岐で明示的に `.idle` を設定する。
このため「ゆっくり動かす」「掴んだまま止める」でモーションが停止する。

**あるべき挙動**: マウス押下が継続している間は、速度に依存せず単一のつまみ状態を保持する。
移動方向による左右の出し分けは行わない（片方向のみ）。リリース後の投擲物理（`throwing`）と、
停止時に `waving` へ戻る挙動（`main.zig:1412`）は現状のまま維持する。

**スコープ拡張（spike で判明、2026-07-29）**: `main.zig` はドラッグ中、毎フレーム
`fx.moveWindow` を呼んでウィンドウ自体を追従させる自前実装を持つ（OSネイティブの
`performWindowDrag` は意図的に不使用 — 速度もテストも見えなくなるため）。しかし
固定した Native SDK（`app/PROVENANCE.md` 参照）は `fx.moveWindow` の実体
（`window_actions` バインディング）を **macOS にしか実装していない**。Windows・Linux
の `root.zig` には一切の実装が無く、Windows実機でのOSレベル入力シミュレーションで
「ウィンドウが1ピクセルも動かない」ことを確認済み。

したがって3.1は「どの状態を表示するか」の修正だけでなく、**Windows・Linux向けの
`moveWindow` 実装を Native SDK フォーク側に追加すること**もスコープに含む。

- **Windows**: `SetWindowPos` で素直に実装可能（macOS版と同じ「毎フレーム位置取得→
  速度計算→投げ物理」設計をそのまま移植する）
- **Linux（X11）**: `XMoveWindow` 等で同様に実装可能
- **Linux（Wayland）**: 実装しない。Wayland はセキュリティ/UX上の設計として、
  クライアントが自分のウィンドウの絶対座標を指定するプロトコルを持たない
  （どのコンポジタも同様）。唯一の代替は「コンポジタにドラッグ移動を委任する」
  `gdk_toplevel_begin_move()` 系だが、これは main.zig が意図的に避けている
  ネイティブドラッグと同じ制約（速度もテストも見えなくなる）を持つため採用しない。
  Wayland環境では3.6と同様「対応していない環境では何もしない」（エラーにしない）

### 3.2 複数セッションの集約

**データソース**: `~/.claude/sessions/<pid>.json`。実機で確認済みの構造:

```json
{"pid":67322,"sessionId":"cb3b...","cwd":"/Users/.../PixelArtAvator",
 "startedAt":1785173592988,"version":"2.1.220","kind":"interactive",
 "name":"pixelartavator-87","status":"busy","statusUpdatedAt":1785173665045}
```

`status` は `busy` / `idle` / `waiting`（`waiting` 時は `waitingFor` を伴う）。

**方針**: ペットは常に1匹。全セッションを優先度規則で1つの表示状態に畳む。
セッションが増えてもペットは増えない。

**未検証事項**: 8セッション並走時に上流の実装がどう振る舞うかは未確認。
本項目の実装着手前に実測し、集約が不要と分かれば本項目をスコープから落とす。

**この経路が上流と異なる点**: 上流を含む既存3実装はすべてフック経由の単一状態ファイルに
書き込む（最後の書き込み勝ち）。`~/.claude/sessions/` を読む実装は調査時点で存在しない。
公開APIではない内部パスのため、スキーマ検証に失敗した場合は本機能を無効化し、
既存のフック経路のみで動作を継続する（劣化動作）。

### 3.3 音声通知（`voice/` — ペットとは独立した成果物）

**ペット本体とは対応環境が異なる。** `app/` の対応OSは spike の出力だが（5.1）、
本項目は macOS / Ubuntu / NixOS / Windows で動かす。ペットが載らない環境にも `voice/` だけを配る。

- 発火条件: Claude Code の `Stop` フックのみ。**`SubagentStop` は対象外**
- 内容: 完了を伝える発話

**各環境にTTSランタイムを置かない。** PyTorch / ONNX Runtime / CUDA / Python の組み合わせは
3環境で全て異なり、特に NixOS では Python のバイナリ wheel が FHS 前提のため `nix-ld` /
`buildFHSEnv` / `uv2nix` 等の回避策が必要になる。一方 WAV はどこでも同じバイト列。
低スペック機ではアイドル時RAMとレイテンシがそのまま効く。**再生に倒す。**

段階構成。L1 だけ先に作り、L2 / L3 は必要になってから足す。

| 層 | 内容 | 動く場所 |
| --- | --- | --- |
| L1 | イベント種別ごとの固定WAV | 各マシン |
| L2 | 文言のハッシュをファイル名にしたキャッシュ（`~/.cache/hitokoe/<sha1>.wav`） | 各マシン |
| L3 | キャッシュミス時のみ Tailscale 越しに母艦の TTS へ | 母艦（ThinkBook） |

L3 で生成したものを L2 に落とすので、プロジェクト名のような準固定の文言は2回目以降ヒットする。
母艦が落ちている／外出中は L1 の generic WAV にフォールバックする。

**再生コマンドの差分吸収**（この関数だけで3環境を賄う）:

```sh
play_audio() {
  if   command -v afplay >/dev/null; then afplay "$1"
  elif command -v pw-play >/dev/null; then pw-play "$1"
  elif command -v paplay >/dev/null; then paplay "$1"
  elif command -v ffplay >/dev/null; then ffplay -nodisp -autoexit -loglevel quiet "$1"
  else aplay -q "$1"; fi
}
```

`aplay` は ALSA 直叩きでサウンドサーバー使用中に失敗しやすいため最後の砦とする。
Ubuntu は PipeWire でも `pipewire-pulse` 経由で `paplay` が通る。

**Windows**: PowerShell 標準の `Media.SoundPlayer` で追加依存なしに再生できる。

```sh
elif command -v powershell.exe >/dev/null; then
  powershell.exe -NoProfile -Command \
    "(New-Object Media.SoundPlayer '$(wslpath -w "$1" 2>/dev/null || echo "$1")').PlaySync()"
```

**未検証**: Windows ネイティブの Claude Code がフックをどのシェルで起動するか
（`cmd` / PowerShell / Git Bash）。`.sh` がそのまま起動されない場合は `.ps1` 版が要る。
WSL 上で動かす場合は上記の分岐で足りる。criteria 段階で実機確認する。

**その他の要件**:

- **並列実行の重なり対策**: 複数プロジェクトを同時に回すと通知が被るため直列化する。
  **`flock` は使わない** — util-linux のコマンドで macOS に存在せず、主力機で動かない
  （実機確認済み）。POSIX で原子的な `mkdir` によるロックを使う:

  ```sh
  LOCK=~/.cache/hitokoe/.lock
  until mkdir "$LOCK" 2>/dev/null; do
    [ "$(( $(date +%s) - start ))" -ge "$LOCK_TIMEOUT" ] && exit 0   # 諦めて滞留させない
    sleep 0.1
  done
  trap 'rmdir "$LOCK"' EXIT INT TERM
  ```

  ロック取得待ちが上限を超えたら諦めて exit 0 する（フック起動を滞留させない、ACCEPTANCE C12）
- **NixOS**: `pkgs.writeShellApplication` の `runtimeInputs` で依存を閉じ込める。
  フックは最小限の環境で起動されPATHが通っていない場合があるため、これが有効に働く。
  macOS / Ubuntu 側は素のシェルスクリプトなので、冒頭で
  `export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"` を入れる
- **ヘッドレス機では音声を鳴らさない**: 母艦に SSH して Claude Code を回す場合、
  そもそも音声デバイスが無い。音声デバイスを検出できない環境では黙って何もしない
  （エラーにしない）

#### 3.3.1 Claude Code と Codex のフック機構は別物（実装上の必須注意）

上流 petdex 自身のインストーラ実装（`app/src/agent_hooks.zig`）で確認済み。

| | Codex | Claude Code |
| --- | --- | --- |
| 設定先 | `~/.codex/hooks.json` + `config.toml` の `[features] hooks = true` | `~/.claude/settings.json` の `hooks.<イベント名>` |
| 起動 | `notify = [...]` | `hooks.Stop[].hooks[]` |
| ペイロード | `.type` = `agent-turn-complete` 等 | `session_id` / `transcript_path` / `tool_name` — **`.type` は存在しない** |

**Codex 向けに書かれたスクリプトを流用してはならない。** `jq -r '.type'` は `null` を返し、
`[ "$TYPE" = "agent-turn-complete" ] || exit 0` が毎回 exit 0 する。
**インストールされて動作しているように見えたまま、一度も音が鳴らない**という失敗モードになる。

プロジェクト名は Stop ペイロードの `cwd` に依存せず、`~/.claude/sessions/<pid>.json`
（`cwd` を確実に持つことを実機確認済み）から引く。

### 3.4 口パク

**制約**: Codex アトラスの9行には口レイヤーも talking 行も存在しない。したがって口パクは
必ず独自拡張になる。

**設計**: 二層構造。以下を契約とする。

1. 既存の Codex アトラスは**無改変で読め、従来通り動作する**
2. 口レイヤーは `mouth.png` として**別ファイルの任意拡張**。ベースのスプライトに重ねて合成
3. **`mouth.png` が存在しないペットは、口パク無しで正常動作する**（エラーにしない）

口形は 2〜3 種（閉 / 半 / 開）。音素（viseme）ベースは採用しない — 192×208 セル内の
顔サイズに対して口形5〜6種の差は視認できない見込みで、素材作成コストに見合わない。

**振幅は事前計算する。再生中の音声を観測しない。** 3.3 で音声は独立したフックスクリプトから
鳴るため、ペットは再生中の音を観測できない。代わりに **WAV の隣に RMS エンベロープを
事前計算して置く**（`done.wav` + `done.rms`）。ペットはエンベロープを読むだけで、
音声デバイスにも録音APIにも一切触らない。

この方式の利点:

- 決定論的。同じWAVは常に同じ口の動きになる
- 録音デバイス・音声キャプチャ権限が不要
- `mouthFrame` が純粋関数のままテストできる（ACCEPTANCE D）
- L1 の固定WAV方式と相性が良く、エンベロープ生成は素材作成時に1回で済む。
  L3 で動的生成した分も、L2 にキャッシュする際に同時にエンベロープを吐く

**未検証事項**: 192×208 セルで口の開閉が視認できるかは未確認。人手で `mouth.png` を1体分
試作して判定する。視認できなければ本項目をスコープから落とす。

### 3.5 アイドル時 CPU の削減

**実測ベースライン**（2026-07-28、macOS、`/Applications/Petdex.app`、上流 v0.3.1）:

```
経過 1分31秒 / CPU時間 20.65秒 / RSS 111MB  →  1コアの約23%を継続消費
```

**原因は未確定。** 確実なのは上記の実測値のみ。当初「`gpu_present_mode = "timer"` +
`gpu_vsync = true` により1スプライトフレームあたり15〜30回同じ絵を描き直している」と
断定したが、**撤回する**。根拠:

- SDK の `GpuSurfacePresentMode = enum { none, timer }` に**要求駆動モードが存在しない**。
  「描画を要求駆動に変える」という当初の修正案はマニフェストレベルでは取れない
- SDK のコメントに「idle skipped frames (no repaint needed) keep the previous value」とあり、
  ランタイム側に既に再描画スキップの仕組みがある。冗長描画が起きているとは限らない

**方針**: spike で原因を特定してから修正案を決める。候補は
(a) `gpu_present_mode = "none"` の挙動確認、
(b) アプリ側がフレーム未変化時にスキップを正しく通知できているかの確認、
(c) `gpu_vsync` を落とす。
E1/E2 の目標値は原因特定後に確定する。

### 3.6 吹き出しタップでセッションの端末へ移動

吹き出しをタップすると、そのセッションが動いている端末のタブへフォーカスを移す。

**指す対象は集約規則の勝者**（3.2 と同じ優先度: `waiting` > `busy` > `idle`）。
ペットの表示行・吹き出しの文言・タップ先の3つを同一のセッションに一致させる。
「許可待ちがある → 吹き出しを押す → その端末に飛ぶ」が一直線になる。

**実機で検証済みの経路**（macOS + iTerm2）:

```
~/.claude/sessions/67322.json  →  pid=67322
ps -o tty= -p 67322            →  ttys012
iTerm2 の tty of session       →  /dev/ttys012 と一致 → その session を select
```

iTerm2 は全ウィンドウ・全タブのセッションを `tty` 付きで AppleScript から列挙できる
（実行して確認済み）。未検証は `select` 動詞のみ。

**実装経路**: 吹き出しは独立ウィンドウ（`app/src/main.zig` の `syncBubbleWindow`、
`bubbleView`）。ペット側が右クリック用に `on_press = .noop` を使っている前例があるので、
`bubbleView` のルートノードに `on_press` を足して Msg を飛ばし、`update` から
Effects チャネル経由で `osascript` を spawn する。Effects は fake executor で
spawn をアサートできるため機械判定可能（ACCEPTANCE H）。

**制約**: 端末エミュレータ依存。iTerm2 は検証済み、Terminal.app は同等の scripting を
持つ見込み（未検証）。Ghostty / WezTerm / Alacritty / kitty は未調査。
**対応していない端末では何もしない**（エラーにしない）。3.3 と異なり本項目は
`app/` 側の機能なので macOS のみが対象（5.1）。

## 4. スコープ OUT（明示的に作らない）

- **マイク入力 / STT / Claude Code へのプロンプト注入** — 別プロジェクト規模
- **Claude の応答本文の読み上げ** — コードブロックや長文の扱いが難問で、並走時に実用に耐えない
- **セッション数だけペットを表示する（N匹）** — 「1匹で全体を代表」を選択済み
- **セッション一覧パネル** — 吹き出しが集約規則の勝者を指し、タップでその端末へ飛べる（3.6）ので、
  一覧を出す必要が無い。「1匹で全体を代表」の静けさを保つ
- **ローカルTTSランタイムの各環境への導入** — 3.3 の理由による。生成は母艦（L3）に寄せる
- **iTerm2 以外の端末エミュレータへの対応保証** — 3.6 の制約。対応していない端末では何もしない
- **Windows / Linux の端末フォーカス（3.6）** — Windows Terminal や Wayland では
  ウィンドウフォーカスの外部制御が制限される。macOS + iTerm2 のみを保証対象とする
- **音素（viseme）ベースの口パク** — 3.4 の理由による
- **Codex / Gemini CLI / opencode 向けの新機能** — 上流の既存対応は壊さないが、拡張もしない
- **上流への PR** — v1 では行わない。3.1 と 3.5 は上流のバグ／改善なので将来の検討事項として
  `app/PROVENANCE.md` に記録する
- **コード署名 / 公証 / リリース配布** — 自分で使うことが目的。未署名配布時の
  Gatekeeper 問題（`docs/recipes/tauri-desktop-app.md` 6項）には踏み込まない
- **Windows / Linux での無条件の動作保証** — 下記制約を参照。ただし spike の結果
  （5.1）により、ビルド・透過・最前面は Windows で実機確認済み、ドラッグ（3.1）は
  Windows・Linux(X11) を対象に自前実装する方針になった。Linux(Wayland) の
  ドラッグと、Windows特有の透過合成の視覚的ノイズ（既知課題、app/PROVENANCE.md
  参照）は対象外・未解決のまま残る

## 5. 制約とリスク

### 5.1 対応OS — ペット本体は spike の出力であって、intake の前提ではない

本プロジェクトは**対応環境の異なる2つの成果物**からなる。混同しないこと。

| 成果物 | 中身 | 対応環境 |
| --- | --- | --- |
| `app/` | ペット本体（3.1 / 3.2 / 3.4 / 3.5 / 3.6） | **spike で決める**（下記） |
| `voice/` | 音声通知フック（3.3） | macOS / Ubuntu / NixOS / **Windows** |

#### 撤回した判断

当初「`app.zon` が `gpu_backend = "metal"` を決め打ちしているので macOS のみ」としたが、
**これは誤り**。SDK の `GpuSurfaceBackend = enum { none, metal, software }` のコメントと
公式プラットフォーム対応表の脚注2に、Linux と Windows は決定論的ソフトウェアレンダラを
プラットフォームの blit 経路（Linux: cairo、Windows: GDI）で提示し、
**別バックエンドを要求したマニフェストはエラーにせず software にフォールバックする**と明記されている。
マニフェストの `gpu_backend` はプラットフォームの門ではない。

SDK は3デスクトップとも実装している（macOS が最深、Windows は Win32 ホストで
実入力注入を含めCI検証、Linux はソフトウェアレンダラで実ウィンドウ）。

#### 実際の未確認事項（OS選定より前に潰す）

**ペットに不可欠な `transparent` と `floating` が、SDK の現行マニフェストスキーマに存在しない。**

- `ShellWindow` のフィールドは label / title / width / height / x / y / resizable /
  restore_state / restore_policy / titlebar / min_width / min_height / close_policy / views のみ
- `app.zon` の公式ドキュメントのフィールド一覧にも、プラットフォーム対応表にも記載が無い
- SDK ソース中の `transparent` は全て WebView 用オプション
- それでも取り込んだ `app/app.zon` は `.floating = true` と `.transparent = true` を書いている
- **`app/` に SDK バージョンの固定が無い。** `native build` はグローバル導入の
  `@native-sdk/cli` を使う。pre-1.0 に対してピン留め無しで参照している

したがって「Windows で透過ウィンドウが出るか」以前に、**現行SDKで macOS でも透過ウィンドウが
出るかが未確認**。ここが成立しなければ土台（petdex-desktop-native）の選択自体が無効になる。

#### spike の順序（これ以外の作業を始める前に）

1. `native build app` が現行SDKで通るか
2. 透過・最前面のウィンドウが macOS で実際に出るか。出ないなら SDK バージョンを特定して固定する
3. 同じことを Windows で確認する
4. 同じことを Linux で確認する

#### spike 進捗（2026-07-29、Windows機で実施）

1. **済**: npm公開版 `@native-sdk/cli`（0.4.0〜0.6.1 全バージョン）では
   `app/app.zon` の `.floating`/`.transparent` が unexpected field で `native build` が
   失敗することを確認。原因は上流petdex自身も同じで、npm版ではなく
   `Railly/native@feat/floating-window-0.5.3`（commit `65d4885`）から自前ビルドした
   CLI を使う必要がある（`app/PROVENANCE.md` に固定内容を記録済み）。このCLIでは
   `native build app` 成功
2. **未**: macOS での実機確認はまだ（上流CIは同じピンでmacOS/Linuxも通しているため
   通る可能性は高いが未検証）
3. **済**: Windows実機で確認。`WS_EX_TOPMOST`/`WS_EX_LAYERED` が実際に設定され、
   実デスクトップキャプチャで背景越しに他ウィンドウが透けることを確認。ただし
   透過領域に視覚的ノイズが乗る既知課題あり（原因未特定、app/PROVENANCE.md）。
   また、つまみドラッグ（3.1）が機能しないことが判明（3.1のスコープ拡張を参照）
4. **未**: Linux実機確認はまだ

#### OS別の既知のギャップ（1〜4が通った場合に効いてくる）

| | macOS | Windows | Linux |
| --- | --- | --- | --- |
| SDK の成熟度 | 最深 | Win32ホスト、CI検証あり | ソフトウェアレンダラ |
| システムトレイ | あり（NSStatusItem） | あり | **無し**（`UnsupportedService` を返す） |
| `close_policy = "hide"` | 可 | `"tray"` capability が必須。無いと**ビルド時に拒否** | **ビルド時に拒否**（再表示手段が無いため） |

`app/app.zon` の `capabilities` は `native_views, gpu_surfaces, menus, url_schemes` で、
**`tray` を宣言していない**。Windows でトレイを使うなら追加が必要。
Linux はトレイが無いため、常駐ペットの終了・再表示の導線を別途設計する必要がある
（右クリックメニューは3デスクトップとも native で動く）。

### 5.2 Native SDK の成熟度

`@native-sdk/cli` は 2026-05-08 作成、v0.6.1（pre-1.0）、週間DL 3,241。
破壊的変更が入る前提のSDK。取り込んだ `app/` 自体も7コミットの新規実装。

当初「事例が少なくヘッドレス修復ループが機能しない」と評価したが、公式ドキュメントを
確認した結果、**このSDKはエージェント運用を前提に設計されている**ことが分かったため下方修正する。

- `native test` / `native check --strict` が機械判定のゲートとして使える
- 各アプリに自動化サーバーが埋め込まれ、エージェントがアクセシビリティスナップショット取得、
  ウィジェット操作、ライブ状態のアサート、決定論的スクリーンショットを行える
  （`native automate`）
- `native automate record` / `replay` でセッションを記録し、状態フィンガープリントを用いて
  ヘッドレスにフレーム単位で再生検証できる
- SDK 自身がエージェント用スキルを同梱している（`native skills list`）。
  導入は `state/init-tools.sh` 経由で人間が行う

**残る帰結**（役割分担は維持する）:

- **既存コードの局所修正**（3.1 / 3.5）— 原因特定済み、SDK知識をほぼ要さない。build段階で扱う
- **新規の描画コード**（3.4 の口レイヤー合成）— SDK の GPU サーフェス API の理解を要する。
  **ヘッドレスループに任せず、Opus で手動対応する**

### 5.2.1 このアプリはSDKの検証機構の一部を利用できない

`native check` のアクセシビリティ検査と型付きバインディング検査は `src/**.native`
マークアップを対象とする。**`app/` にマークアップは0個**（Zig 6ファイル + `app.zon` のみ、
gpu_surface への直描画）。したがって a11y は独自の構造検査で担保する（ACCEPTANCE G3）。

### 5.3 上流追従

上流は日次で push されている。`app/` は subtree なので取り込みは可能だが、
`main.zig`（2,132行）に手を入れる本プロジェクトは衝突しやすい。
改変内容は `app/PROVENANCE.md` の表に必ず記録する。

### 5.4 テスト可能性

`app/src/` には Zig テストが18個あるが、**`main.zig` には0個**。本プロジェクトの変更は
すべて `main.zig` に入る。状態選択・集約・口形決定は**純粋関数に切り出してテストする**ことを
実装上の必須要件とする。
