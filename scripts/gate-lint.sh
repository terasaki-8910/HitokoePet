#!/usr/bin/env sh
# shellcheck shell=sh
#
# 非機能ルールの静的検査。CLAUDE.md の Lint コマンド
#   native check app --strict && scripts/gate-lint.sh
# の後半。native check は .native マークアップ前提でこのアプリでは空振りするため
# （SPEC 5.2.1 / ACCEPTANCE の「判定コマンド」節）、no-emoji / design-tokens-only /
# a11y / 純粋関数テスト存在 / つまみ分岐の速度参照除去 を本スクリプトで担保する。
#
# 対応 ACCEPTANCE 項目: G1 / G2 / G3 / G4 / A6。
#
# 走査は「本プロジェクトが追加した行」(BASE..HEAD の diff の追加行) に限定する。
# BASE は subtree 取り込み基点（既定 6e205e5）。HITOKOE_BASE で上書き可。
#
# 実行時 / ビルド生成物 / バイナリは走査しない:
#   state/** dist/** node_modules/** coverage/** app/.zig-cache/** app/zig-out/**
#   および *.png *.webp *.rms *.wav と assets/**。
#
# _ 接頭辞の識別子は「意図的な未使用」とみなす規約（Zig の `_ =` 破棄 / `_name` 引数）。
# 本リポジトリのテストもこの規約に従う。

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT" || exit 2
BASE=${HITOKOE_BASE:-6e205e5}

if ! git rev-parse --verify --quiet "$BASE" >/dev/null; then
  printf 'gate-lint: BASE %s が見つかりません（HITOKOE_BASE で上書き可）。\n' "$BASE" >&2
  exit 2
fi

fail=0
note() { printf '%s\n' "$1"; }
bad()  { fail=1; printf 'FAIL %s\n' "$1"; }
good() { printf 'ok   %s\n' "$1"; }

# 追加行（先頭 + かつ +++ ヘッダを除く）を、指定 pathspec で取り出す。
added_lines() {
  # 引数はそのまま git diff の pathspec として渡す。
  git diff "$BASE"..HEAD -- "$@" | grep '^+' | grep -v '^+++'
}

CODE_PATHS='app/src app/app.zon voice scripts'
EXCLUDES=':(exclude)state/**
:(exclude)dist/**
:(exclude)node_modules/**
:(exclude)coverage/**
:(exclude)app/.zig-cache/**
:(exclude)app/zig-out/**
:(exclude)*.png
:(exclude)*.webp
:(exclude)*.rms
:(exclude)*.wav'

# ---- G1: 絵文字禁止（追加した source / UI 文字列） ----------------------------------------
# 範囲は ACCEPTANCE G1 に沿いつつ arrow/記号系を少し広げる。
EMOJI='[\x{1F000}-\x{1FAFF}\x{2600}-\x{27BF}\x{2B00}-\x{2BFF}\x{FE00}-\x{FE0F}\x{200D}]'

emoji_hits() {
  # stdin を走査し、絵文字を含む行を出力する（あれば exit 0 = ヒット扱い）。
  if command -v rg >/dev/null 2>&1; then
    rg -n --no-config -o -e "$EMOJI"
  elif command -v python3 >/dev/null 2>&1; then
    python3 - <<'PY'
import sys
# EMOJI と同じ範囲を数値で構築（ソースに絵文字リテラルを埋めない）。
ranges = [
    (0x1F000, 0x1FAFF), (0x2600, 0x27BF), (0x2B00, 0x2BFF),
    (0xFE00, 0xFE0F), (0x200D, 0x200D),
]
def is_emoji(ch):
    o = ord(ch)
    return any(lo <= o <= hi for lo, hi in ranges)
hit = False
for line in sys.stdin:
    if any(is_emoji(c) for c in line):
        sys.stdout.write(line)
        hit = True
sys.exit(0 if hit else 1)
PY
  else
    grep -nP "$EMOJI"
  fi
}

# shellcheck disable=SC2086
emitted=$(added_lines $CODE_PATHS $EXCLUDES 2>/dev/null | emoji_hits || true)
if [ -n "$emitted" ]; then
  bad "G1 絵文字が追加行に含まれる"; printf '%s\n' "$emitted" | sed 's/^/     /'
else
  good "G1 追加行に絵文字なし"
fi

# ---- G2: 色リテラル直書き禁止（追加した app/src/ の行） ------------------------------------
# 色は petdexTokens()（main.zig:209）経由のみ。ビットマスク等の非色 hex は行末に
# `// not-a-color` を付けて明示的に除外できる（設計トークンはデザインゲートで変更）。
hex_hits=$(added_lines app/src ':(exclude)app/src/**/*.png' 2>/dev/null \
  | grep -Ei '0x[0-9a-f]{6,8}|#[0-9a-f]{6}' \
  | grep -v 'not-a-color' || true)
if [ -n "$hex_hits" ]; then
  bad "G2 色リテラルの直書き（追加行）"; printf '%s\n' "$hex_hits" | sed 's/^/     /'
else
  good "G2 追加行に色リテラル直書きなし"
fi

# ---- G3: app.zon の全 view に accessibility_label ----------------------------------------
# view 宣言（gpu_surface / webview）と同じ行に accessibility_label があること。
missing_a11y=$(grep -nE 'kind = "gpu_surface"|kind = "webview"' app/app.zon \
  | grep -v 'accessibility_label' || true)
views=$(grep -Ec 'kind = "gpu_surface"|kind = "webview"' app/app.zon)
labels=$(grep -c 'accessibility_label' app/app.zon)
if [ -z "$missing_a11y" ] && [ "$views" = "$labels" ]; then
  good "G3 全 view に accessibility_label（view=$views label=$labels）"
else
  bad "G3 accessibility_label 欠落（view=$views label=$labels）"
  [ -n "$missing_a11y" ] && printf '%s\n' "$missing_a11y" | sed 's/^/     /'
fi

# ---- G4: 切り出した純粋関数それぞれに1つ以上のテスト --------------------------------------
TESTFILE=app/src/hitokoe_test.zig
if [ -f "$TESTFILE" ]; then
  miss=""
  for fn in dragState aggregate focusTarget mouthFrame parseSession parseTty; do
    grep -q "main\.$fn" "$TESTFILE" || miss="$miss $fn"
  done
  if [ -z "$miss" ]; then good "G4 純粋関数にテストあり"; else bad "G4 テストが無い純粋関数:$miss"; fi
else
  bad "G4 $TESTFILE が無い"
fi

# ---- A6: dragging 分岐から速度参照が消えていること ---------------------------------------
# `if (model.dragging)` の直後 6 行以内に vel/velocity が出現しないこと。
if command -v rg >/dev/null 2>&1; then
  a6=$(rg -n -A6 'if \(model\.dragging\)' app/src/main.zig 2>/dev/null | rg 'vel|velocity' || true)
else
  a6=$(grep -n -A6 -E 'if \(model\.dragging\)' app/src/main.zig 2>/dev/null | grep -E 'vel|velocity' || true)
fi
if [ -z "$a6" ]; then
  good "A6 dragging 分岐に速度参照なし"
else
  bad "A6 dragging 分岐に速度参照が残っている"; printf '%s\n' "$a6" | sed 's/^/     /'
fi

# ---- まとめ -------------------------------------------------------------------------------
if [ "$fail" -eq 0 ]; then
  note ""
  note "gate-lint: PASS"
  exit 0
else
  note ""
  note "gate-lint: FAIL"
  exit 1
fi
