#!/usr/bin/env sh
# shellcheck shell=sh
#
# ACCEPTANCE C（SPEC 3.3 / voice/ 成果物）の機械判定。app/ とは別成果物で shell 製なので
# 判定も shell で行う。Stage 1（criteria）で書いた RED テスト。**フィーチャは含まない。**
#
# 被テスト対象は `voice/hitokoe-notify.sh`（build 段階で作る）。現時点では存在しないので
# 本ハーネスは fail-fast で赤になる。build が下記の契約でフックを実装した時点で緑になる。
#
# --- hitokoe-notify.sh の契約（build が満たす。テストの seam はすべて環境変数）-------------
#   * Claude Code の hook JSON を stdin から読む。
#   * `hook_event_name == "Stop"` のときだけ再生する。SubagentStop と他イベントは無音で exit 0。
#   * フェイルクローズ: hook_event_name が無い/未知、Codex 形式（`.type` を持ち
#     hook_event_name を持たない）、不正 JSON、いずれも再生せず exit 0。
#   * 再生コマンド探索順: afplay -> pw-play -> paplay -> ffplay -> powershell.exe -> aplay。
#     最初に command -v で見つかったものを使う。1つも無ければ無音で exit 0（ヘッドレス）。
#   * 何が起きても exit 0（Claude Code 本体を止めない）。
#   * 直列化: ${HITOKOE_CACHE_DIR}/.lock を mkdir で原子ロック。取得待ちが
#     HITOKOE_LOCK_TIMEOUT 秒を超えたら諦めて exit 0（滞留させない）。
#   * L3(母艦TTS): HITOKOE_TTS_URL へ curl --max-time HITOKOE_MAX_TIME。到達不能なら
#     L1 generic WAV にフォールバック。L2 キャッシュヒット時はネットワークに触れない。
#
#   テスト用 seam の環境変数:
#     HITOKOE_PLAY_CMD    設定時は探索せずこのコマンドに wav を渡す（再生スタブ）
#     HITOKOE_CACHE_DIR   L2 キャッシュ兼ロック置き場
#     HITOKOE_WAV_DIR     L1 の generic/イベント別 WAV の置き場
#     HITOKOE_LOCK_TIMEOUT  ロック取得の上限秒
#     HITOKOE_TTS_URL     L3 母艦のエンドポイント
#     HITOKOE_MAX_TIME    L3 への curl の上限秒
#     HITOKOE_CACHE_KEY   設定時は L2 キャッシュの basename を sha1 計算せずこの値に固定
#                         （テスト専用。キャッシュヒット検証 C15 で使う）
# ------------------------------------------------------------------------------------------

set -u

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
HOOK=${HOOK:-"$here/hitokoe-notify.sh"}

pass=0
fail=0
skip=0
ok()   { pass=$((pass + 1)); printf 'ok   - %s\n' "$1"; }
ng()   { fail=$((fail + 1)); printf 'NOT  - %s\n' "$1"; }
skp()  { skip=$((skip + 1)); printf 'skip - %s\n' "$1"; }

if [ ! -f "$HOOK" ]; then
  printf 'voice/test.sh: 被テストの %s がまだ存在しません（Stage 1 の想定 RED）。\n' "$HOOK" >&2
  printf 'build 段階で契約どおりフックを実装すると本ハーネスが緑になります。\n' >&2
  exit 1
fi
if [ ! -x "$HOOK" ]; then
  printf 'voice/test.sh: %s に実行権がありません。\n' "$HOOK" >&2
  exit 1
fi

WORK=$(mktemp -d 2>/dev/null || mktemp -d -t hitokoe)
trap 'rm -rf "$WORK"' EXIT INT TERM

# 再生スタブ: 呼ばれたら PLAY_LOG に "PLAY <wav>" を1行足す。
PLAY_STUB="$WORK/play-stub"
PLAY_LOG="$WORK/play.log"
cat >"$PLAY_STUB" <<'STUB'
#!/usr/bin/env sh
printf 'PLAY %s\n' "$1" >>"$HITOKOE_PLAY_LOG"
STUB
chmod +x "$PLAY_STUB"

