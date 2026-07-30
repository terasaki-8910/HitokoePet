#!/bin/sh
# shellcheck shell=sh
#
# Claude Code の Stop フックから完了を発話する（SPEC 3.3）。契約全文は voice/test.sh 冒頭。
# Codex 向けに書かれたスクリプトを流用しないこと（.type 判定は誤発火する。SPEC 3.3.1）。
# 何が起きても exit 0 で終わる — Claude Code 本体を止めない。

set -u

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

: "${HITOKOE_CACHE_DIR:=$HOME/.cache/hitokoe}"
: "${HITOKOE_WAV_DIR:=$here/wav}"
: "${HITOKOE_LOCK_TIMEOUT:=5}"
: "${HITOKOE_MAX_TIME:=3}"

TEXT='完了しました'

play_audio() {
  w=$1
  if [ -n "${HITOKOE_PLAY_CMD:-}" ]; then
    "$HITOKOE_PLAY_CMD" "$w"
  elif command -v afplay >/dev/null 2>&1; then
    afplay "$w"
  elif command -v pw-play >/dev/null 2>&1; then
    pw-play "$w"
  elif command -v paplay >/dev/null 2>&1; then
    paplay "$w"
  elif command -v ffplay >/dev/null 2>&1; then
    ffplay -nodisp -autoexit -loglevel quiet "$w"
  elif command -v powershell.exe >/dev/null 2>&1; then
    powershell.exe -NoProfile -Command \
      "(New-Object Media.SoundPlayer '$(wslpath -w "$w" 2>/dev/null || printf '%s' "$w")').PlaySync()"
  elif command -v aplay >/dev/null 2>&1; then
    aplay -q "$w"
  fi
}

payload=$(cat)

# hook_event_name の抽出だけで Codex 判別も兼ねる: Codex ペイロードは .type を持つが
# hook_event_name を持たないため、抽出は必ず空になり自然に無音で抜ける（SPEC 3.3.1）。
hook_event=$(printf '%s' "$payload" | sed -n 's/.*"hook_event_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

[ "$hook_event" = "Stop" ] || exit 0

mkdir -p "$HITOKOE_CACHE_DIR" 2>/dev/null

LOCK="$HITOKOE_CACHE_DIR/.lock"
tries=0
max_tries=$((HITOKOE_LOCK_TIMEOUT * 10))
while ! mkdir "$LOCK" 2>/dev/null; do
  tries=$((tries + 1))
  [ "$tries" -ge "$max_tries" ] && exit 0
  sleep 0.1
done
trap 'rmdir "$LOCK" 2>/dev/null' EXIT INT TERM

cache_key=${HITOKOE_CACHE_KEY:-}
if [ -z "$cache_key" ]; then
  cache_key=$(printf '%s' "$TEXT" | sha1sum | cut -d ' ' -f1)
fi
cache_wav="$HITOKOE_CACHE_DIR/$cache_key.wav"

wav=""
if [ -f "$cache_wav" ]; then
  wav=$cache_wav
elif [ -n "${HITOKOE_TTS_URL:-}" ] && command -v curl >/dev/null 2>&1; then
  tmp="$cache_wav.tmp$$"
  if curl -fsS --max-time "$HITOKOE_MAX_TIME" -G --data-urlencode "text=$TEXT" \
      -o "$tmp" "$HITOKOE_TTS_URL" 2>/dev/null && [ -s "$tmp" ]; then
    mv "$tmp" "$cache_wav" 2>/dev/null && wav=$cache_wav
  fi
  rm -f "$tmp" 2>/dev/null
fi

if [ -z "$wav" ]; then
  wav="$HITOKOE_WAV_DIR/stop.wav"
  [ -f "$wav" ] || wav="$HITOKOE_WAV_DIR/generic.wav"
fi

[ -f "$wav" ] && play_audio "$wav"

exit 0
