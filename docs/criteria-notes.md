# criteria-notes — Stage 1 の受け入れ資産と build への引き継ぎ

Stage 1（criteria）で作った「落ちるテスト（RED）」と静的検査の一覧、build 段階が満たすべき
純粋関数 API の契約、および ACCEPTANCE 各項目の判定手段の対応表。**フィーチャコードは
まだ書いていない。** 各 RED は build がフィーチャを正しく実装した時点で緑になる。

機械判定できない項目は [docs/human-gates.md](human-gates.md) に人間ゲートとして分離した。

## 現在の RED はどう緑になるか

- Zig 単体テスト（`app/src/hitokoe_test.zig`）は、参照している純粋関数がまだ `main.zig` に
  無いため**コンパイルできない**。これが意図した RED。build が下記契約どおり関数を切り出すと
  コンパイルが通り、アサーションが緑になる。
- テスト探索は `main.zig` 末尾の集約子 `test { _ = @import("hitokoe_test.zig"); }` で保証する。
  `test` ブロックはテストビルド時のみ解析されるので `native build app`（非テスト）には無影響。
- `voice/test.sh` は被テストの `voice/hitokoe-notify.sh` が無いため fail-fast で赤。
- 閾値未確定の計測（E1/E2）は、閾値環境変数が未設定なら赤にしてある（空白を合格に読み替えない）。

## build が満たす純粋関数 API 契約（`main.zig` に pub で公開）

SPEC 5.4 の「状態選択・集約・口形決定は純粋関数に切り出す」の具体形。ACCEPTANCE が明示した
シグネチャに従い、暗黙部分の表現はここで確定する。

```zig
pub const Velocity = struct { x: f64, y: f64 };
pub const Pid = i32;
pub const Status = enum { busy, idle, waiting, unknown };
pub const Session = struct {
    status: Status = .unknown,
    pid: Pid = 0,
    // name / cwd / waiting_for 等は build が固定長バッファで持ってよい。ただし
    // aggregate / focusTarget のテストは status / pid だけで構築するため、残りは既定値を持つこと。
};

// A. つまみ保持（SPEC 3.1）
pub fn dragState(vel: ?Velocity, primary_down: bool) ?State; // 押下中は速度非依存で単一状態
pub fn enterThrow(vel: Velocity) bool;      // リリース時の投擲突入（現状: |x|<1 かつ |y|<1 で不突入）
pub fn throwEnded(elapsed_ms: u32, speed: f64) bool; // speed<physics_min_vel か 最大時間で終了
pub const post_throw_state: State = .waving;         // 投擲終了後の遷移先

// B. 集約（SPEC 3.2） 優先度 waiting > busy > idle。0件は idle。
pub fn aggregate(sessions: []const Session) State;   // waiting->.waiting busy->.running idle->.idle
pub fn parseSession(json: []const u8) ?Session;      // 必須キー(status/cwd/name)欠落で null、
                                                     // 未知 status 文字列は .unknown に写す

// D. 口パク（SPEC 3.4） 事前計算エンベロープ(.rms)を読む。再生中の音は観測しない。
pub const mouth_shape_count: u8 = 3;                  // 閉/半/開（design_brief 2項）
pub fn mouthFrame(rms: f32) u8;                       // 0..mouth_shape_count-1、単調非減少、
                                                     // rms<=0/NaN/inf は 0 に倒す（クランプ）
pub fn mouthFrameMotion(rms: f32, reduce_motion: bool) u8; // reduce_motion 真で 0 固定（抑制）
pub fn rmsAt(env: []const f32, i: usize) f32;        // 範囲外は 0.0（範囲外アクセスしない）

// H. 吹き出しタップの対象（SPEC 3.6） aggregate と同一優先度で pid を選ぶ。
pub fn focusTarget(sessions: []const Session) ?Pid;  // 0件は null。同順位は入力順で先勝ち。
pub fn parseTty(ps_out: []const u8) ?[]const u8;     // "?"/"??"/空/空白のみ は null、それ以外は tty 名
```

補足:
- `aggregate` の busy は既存の状態表（`hook_runner.zig` の `stateForEvent`）に倣い `.running`
  （行7）に写す。waiting は `.waiting`（行6）。
- `focusTarget` の同順位タイブレークは「入力配列で最初に現れた勝者ステータス」。テスト
  H1/H1b は勝者が一意な入力で照合する（タイブレークに依存しない）。
- `enterThrow` は既存の投擲物理を壊さないための抽出。build は `update()` の投擲突入判定を
  この関数呼び出しに置き換える（挙動は不変、テスト可能性のための機械的切り出し）。

## `voice/hitokoe-notify.sh` の契約（build が実装）

`voice/test.sh` の冒頭コメントに全文。要点:

- Claude Code hook JSON を stdin から読み、`hook_event_name == "Stop"` のときだけ再生。
  SubagentStop・他イベント・未知イベント・Codex 形式（`.type` あり `hook_event_name` 無し）・
  不正 JSON は再生せず **常に exit 0**（フェイルクローズ、Claude 本体を止めない）。
- 再生コマンド探索順 `afplay -> pw-play -> paplay -> ffplay -> powershell.exe -> aplay`、
  1つも無ければ無音 exit 0。
