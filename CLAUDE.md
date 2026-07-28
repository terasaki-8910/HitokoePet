# Project: HitokoePet

## What this is
Claude Code のセッション状態に反応するデスクトップペット。全セッションを1匹が代表し、
作業完了を声で伝え、口パクする。Codex pet のアトラス規格と互換。

上流 [petdex](https://github.com/crafter-station/petdex) の `packages/petdex-desktop-native`
を `app/` に subtree で取り込み、既存3実装に無い4点を足す構成
（つまみ保持 / 多セッション集約 / 音声・口パク / アイドルCPU削減 + 吹き出しタップ）。

Scope in SPEC.md; pass/fail criteria in ACCEPTANCE.md.
先行調査と実測値は docs/prior-art.md。Windows 機への引き渡しは docs/handoff-windows.md。

> intake 前の初期メモにあった「electron がよさそう」「win,mac,linux で使いたい」は
> 調査の結果いずれも変更になった。現在の決定は SPEC.md 5.1 が正。

## Workflow
Driven by scripts/run.sh through gated stages (see pipeline.yaml). Do NOT skip gates.
Intake proposes per-project tools (MCP/plugins/skills): Claude proposes, I approve, I
run state/init-tools.sh myself. Never auto-install or enable tools.

## Language
Generated artifacts (code, comments, docs, commit messages, UI copy) default to 日本語.
Change here to override per project. The language I chat in is separate and unaffected.

## Commands
- Tests: `native test app`
- Lint:  `native check app --strict && scripts/gate-lint.sh`
  native check だけでは不足。理由: このアプリに .native マークアップが0個（Zig + app.zon の
  gpu_surface 直描画）で、check の a11y/バインディング検査が空振りする。no-emoji /
  design-tokens-only / a11y は scripts/gate-lint.sh で担保する（criteria 段階で作成）。
  判定内容の詳細は ACCEPTANCE.md の「判定コマンド」節。

## UI rules
IMPORTANT: colors ONLY via design tokens; never hardcode hex. No emoji in UI or source.
Shared personal UI direction: @~/.claude/rules/ui.md

## Stack recipes
If the chosen stack matches a doc under docs/recipes/ (e.g. docs/recipes/
tauri-desktop-app.md for a Tauri + pnpm desktop app), read it during intake/design and
follow its documented patterns/gotchas -- each one there cost real debugging time on a
prior project, not guessed in advance. If personal shared-infrastructure notes exist at
~/.claude/rules/infra.md (e.g. a self-hosted DB server reused across projects), check
there too -- it stays out of this repo, never committed, since this template is public.

## Do not touch
state/ (runtime), design tokens (change only via the design gate), auto-generated files.

## Git
Local only by default; do NOT push unless asked. Feature branches merge to main with --no-ff.
