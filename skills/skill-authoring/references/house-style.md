# claude-pipeline house style（skill 著作規約）

[../SKILL.md](../SKILL.md) が強制する規約の正本。新規 skill が既存の skill 群と
見分けがつかず、かつドキュメント・eval に漏れなく登録される状態を「house style 準拠」と呼ぶ。
本書はメタドキュメントのため日本語、規律対象の SKILL 本体は英語（§言語）。

---

## 言語

| 対象 | 言語 |
|------|------|
| `SKILL.md`、`references/*.md`（**指示書**） | 英語 |
| README / ARCHITECTURE / plans / 本書（**メタ文書**） | 日本語 |

根拠: [feedback_skill_language]。指示書はエージェントが実行する命令でありモデルの一次言語（英語）が安定。メタ文書は人間の設計議論なので日本語。

---

## Layers（配置）

ARCHITECTURE.md §2 の 4 層のどれに置くかを最初に決める。

| 層 | 役割 | 例 |
|----|------|----|
| Layer 1 | フェーズオーケストレーター | impl-orchestrator, design-phase, task-planner |
| Layer 2 | 専門領域スキル（検査） | spec-audit, robust-review, code-review, boundary-test |
| Layer 3 | ユーティリティ | checkpoint, ship, skill-authoring |
| Layer 4 | technical-judgment subagent（`agents/`） | technical-arbiter, regression-judge, tech-comparator |

**原則**: 上位層は下位層を呼ぶ。逆方向・循環は禁止。skill→skill 直接呼び出しは不可、合成は Agent 委譲のみ（§3.1）。

---

## Frontmatter

- `name`: kebab-case、ディレクトリ名と一致。
- `description`: trigger 品質が skill の生死を決める。必須要素:
  - explicit / implicit / casual の 3 トーンの trigger 例
  - 「Trigger even when the user does not say …」節（暗黙発火）
  - 最も近い兄弟 skill との**境界線**（"for X use Y instead"）
- `argument-hint`: 受け取る引数形。
- `allowed-tools`: **最小化**。read-only judgment 系は Read/Glob/Grep のみ。
- `model`: §モデル pin に従う。

---

## モデル pin

ARCHITECTURE.md §4 の原則「出力品質を機械検証できない所は pin、できる所は float」。

| 役割 | model | 理由 |
|------|-------|------|
| opus judgment 役（orchestrator / reviewer / planner） | `claude-opus-4-8`（dated pin） | 判断品質が下流に直結 |
| 実装者 | bare `sonnet`（float） | cost 最適化＋後段ゲートで担保される唯一の役 |
| judgment subagent | `claude-sonnet-4-6`（dated pin） | 判定品質が下流に影響、頻度低 |
| 純ユーティリティ（checkpoint, ship） | 指定なし（親継承） | 軽量、呼び出し元で十分 |

更新は `grep -rE "claude-(opus\|sonnet)-4-[0-9]"` で SKILL.md / agents/*.md / .claude/settings.json / plans/*.md / CLAUDE.md を一括（**opus だけの grep は sonnet pin を取りこぼす**）。

---

## Diagrams（図の方針）★本リポの新規約

フロー的処理の表現は **「分岐・ループは Mermaid、直列はテキスト」** で使い分ける。全面 Mermaid 化はしない。

| フローの形 | 表現 | 理由 |
|-----------|------|------|
| 直列（A→B→C） | テキスト/矢印 1 行 | Mermaid のノード/エッジ定義より軽く、十分明確 |
| 分岐・ループ・並列 | Mermaid `flowchart` | テキスト散文だと構造が潰れる。散文より軽く明確 |

**3 つの留意点**:

1. **トークンは「複雑なフローだけ」勝つ**。直列を Mermaid 化するとむしろ重い。図化は分岐がある所だけ。
2. **描画される場所の落とし穴**: Mermaid は GitHub / エディタプレビューでは図になるが、**Claude Code のターミナルでは生ソースのまま**。ターミナルで即読みする quick-reference はテキスト、GitHub/エディタで読む plans/・ARCHITECTURE は Mermaid 向き。
3. **単一真実源**: SKILL 本体では図は最上位の地図、実行ディテールは散文。**図と散文に同じロジックを二重化しない**（drift してエージェントが混乱する）。

**retrofit しない**: 既存の ASCII フローは無理に Mermaid 化しない。新規の分岐フローから適用する。実例: [skills/ship/SKILL.md](../../ship/SKILL.md) の push/merge フロー。

---

## Body の薄さと references

SKILL 本体は薄く保ち（目安 ~120-200 行）、以下を `references/` に出す:

- 長いプロンプトテンプレート、テーブル、コマンド表、回復手順、出力フォーマット

本体は「何を / どの順で」、references は「具体的にどう」。

---

## Eval

- `evals/queries/<name>.json` を ~20 件作成: triggerable（explicit/implicit/casual）＋ non-triggerable（near-miss-<兄弟skill>/generic）。スキーマは既存ファイルに合わせる（`{"query","should_trigger","tag"}` 配列）。
- **skill 編集中は eval を回さない**（測定汚染防止、[evals/README.md](../../../evals/README.md)）。測定は編集が落ち着いてから。

---

## Registration（登録しない skill は存在しない）

新規 skill を作ったら同じ変更内で:

1. ARCHITECTURE.md §2 層リストに配置
2. ARCHITECTURE.md §10 責務マトリクスに 1 行（やりたいこと / skill / 補足）
3. README.md 構成 tree ＋ エントリーポイント
4. 「N skill」表記の総数を更新（README, ARCHITECTURE §2/§10/§11）

---

## Symlink truth-source

本リポが唯一の真実源。`~/.claude/` 配下にファイルを**コピーしない**（junction で参照）。構造は skills と agents で**非対称**:

- **`~/.claude/skills`** は実ディレクトリ＋**skill 毎の junction**。→ **新 skill は junction を 1 本作る必要がある**（自動では見えない。作らないと `/<name>` は "Unknown command"）。作成（管理者不要）:
  `New-Item -ItemType Junction -Path "$HOME\.claude\skills\<name>" -Target "<repo>\skills\<name>"`
- **`~/.claude/agents`** は **dir 全体が junction** → 新 agent は**自動反映**、作業不要。

作成後 Claude Code が再スキャンして skill 一覧に出る。
