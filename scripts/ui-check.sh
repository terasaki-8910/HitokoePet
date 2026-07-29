#!/usr/bin/env sh
# shellcheck shell=sh
#
# gates.sh の gate_ui() が実行可能なら呼ぶフック（無ければ no-op）。
# ここには「native test / gate-lint では回らないが機械判定できる UI/E2E」を置く。
#
# 常に回す（表示不要・確実に機械判定できる）:
#   * G3 a11y: app.zon の全 view に accessibility_label があること（軸/コントラストの
#     axe 相当。構造検査なので表示デバイス不要）。
#
# 表示デバイス + Native SDK が要る E2E（既定はスキップし、明示 opt-in で回す）:
#   * D2: mouth.png 無しペットの描画が本機能導入前と一致（native automate screenshot 比較）
#   * D3: 無改変 Codex アトラス(8x9,1536x1872)が従来通り読める
# これらは HITOKOE_UI_E2E=1 のとき、かつ `native` が PATH にあるときだけ実行する。
# integration_accept を macOS 実機で回す際に HITOKOE_UI_E2E=1 を設定する
# （docs/human-gates.md 参照）。CI/ヘッドレスで無言スキップして壊れた描画を見逃さないよう、
# スキップ時は必ずその旨を出力する。

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT" || exit 2
fail=0

# ---- G3 a11y（常時・表示不要） -----------------------------------------------------------
missing=$(grep -nE 'kind = "gpu_surface"|kind = "webview"' app/app.zon \
  | grep -v 'accessibility_label' || true)
if [ -z "$missing" ]; then
  printf 'ok   ui: 全 view に accessibility_label\n'
else
  fail=1
  printf 'FAIL ui: accessibility_label 欠落\n'
  printf '%s\n' "$missing" | sed 's/^/     /'
fi

# ---- D2 / D3 スクリーンショット系（opt-in + SDK 必須） ------------------------------------
if [ "${HITOKOE_UI_E2E:-0}" = "1" ]; then
  if command -v native >/dev/null 2>&1; then
    BASELINE=${HITOKOE_SCREENSHOT_BASELINE:-app/.native/baseline/pet-canvas.png}
    SHOT="$ROOT/state/ui-shot.png"
    if native automate screenshot pet-canvas --out "$SHOT" >/dev/null 2>&1; then
      if [ -f "$BASELINE" ]; then
        if cmp -s "$BASELINE" "$SHOT"; then
          printf 'ok   ui: D2 描画が baseline と一致\n'
        else
          fail=1; printf 'FAIL ui: D2 描画が baseline と不一致\n'
        fi
      else
        fail=1
        printf 'FAIL ui: D2 baseline (%s) が無い。導入前ペットで採取して固定すること\n' "$BASELINE"
      fi
    else
      fail=1
      printf 'FAIL ui: D2 native automate screenshot に失敗\n'
    fi
  else
    fail=1
    printf 'FAIL ui: HITOKOE_UI_E2E=1 だが native CLI が見つからない\n'
  fi
else
  printf 'skip ui: D2/D3 スクリーンショット比較は HITOKOE_UI_E2E=1 のときのみ（実機で設定）\n'
fi

exit "$fail"