# 探索順検証用の名前付きスタブ（PATH に置く）。呼ばれた自分の名前を PROBE_LOG に書く。
make_named_stub() {
  # $1 = コマンド名, $2 = 置き場ディレクトリ
  cat >"$2/$1" <<STUB
#!/usr/bin/env sh
printf '%s\n' "$1" >>"\$HITOKOE_PROBE_LOG"
STUB
  chmod +x "$2/$1"
}

# クリーンな実行環境を毎回作る。
reset_env() {
  : >"$PLAY_LOG"
  CACHE="$WORK/cache"; rm -rf "$CACHE"; mkdir -p "$CACHE"
  WAVS="$WORK/wav";   rm -rf "$WAVS";  mkdir -p "$WAVS"
  printf 'RIFFgeneric' >"$WAVS/generic.wav"
  export HITOKOE_PLAY_LOG="$PLAY_LOG"
  export HITOKOE_CACHE_DIR="$CACHE"
  export HITOKOE_WAV_DIR="$WAVS"
  export HITOKOE_LOCK_TIMEOUT=2
  export HITOKOE_MAX_TIME=2
  export HITOKOE_PLAY_CMD="$PLAY_STUB"
  unset HITOKOE_TTS_URL 2>/dev/null || true
  unset HITOKOE_CACHE_KEY 2>/dev/null || true
}

RC=0
run_hook() {
  # $1 = payload。呼び出し側が事前に env を整える。
  RC=0
  printf '%s' "$1" | "$HOOK" >"$WORK/out" 2>"$WORK/err" || RC=$?
}
played()     { [ -s "$PLAY_LOG" ]; }
not_played() { [ ! -s "$PLAY_LOG" ]; }

STOP='{"hook_event_name":"Stop","session_id":"s1","transcript_path":"/tmp/t.jsonl","cwd":"/tmp/p"}'
SUBSTOP='{"hook_event_name":"SubagentStop","session_id":"s1"}'
CODEX='{"type":"agent-turn-complete","last-assistant-message":"done"}'
BADJSON='{not valid json'

# ---- C-1. イベント選別 --------------------------------------------------------------------

reset_env; run_hook "$STOP"
if played && [ "$RC" -eq 0 ]; then ok "C1 Stop で再生が発火"; else ng "C1 Stop で再生が発火"; fi

reset_env; run_hook "$SUBSTOP"
if not_played && [ "$RC" -eq 0 ]; then ok "C2 SubagentStop で発火しない"; else ng "C2 SubagentStop で発火しない"; fi

c3_all=1
for ev in PreToolUse PostToolUse Notification SessionStart PreCompact UserPromptSubmit; do
  reset_env
  run_hook "{\"hook_event_name\":\"$ev\"}"
  if not_played && [ "$RC" -eq 0 ]; then :; else c3_all=0; printf '     (%s で発火 or 非0終了)\n' "$ev"; fi
done
if [ "$c3_all" -eq 1 ]; then ok "C3 非Stopイベント全てで発火しない"; else ng "C3 非Stopイベント全てで発火しない"; fi

reset_env; run_hook '{"hook_event_name":"TotallyMadeUpEvent"}'
if not_played && [ "$RC" -eq 0 ]; then ok "C4 未知イベント名で発火しない（フェイルクローズ）"; else ng "C4 未知イベント名で発火しない"; fi

reset_env; run_hook "$CODEX"
if not_played && [ "$RC" -eq 0 ]; then ok "C5 Codex形式(.type)で誤発火しない"; else ng "C5 Codex形式(.type)で誤発火しない"; fi

reset_env; run_hook "$BADJSON"
if [ "$RC" -eq 0 ]; then ok "C6 不正JSONでも exit 0"; else ng "C6 不正JSONでも exit 0（RC=$RC）"; fi

# ---- C-2. 環境互換 ------------------------------------------------------------------------