- `${HITOKOE_CACHE_DIR}/.lock` を `mkdir` で原子ロックし直列化。`HITOKOE_LOCK_TIMEOUT` 秒で諦め exit 0。
- L2 キャッシュ（`~/.cache/hitokoe/<sha1>.wav`）、L3 母艦 TTS（`HITOKOE_TTS_URL`、
  `curl --max-time HITOKOE_MAX_TIME`）。不通なら L1 generic にフォールバック。ヒット時は無通信。
- テスト seam の環境変数: `HITOKOE_PLAY_CMD` `HITOKOE_CACHE_DIR` `HITOKOE_WAV_DIR`
  `HITOKOE_LOCK_TIMEOUT` `HITOKOE_TTS_URL` `HITOKOE_MAX_TIME`、および `HITOKOE_CACHE_KEY`
  （設定時は L2 キャッシュ basename を sha1 計算せずこの値に固定。C15 のヒット検証専用）。
- NixOS 用に `pkgs.writeShellApplication` の定義（`voice/*.nix`）を置き、`runtimeInputs` に
  スクリプトが呼ぶ外部コマンド（curl 等）を網羅する（C10）。

## 判定手段の対応表（ACCEPTANCE 全項目）

| 項目 | 手段 | 具体 |
| --- | --- | --- |
| A1-A3 | Zig unit | `hitokoe_test.zig` "A1.."/"A2.."/"A3.." |
| A4-A5 | Zig unit | 同 "A4 enterThrow" / "A5 throwEnded" |
| A6 | 静的検査 | `scripts/gate-lint.sh`（dragging 分岐の速度参照） |
| A7-A10 | 統合(実機) | human-gates（Windows/X11/Wayland のウィンドウ追従） |
| B1-B6 | Zig unit | `hitokoe_test.zig` "B1.."〜"B6.." |
| B7 | Zig unit | 同 "B7 parseSession" |
| B8 | 統合(fixture HOME) | human-gates |
| B 着手前 | 人間ゲート | 8セッション実測 → `state/BASE.md` |
| C1-C6 | shell | `voice/test.sh`（イベント選別） |
| C7-C8 | shell | 同（探索順 / 皆無時） |
| C9 | shell | `shellcheck voice/*.sh`（test.sh 内でも実行） |
| C10 | shell | 同（nix runtimeInputs 網羅、`voice/*.nix` 必須） |
| C11-C12 | shell | 同（並列ロック / タイムアウト） |
| C13-C15 | shell(curl) | 同（curl があるときのみ、無ければ skip） |
| D4-D8,D10,D11 | Zig unit | `hitokoe_test.zig` "D4.."〜"D11.." |
| D1,D9 | 統合 | human-gates |
| D2,D3 | 統合(SDK+表示) | `scripts/ui-check.sh`（`HITOKOE_UI_E2E=1` opt-in） |
| D12 | shell(要WAV) | human-gates（`.rms` 再生成 diff、素材確定後） |
| D 着手前 | 人間ゲート | `mouth.png` 試作の視認確認 |
| H1,H2,H6,H8 | Zig unit | `hitokoe_test.zig` "H1.."/"H2.."/"H6/H8.." |
| H3,H4,H5,H7 | 統合(fake exec) | human-gates |
| S1-S5 | 人間レビュー | spike。状態は ACCEPTANCE S 表に記録 |
| E1,E2 | 計測(閾値TBD) | `scripts/measure-idle.sh`（S5 後に閾値設定、それまで赤） |
| E3 | 計測(実機) | 同（ベースライン 22.7% 未満） |
| F1 | diff | `git diff <BASE>..HEAD -- app/LICENSE` が空 |
| F2 | diff レビュー | human-gates（PROVENANCE の改変一覧） |
| F3 | テスト | `native test app`（既存18テスト） |
| G1-G2 | lint | `scripts/gate-lint.sh`（no-emoji / no-hex） |
| G3 | lint | 同 + `scripts/ui-check.sh`（app.zon a11y） |
| G4 | lint | 同（純粋関数のテスト存在） |

## 判定コマンド（criteria 段階の最初に実機で通ることを確認）

```sh
native test app                                   # A/B/D/H の Zig unit + F3 既存18テスト
native check app --strict && scripts/gate-lint.sh # G1-G4 / A6（CLAUDE.md の Lint）
voice/test.sh                                     # C1-C15
shellcheck voice/*.sh scripts/*.sh                # C9 と自身の健全性
scripts/ui-check.sh                               # G3（＋ HITOKOE_UI_E2E=1 で D2/D3）
scripts/measure-idle.sh                           # E（macOS 実機、閾値設定後）
```

`gate-lint.sh` の走査基点は `HITOKOE_BASE`（既定 `6e205e5` = subtree 取り込み点）。

## 規約と留意

- `_` 接頭辞の識別子は「意図的な未使用」（Zig の `_ =` 破棄 / `_name` 引数）。テストも遵守。
- リンタは実行時/ビルド生成物を走査しない: `state/** dist/** node_modules/** coverage/**`
  `app/.zig-cache/** app/zig-out/**`、および `*.png *.webp *.rms *.wav`。
- **要人間確認の食い違い**: ACCEPTANCE A4 の括弧書き「速度 < physics_min_vel で throwing に
  入らない」は現行コード（閾値約 1、`physics_min_vel=65` ではない, `main.zig:1457`）と一致しない。
  テストは A4 本文「現状と同じ挙動を保つ」に忠実に閾値約 1 で符号化した。文言の整合は human-gates 参照。
