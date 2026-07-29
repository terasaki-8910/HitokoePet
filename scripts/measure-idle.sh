#!/usr/bin/env sh
# shellcheck shell=sh
#
# ACCEPTANCE E（SPEC 3.5）のアイドル時 CPU / RSS 計測。macOS 実機で、ペット表示・無操作・
# セッション無しの状態を 60 秒放置し、CPU 時間の増分と RSS を測る。
#
#   E1: 60 秒の CPU 時間増分 < HITOKOE_E1_MAX_CPU_S 秒
#   E2: RSS < HITOKOE_E2_MAX_RSS_MB MB
#   E3: 1コア占有率がベースライン 22.7%（上流 v0.3.1）未満
#
# E1/E2 の閾値は S5（CPU 原因特定）後に criteria 段階で確定する <TBD>。未設定なら赤にする
# （閾値の空白を「合格」に読み替えないため）。E3 のみ spike 前でも成立する。
#
# 使い方: ペットを起動しておき、`scripts/measure-idle.sh` を実行する。
#   HITOKOE_E1_MAX_CPU_S=<秒>  HITOKOE_E2_MAX_RSS_MB=<MB>  を確定後に設定する。

set -u

PROC=${HITOKOE_PROC:-petdex-desktop-native}
WINDOW=${HITOKOE_WINDOW_S:-60}
BASELINE_PCT=22.7   # 上流 v0.3.1 実測（2026-07-28, macOS）。E3 の基準。

fail=0
bad()  { fail=1; printf 'FAIL %s\n' "$1"; }
good() { printf 'ok   %s\n' "$1"; }

pid=$(pgrep -x "$PROC" 2>/dev/null | head -n1 || true)
if [ -z "${pid:-}" ]; then
  printf 'measure-idle: プロセス %s が見つかりません。ペットを起動してから実行してください。\n' "$PROC" >&2
  exit 2
fi

# cputime("MM:SS" or "HH:MM:SS") を秒に。
cputime_s() {
  ct=$(ps -o cputime= -p "$1" 2>/dev/null | tr -d ' ' || true)
  [ -n "$ct" ] || { echo 0; return; }
  printf '%s' "$ct" | awk -F: '{
    n=NF; s=0; m=1;
    for (i=n; i>=1; i--) { s += $i * m; m *= 60 }
    printf "%d", s
  }'
}
rss_mb() {
  kb=$(ps -o rss= -p "$1" 2>/dev/null | tr -d ' ' || true)
  [ -n "$kb" ] || { echo 0; return; }
  echo $((kb / 1024))
}

c0=$(cputime_s "$pid")
sleep "$WINDOW"
c1=$(cputime_s "$pid")
rss=$(rss_mb "$pid")
delta=$((c1 - c0))
# 1コア占有率 (%) = delta / window * 100。小数比較は awk。
pct=$(awk -v d="$delta" -v w="$WINDOW" 'BEGIN{ printf "%.1f", (w>0)? d/w*100 : 0 }')

printf 'measure-idle: pid=%s window=%ss cpu_delta=%ss rss=%sMB cpu_pct=%s%%\n' \
  "$pid" "$WINDOW" "$delta" "$rss" "$pct"

# E3: ベースライン未満（spike 前でも成立）。
below=$(awk -v p="$pct" -v b="$BASELINE_PCT" 'BEGIN{ print (p < b) ? "1" : "0" }')
if [ "$below" = "1" ]; then good "E3 CPU がベースライン $BASELINE_PCT% 未満（$pct%）"; else bad "E3 CPU がベースライン以上（$pct%）"; fi

# E1: CPU 時間増分の閾値（S5 後に確定）。
if [ -n "${HITOKOE_E1_MAX_CPU_S:-}" ]; then
  if [ "$delta" -lt "$HITOKOE_E1_MAX_CPU_S" ]; then good "E1 CPU 増分 < ${HITOKOE_E1_MAX_CPU_S}s（${delta}s）"; else bad "E1 CPU 増分 >= ${HITOKOE_E1_MAX_CPU_S}s（${delta}s）"; fi
else
  bad "E1 閾値 HITOKOE_E1_MAX_CPU_S が未設定（S5 後に確定する <TBD>）"
fi

# E2: RSS 閾値（S5 後に確定）。
if [ -n "${HITOKOE_E2_MAX_RSS_MB:-}" ]; then
  if [ "$rss" -lt "$HITOKOE_E2_MAX_RSS_MB" ]; then good "E2 RSS < ${HITOKOE_E2_MAX_RSS_MB}MB（${rss}MB）"; else bad "E2 RSS >= ${HITOKOE_E2_MAX_RSS_MB}MB（${rss}MB）"; fi
else
  bad "E2 閾値 HITOKOE_E2_MAX_RSS_MB が未設定（S5 後に確定する <TBD>）"
fi

exit "$fail"