# C7: 探索順。PATH 先頭に全スタブ（実在プレイヤより優先）を置き、HITOKOE_PLAY_CMD を外す。
# 先頭の afplay が選ばれること。coreutils を奪わないよう既存 PATH に前置する。
reset_env
BIN="$WORK/bin"; rm -rf "$BIN"; mkdir -p "$BIN"
for name in afplay pw-play paplay ffplay powershell.exe aplay; do make_named_stub "$name" "$BIN"; done
PROBE_LOG="$WORK/probe.log"; : >"$PROBE_LOG"
export HITOKOE_PROBE_LOG="$PROBE_LOG"
unset HITOKOE_PLAY_CMD
SAVED_PATH=$PATH; PATH="$BIN:$PATH"; export PATH
run_hook "$STOP"
PATH=$SAVED_PATH; export PATH
chosen=$(head -n1 "$PROBE_LOG" 2>/dev/null || true)
if [ "$chosen" = "afplay" ]; then ok "C7 探索順の先頭(afplay)を使う"; else ng "C7 探索順（使われた=$chosen 期待=afplay）"; fi

# C8: 再生コマンドが1つも無い環境。exit 0 かつ標準出力に何も出さない。
# RC を親で見たいので subshell を使わず PATH を退避/復元する。
reset_env
EMPTY="$WORK/empty-bin"; rm -rf "$EMPTY"; mkdir -p "$EMPTY"
unset HITOKOE_PLAY_CMD
SAVED_PATH=$PATH; PATH=$EMPTY; export PATH
run_hook "$STOP"
PATH=$SAVED_PATH; export PATH
if [ "$RC" -eq 0 ] && [ ! -s "$WORK/out" ]; then ok "C8 再生手段皆無で exit 0・無出力"; else ng "C8 再生手段皆無で exit 0・無出力（RC=$RC）"; fi

