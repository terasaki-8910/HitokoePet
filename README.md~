<div align="right">

[![English](https://img.shields.io/badge/lang-English-2b7489?style=flat-square)](./README.en.md)

</div>

# claude-pipeline-template

Claude Code で **1 つのプロジェクト**を、ざっくりした案からゲート付き・テスト済みの
成果物まで進めるための **GitHub テンプレートリポジトリ**。複数プロジェクトは別リポジトリ
として並列に走らせるだけでよい（共有状態なし）。Ralph 式の反復は build ステージの内部に
だけ、テストで束ねた有界ループとして使う（無人の朝までグラインドではない）。

## ファイル構成
- `pipeline.yaml`  — 宣言的な仕様（単一の真実）。run.sh と同期を保つこと。
- `scripts/run.sh` — POSIX ドライバ本体：段階を進め、人間ゲートで通知して停止。
- `scripts/gates.sh` — 機械ゲート（テスト / lint / ui）。プロジェクトごとに調整。
- `prompts/0X-*.md` — 各段階の「契約」。
- `CLAUDE.md`      — プロジェクト記憶（グローバルの UI ルールを取り込む）。
- `.claude/settings.json` — スコープ付き権限（安全性の項参照）。素の skip-permissions は使わない。
- `Makefile`       — 任意の短縮（`make plan`, `make build` …）。

## マシン全体の一度きり設定（このリポジトリ外）
1. git の co-author 行を全プロジェクトで止める：
   `~/.claude/settings.json` → `{ "includeCoAuthoredBy": false }`
2. 全プロジェクト共通の UI 方針：
   `docs/ui-rules.starter.md` を `~/.claude/rules/ui.md` にコピーして継続的に洗練する。
   `~/.claude/CLAUDE.md` と `~/.claude/rules/` は全プロジェクトで読み込まれる。フロントエンドの
   glob にスコープすれば UI 作業時のみ読み込まれる（rules ディレクトリのドキュメント参照）。

## プロジェクトごとの使い方
1. GitHub でこのリポジトリを Template repository に設定（Settings → Template repository）。
2. 新規プロジェクトごとに Use this template → 新リポジトリ → clone。
3. `CLAUDE.md` に**プロジェクト名と一行の目的だけ**手で記入（test/lint コマンド欄は空でよい
   ——intake がスタック確定後に埋め、あなたが確認する）。生成物の言語は `Language` 欄（既定=
   英語、会話言語とは別）で指定。UI があるなら `touch state/has_ui`。
4. パイプライン実行：`sh scripts/run.sh all`（段階ごとにも：`… intake` など）。
   intake は**案内型**：一行のざっくり指示から始め、Claude が各論点で選択肢を出し、あなたは
   選ぶだけ（重い判断が先・細部は後）。合わなければ自分で指定も可。
5. intake の最後に**プロジェクト別の道具提案**（MCP/プラグイン/スキル）が出る。承認すると
   `state/TOOLING.md`（提案書）と `state/init-tools.sh`（導入コマンド）が生成される。入れる場合は
   中身を確認し `sh state/init-tools.sh` を**自分で**実行する（Claude は自動導入しない）。intake は
   **プロジェクト固有の .gitignore 追加**も提案する（大きな fixture・生成物を build の `git add -A`
   がコミットしないように）。
6. （任意）`sh scripts/run.sh slim` — このプロジェクトの git から**パイプライン機構**（`scripts/`,
   `prompts/`, `pipeline.yaml`, `Makefile`, `docs/ui-rules.starter.md`）を untrack + gitignore し、
   **git に成果物だけ**を残す（機構はディスクに残り実行可）。仕上げに `git commit`。※テンプレート
   本体では拒否される（Use this template で配布するため全追跡が必須）。

## 段階（ゲート）
0 intake（人間・1回：仕様確定＋プロジェクト別の道具提案 → `TOOLING.md` / `init-tools.sh`）／
1 criteria（人間）／2 design_gate（UI のみ・人間・1回）／
3 plan（目視）／4 build（機械ゲート・worktree・既定は逐次）／
5 feature_accept（機械＋軽い人間・ローカルマージ）／6 integration_accept（機械＋人間・1回）

## 進捗確認・復旧
- `sh scripts/run.sh status` — 完了したステージ（`[x]`）と、**次に進むコマンド**を表示。各
  ステージは人間ゲートを通った時点で `state/done/<stage>` に記録される（UI 無しなら design は
  `[-] n/a`）。「どこまで終わって、次に何を打てばいいか」が一目で分かる。
- ゲート失敗時は**その場で修復メニュー**:`1) auto`（直るまで自動修復）/ `2) hybrid`〔既定・Enter・
  数回で人間へ〕/ `3) stop`（**対話 Claude をエラー付きで起動**して自分で直す→`/exit` 後に再判定）。
  auto/hybrid は失敗出力をエージェントに渡して直させる（盲目リトライでなく実デバッグ）。無進捗で自動
  停止、テストを弱める/消すのは禁止。
- 完了（DONE）時に **NEXT STEPS** を出力:設定すべき env/シークレット（SPEC から抽出）・外部ツール・
  使い方（README 参照）・integration で skip された未検証テストの回し方。
- `sh scripts/run.sh reset` — **失敗からの復旧**。build の worktree・`feature/*` ブランチ・
  チェックポイントを消し、仕様/基準/計画（SPEC・ACCEPTANCE・PLAN・tests・gates）は残す。→
  `from build` で作り直せる。

## 任意コマンド：先行事例調査（build 前）
`sh scripts/run.sh survey` — 一から作る前に、似た既存プロジェクトを**実検索**して提示（記憶
からの列挙は禁止＝幻覚回避）。`all` には含まない。選択は「一から作る（既定）／既存を base に
採用」。base 採用時は `state/BASE.md` に記録するがコードは複製しない——採用しても通常の
criteria/build ゲートを通し、ライセンスも自分で満たす（"存在するだけ"では信用しない）。
**要件**：WebSearch の有効化が必要（現状 `.claude/settings.json` は WebFetch を deny）。

## 任意コマンド：自動化提案（build 後）
`sh scripts/run.sh recommend` — **完成したコード**を解析し、Hooks/MCP/subagent/skill を**提案**
（実装はせず `state/RECOMMENDATIONS.md` に出力、あなたが採否を決める）。`claude-code-setup`
プラグインがあればその `automation-recommender` スキルを使い、無ければ内蔵で代替。**DONE で自動
実行**される（`RECOMMEND=0` で無効化）。コードが無いと意味が無いので intake ではなく完成後。

## モデル
仕様・基準 = Opus、design・build = Sonnet。段階ごとに環境変数で指定
（`MODEL_BUILD=sonnet` など）。`opus-plan` は対話モードでありヘッドレスのモデル文字列では
ないので、ヘッドレスの plan では `MODEL_PLAN` は実在モデルのまま。Fable は**手動エスカレー
ションのみ**（ブロッカーを `state/BLOCKED-*.md` に書いて手で上げる）。一部の Fable クエリは
Opus に迂回し可用性・セーフガードの注意もあるため、自動化はしない。

## 安全性（重要）
- 各機能は隔離された `git worktree` でビルドする。この隔離が安全境界。
- `.claude/settings.json` はスコープ付き許可リストを与え、push と rm -rf を deny する。
  本番マシンで `--dangerously-skip-permissions` を使わないこと。使う場合も worktree /
  サンドボックス内に限定する。
- 既定では push しない — すべてローカル git。

## claude の起動（移植可能・全プロジェクト共通）
run.sh は文書化された安定形で claude を呼ぶ。マシン依存の調整は不要:
- 対話（intake）: `claude "<プロンプト>"` — REPL を開き、それを最初のメッセージとして送る。
- ヘッドレス（criteria/plan/build 等）: `claude -p "<プロンプト>"`。
権限は `.claude/settings.json` のスコープ付き許可リストで統一。将来 CLI がこの中核フラグを
変えた時だけ、`claude_interactive` / `claude_run` の1箇所を直す（マシンごとではなくテンプレ
1箇所の修正）。`--model` は段階別に環境変数で渡す。

## 実行の環境変数（見ながら回す / コスト制御）
- `INTERACTIVE=1` — criteria/design/plan を**ヘッドレスでなく Claude Code の TUI** で開く。
  進捗が見え、通知が来て、途中で指示を変えられ、`/exit` で次段へ進む。既定 0 はヘッドレス
  （無人）。**intake は常に TUI、build は常にヘッドレス**（機能ごとに worktree で回すため）。
  例：`INTERACTIVE=1 sh scripts/run.sh from plan`
- `REPAIR_ITERS`（既定 4）/ `REPAIR_HARD_CAP`（既定 12）— ゲート失敗時の自動修復の試行上限
  （hybrid は REPAIR_ITERS 回で人間へ、絶対上限は HARD_CAP）。各試行は有料実行。
- `PARALLEL=1` — build を並列化（既定は逐次＝コストと停止性で安全）。
- `PERMISSION_MODE`（既定 acceptEdits）— ヘッドレスの権限モード。
- `MODEL_*`（INTAKE/CRITERIA/DESIGN/PLAN/BUILD）— 段階別モデル。
- 入力待ちの通知：人間ゲート（承認・plan の Enter 待ち）で macOS 通知を鳴らす。**ターミナルが
  最前面の時は抑制**（見ているので不要）。常に鳴らすなら `NOTIFY_ALWAYS=1`。
