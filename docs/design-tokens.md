# design-tokens — Stage 2 design gate 成果物

Stage 2 の指示「design tokens を real file として出す」への対応。**このプロジェクトは
新しいトークンを1つも定義しない。** design_brief.md 4項の通り、色は upstream の
`petdexTokens()`（`app/src/main.zig:209`、`canvas.DesignTokens.theme()` を薄くラップ）
経由のみで、追加コードに色リテラルを書くことは `scripts/gate-lint.sh` の G2 が機械的に禁止する。

この文書は新しいトークン源ではなく、**upstream から読み取った現在値のスナップショット**
（dark テーマ、`Model.dark` の既定値）と、既存UIが既に使っている spacing/type の語彙を
記録するだけ。値がズレたら upstream 側（`main.zig:209-238`）を正とする。

## 1. カラートークン（`petdexTokens`, dark 分岐 = 既定 `model.dark = true`）

| token | 値 | 用途（既存コードでの使用箇所） |
| --- | --- | --- |
| `background` | `rgb(12,12,15)` | ウィンドウ背景 |
| `surface` | `rgb(25,25,28)` | パネル/リスト行の背景（`style_tokens.background = .surface`） |
| `surface_subtle` | `rgb(45,45,48)` | サブトルな塗り分け |
| `surface_pressed` | `rgb(22,27,67)` | 選択中/押下中の強調背景 |
| `text` | `rgb(237,237,238)` | 通常テキスト |
| `text_muted` | `rgb(156,158,168)` | 説明文（`style_tokens.foreground = .text_muted`） |
| `accent` | `rgb(137,163,255)` | ブランドアクセント（`accentOverrides` 経由で二次色にも波及） |
| `destructive` | `rgb(250,105,94)` | 破壊的操作（本プロジェクトでは未使用） |

`high_contrast` が有効なとき、これらの上書きは一切適用されず upstream の
`.theme(.{ .contrast = .high, ... })` がそのまま出る（`main.zig:216`）。この分岐にも
このプロジェクトは触らない。

light 分岐（`model.dark = false`）の値は `main.zig:227-236` に同じ構造で存在するが、
既定は dark なので、下記の representative screen は dark のみを対象にする。

## 2. spacing / type の語彙（`settingsView`, `main.zig:1924` 以降で確立済み）

新しいUI（後述の Voice トグル）はここに無い値を発明しない。既存の "Show messages" 行
（`main.zig:2012-2024`）をそのまま複製するのが唯一の正解。

| 語彙 | 値 | 出典 |
| --- | --- | --- |
| section heading | `ui.text(.{ .size = .lg }, ...)` | "Pets" / "Agents" / "Appearance" 見出し |
| panel | `ui.el(.panel, .{ .style_tokens = .{ .background = .surface, .radius = .md } })` | 設定カード1枚 |
| row padding / gap | `12` / `12`（`cross = .center`） | パネル内の row |
| label | `ui.text(.{}, "...")`（既定サイズ） | 行タイトル（例: "Show messages"） |
| description | `ui.text(.{ .size = .sm, .style_tokens = .{ .foreground = .text_muted } }, "...")` | 行の説明文 |
| toggle control | `ui.el(.switch_control, .{ .selected = ..., .on_toggle = ..., .semantics = .{ .label = "..." } })` | ON/OFF |
| section spacer | `ui.el(.stack, .{ .height = 10 }, .{})` | セクション間の空き |

## 3. このゲートで承認対象になる「新しい画面」は1つだけ

design_brief.md 3項が禁止リストで新規UIを絞り込んだ結果、**このプロジェクトが足す
唯一のUI要素は「音声 ON/OFF」トグル**（Settings → Appearance、既存の "Show messages" 行の
直下）。それ以外（口パクの個別トグル、感度スライダー、集約状態の表示、CPU削減インジケータ）
は明示的に作らない。

`mouth.png` オーバーレイ（design_brief 2項）と つまみ保持ポーズ（design_brief 1項）は
トークンを使わないラスタ/モーションの決定であり、この「デザイントークンで作る画面」ゲート
の対象外（すでに design_brief.md で決定済み・変更しない）。

→ representative screen: [design-reference-screen.html](design-reference-screen.html)