# C9: shellcheck。voice/*.sh 全てを警告0で通す。
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck "$here"/*.sh >"$WORK/sc.out" 2>&1; then
    ok "C9 shellcheck 警告0"
  else
    ng "C9 shellcheck 警告あり"; sed 's/^/     /' "$WORK/sc.out"
  fi
else
  skp "C9 shellcheck 未インストール"
fi

# C10: NixOS 用 writeShellApplication の runtimeInputs が、フックが実際に呼ぶ外部コマンドを
#      網羅していること。nix 定義（voice/*.nix）が未作成なら赤。
NIX=""
for f in "$here"/*.nix; do [ -f "$f" ] && { NIX="$f"; break; }; done
if [ -n "$NIX" ]; then
  missing=""
  for cmd in curl mkdir rmdir sha1sum; do
    if grep -Eq "command -v $cmd|[^a-z]$cmd " "$HOOK"; then
      grep -q "$cmd" "$NIX" || missing="$missing $cmd"
    fi
  done
  if [ -z "$missing" ]; then ok "C10 runtimeInputs が呼び出しコマンドを網羅"; else ng "C10 runtimeInputs 不足:$missing"; fi
else
  ng "C10 NixOS 用 nix 定義（voice/*.nix）が未作成"
fi

# ---- C-3. 並列実行 ------------------------------------------------------------------------

# C11: 同時10回。mkdir ロックで直列化され、再生区間が重ならないこと。
#      スタブが START/END を共有ログに書き、interleave が無いことで重なりを検出する。
reset_env
SEQ_LOG="$WORK/seq.log"; : >"$SEQ_LOG"
SEQ_STUB="$WORK/seq-stub"
cat >"$SEQ_STUB" <<'STUB'
#!/usr/bin/env sh
printf 'START %s\n' "$$" >>"$HITOKOE_SEQ_LOG"
sleep 0.2
printf 'END %s\n' "$$" >>"$HITOKOE_SEQ_LOG"
STUB
chmod +x "$SEQ_STUB"
export HITOKOE_SEQ_LOG="$SEQ_LOG"
export HITOKOE_PLAY_CMD="$SEQ_STUB"
export HITOKOE_LOCK_TIMEOUT=10
i=0
while [ "$i" -lt 10 ]; do
  printf '%s' "$STOP" | "$HOOK" >/dev/null 2>&1 &
  i=$((i + 1))
done
wait
# 直列なら各行は START/END が交互（START の次は必ず同じ pid の END）。
interleaved=0
prev=""
while read -r kind pid; do
  case "$kind" in
    START) if [ -z "$prev" ]; then prev="$pid"; else interleaved=1; fi ;;
    END)   if [ "$pid" = "$prev" ]; then prev=""; else interleaved=1; fi ;;
    *) ;;
  esac
done <"$SEQ_LOG"
n_start=$(grep -c '^START' "$SEQ_LOG")
if [ "$interleaved" -eq 0 ] && [ "$n_start" -eq 10 ]; then ok "C11 10並列でも再生が重ならない"; else ng "C11 再生の重なり検出（interleaved=$interleaved starts=$n_start）"; fi
export HITOKOE_PLAY_CMD="$PLAY_STUB"

# C12: ロックを外部で保持した状態で起動。timeout 秒で諦めて exit 0、再生しない。
reset_env
mkdir -p "$HITOKOE_CACHE_DIR/.lock"   # ロックを占有
export HITOKOE_LOCK_TIMEOUT=2
t0=$(date +%s)
run_hook "$STOP"
t1=$(date +%s)
elapsed=$((t1 - t0))
rmdir "$HITOKOE_CACHE_DIR/.lock" 2>/dev/null || true
if [ "$RC" -eq 0 ] && not_played && [ "$elapsed" -le 5 ]; then
  ok "C12 ロック待ち上限超過で諦めて exit 0（${elapsed}s）"
else
  if played; then pl=yes; else pl=no; fi
  ng "C12 ロックタイムアウト（RC=$RC elapsed=${elapsed}s played=$pl）"
fi

# ---- C-4. フォールバック（L2/L3、curl 依存） ----------------------------------------------

if command -v curl >/dev/null 2>&1; then
  # C13: L3 到達不能 -> L1 generic にフォールバックして再生する。
  reset_env
  export HITOKOE_TTS_URL="http://127.0.0.1:1/tts"   # 到達不能ポート
  run_hook "$STOP"
  if played && [ "$RC" -eq 0 ]; then ok "C13 L3不通で generic にフォールバック再生"; else ng "C13 L3フォールバック"; fi

  # C14: L3 不通時の追加待ちが --max-time を超えない。
  reset_env
  export HITOKOE_TTS_URL="http://10.255.255.1/tts"  # ルーティング不能（ハングしやすい）
  export HITOKOE_MAX_TIME=2
  t0=$(date +%s); run_hook "$STOP"; t1=$(date +%s)
  if [ $((t1 - t0)) -le 6 ]; then ok "C14 L3待ちが max-time 内"; else ng "C14 L3待ちが長すぎ（$((t1 - t0))s）"; fi

  # C15: L2 キャッシュヒット時はネットワークに触れない。
  #      PATH 先頭に記録する curl スタブを置き、呼ばれないことを確認する。
  reset_env
  CBIN="$WORK/cbin"; rm -rf "$CBIN"; mkdir -p "$CBIN"
  CURL_LOG="$WORK/curl.log"; : >"$CURL_LOG"
  cat >"$CBIN/curl" <<'STUB'
#!/usr/bin/env sh
printf 'curl %s\n' "$*" >>"$HITOKOE_CURL_LOG"
exit 0
STUB
  chmod +x "$CBIN/curl"
  # キャッシュを事前に温める。HITOKOE_CACHE_KEY で basename を固定してヒットを確定させる。
  export HITOKOE_CACHE_KEY=warm
  printf 'RIFFcached' >"$HITOKOE_CACHE_DIR/warm.wav"
  export HITOKOE_TTS_URL="http://cache-should-not-be-contacted.invalid/tts"
  export HITOKOE_CURL_LOG="$CURL_LOG"
  SAVED_PATH=$PATH; PATH="$CBIN:$PATH"; export PATH
  run_hook "$STOP"
  PATH=$SAVED_PATH; export PATH
  if [ ! -s "$CURL_LOG" ]; then ok "C15 キャッシュヒットでネットワーク不発生"; else ng "C15 キャッシュヒット時に curl 呼び出しあり"; fi
else
  skp "C13 curl 未インストール"
  skp "C14 curl 未インストール"
  skp "C15 curl 未インストール"
fi

# ---- まとめ -------------------------------------------------------------------------------
printf '\n# voice: pass=%s fail=%s skip=%s\n' "$pass" "$fail" "$skip"
[ "$fail" -eq 0 ] || exit 1
[ "$pass" -gt 0 ] || exit 1
exit 0
