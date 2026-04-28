# Redesign Checkpoint: Phase 3 完了 → Phase 4 着手

Updated: 2026-04-29

## 現在地

- ブランチ: `redesign/heavy` (main は触らない、Phase 6 完了時に 1 回マージ)
- 計画書: [REDESIGN-PLAN.md](REDESIGN-PLAN.md)
- 完了 commits (新しい順):
  - `ec1b8da` Phase 3 Step 5: tweak robust-review 209 → 177 lines (Sub-K)
  - `b9b3bce` Phase 3 Step 4: split safe-fix 236 → 150 lines + finding.schema.json (Sub-I-4 + Sub-J)
  - `654c758` Phase 3 Step 3: split impl-orchestrator 299 → 200 lines (Sub-I-3)
  - `56cc653` Phase 3 Step 2: split boundary-test 331 → 196 lines (Sub-I-2)
  - `882831c` Phase 3 Step 1: split design-phase 346 → 194 lines (Sub-I-1)
  - `48b3249` Phase 2 Step 7: update CHECKPOINT for Phase 3 handoff
  - `81de55e` Phase 2 Step 6: add docs/MIGRATION.md
  - `d224ac3` Phase 2 Step 5: simplify impl-orchestrator 6→4 stages
  - `312347c` Phase 2 Step 4: demote pipeline-state/escalation to ARCHITECTURE.md §A/§B
  - `f8ae499` Phase 2 Step 3: add safe-fix skill (3 modes)
  - `fa2c275` Phase 2 Step 2: integrate spec-check into spec-audit (Mode A + B)
  - `3bace02` Phase 2 Step 1: drop 6 obsolete skills
  - `8629c9e` Phase 2 Step 0: phase 1 verification + sub-f isolation test
  - `c0192cc` checkpoint: phase 1 done
  - `6fbdff7` Phase 1: 英語化 + pushy descriptions
  - `80d9f60` Phase 0 fix: 5 skill 再測定
  - `3f9fbeb` checkpoint: phase 0 done
  - `2054bb7` Phase 0 baseline
  - `db36059` Phase 0 scaffolding
  - `4991cdf` 計画書追加

---

## Phase 3 実行結果 (2026-04-29, redesign/heavy: 5 commits)

| Step | 内容 | commit | 主要成果物 |
|------|------|--------|----------|
| 1 | Sub-I-1: design-phase 分割 | `882831c` | references/templates.md (156), references/spec-audit-handoff.md (98) |
| 2 | Sub-I-2: boundary-test 分割 | `56cc653` | references/type-{a,b,c,d}.md + references/claude-md-boundary-table.md |
| 3 | Sub-I-3: impl-orchestrator 分割 | `654c758` | references/{implementer-prompt,gate-commands,review-prompts,final-report}.md (REVIEW-AGENTS.md は references/review-prompts.md に rename) |
| 4 | Sub-I-4 + Sub-J: safe-fix 分割 + Finding schema | `b9b3bce` | references/mode-{conformance,robust,adhoc}.md + references/output-format.md + references/finding.schema.json |
| 5 | Sub-K: robust-review 微調整 | `ec1b8da` | references/output-format.md + Phase 2 Stage 番号修正 + retired robust-fix 参照を safe-fix --mode=robust に更新 |

### Phase 3 後の SKILL.md 行数

| skill | Phase 2 後 | Phase 3 後 | P5 (≤200) |
|-------|---:|---:|:---:|
| `checkpoint` | 68 | 68 | ✓ |
| `code-review` | 131 | 131 | ✓ |
| `safe-fix` | 236 | **150** | ✓ |
| `robust-review` | 209 | **177** | ✓ |
| `spec-audit` | 190 | 190 | ✓ |
| `design-phase` | 346 | **194** | ✓ |
| `boundary-test` | 331 | **196** | ✓ |
| `impl-orchestrator` | 299 | **200** | ✓ |
| **合計** | 1810 | **1306** | — |
| **平均** | 226 | **163** | — |

PLAN §4 M3 達成: SKILL.md 平均行数 200 行以下。

### references/ 構造完備状況 (PLAN §3 P3 達成)

```
skills/
├── boundary-test/
│   ├── SKILL.md (196)
│   └── references/
│       ├── claude-md-boundary-table.md (34)
│       ├── type-a-rest-api.md (59)
│       ├── type-b-wasm.md (46)
│       ├── type-c-db.md (47)
│       └── type-d-conversion.md (60)
├── checkpoint/SKILL.md (68)
├── code-review/SKILL.md (131)
├── design-phase/
│   ├── SKILL.md (194)
│   └── references/
│       ├── spec-audit-handoff.md (98)
│       └── templates.md (156)
├── impl-orchestrator/
│   ├── SKILL.md (200)
│   └── references/
│       ├── final-report.md (51)
│       ├── gate-commands.md (69)
│       ├── implementer-prompt.md (35)
│       └── review-prompts.md (204)  ← REVIEW-AGENTS.md からの rename
├── robust-review/
│   ├── SKILL.md (177)
│   └── references/
│       └── output-format.md (53)
├── safe-fix/
│   ├── SKILL.md (150)
│   └── references/
│       ├── finding.schema.json
│       ├── mode-adhoc.md (51)
│       ├── mode-conformance.md (70)
│       ├── mode-robust.md (53)
│       └── output-format.md (58)
└── spec-audit/SKILL.md (190)
```

`scripts/` `assets/` ディレクトリは現時点では未使用。SKILL.md の責務が
Markdown 指示書のみで完結している (決定論的処理がない) ため、必要となる
段階で Phase 4 以降に追加する想定。

### Sub-J 副産物: Finding 入力契約

`skills/safe-fix/references/finding.schema.json` として JSON Schema
draft 2020-12 形式で informal 定義。Phase 4 で正式版 (検証付き) に
昇格させる予定。SKILL.md からは
"For the formal contract, see references/finding.schema.json" 形式で
参照済み。

---

## Phase 4 サブタスク

PLAN §3.4 の通り、Anthropic 公式新機能の取り込みを評価する。

### Sub-M: `context: fork` 検証

`robust-review/SKILL.md` 既に `context: fork` を frontmatter に持つ
(Phase 1 から)。impl-orchestrator Stage 3-2 の Agent 委譲先 3 reviewers
(security/robustness/spec-compliance) を全て `context: fork` 化できるか
検証する。fork が機能すれば既存の Agent 並列呼び出しを単純化できる。

### Sub-N: `agent: parallel` 検証

Stage 3-2 の "1 メッセージで Agent ×3" を `agent: parallel` フィールドに
リライトできるか試す。互換性に問題があれば旧方式 (1 メッセージ ×3 Agent)
維持 (R2 リスク緩和)。

### Sub-O: `skills:` プリロード

impl-orchestrator が code-review / robust-review / spec-audit / safe-fix
を pre-attach すれば Stage 3 開始時のロード遅延が消える可能性。
frontmatter に `skills:` フィールドが追加できるか公式仕様を確認 → 適用。

### Sub-P: Finding schema 正式化

Phase 3 Sub-J は informal な JSON Schema。Phase 4 で:
1. 上流 (spec-audit, robust-review, code-review) が schema 通りに
   出力するよう強制 (`output_format` 等の機能を使う)
2. safe-fix が起動時に schema 検証

### Phase 4 着手判断

Phase 4 は公式機能の互換性次第なので "やってみないとわからない" 部分が
多い。各 Sub について:
- 適用可: 該当 skill の frontmatter を更新、commit
- 互換性問題: 旧方式維持、CHECKPOINT に "見送り理由" を追記

成果物: 公式 frontmatter 拡張が当てはまる場所に適用 + 適用見送り理由
記録。

---

## 維持事項

- ARCHITECTURE.md / README.md / plans/* / docs/MIGRATION.md / evals/ は日本語維持
- ユーザー出力は日本語可
- skills/ 編集中は eval 実行禁止 (測定汚染防止)
- main にはマージしない (Phase 6 完了まで `redesign/heavy` 1 本)
- 並列 Bash/Agent 実行を避ける (前セッションでメッセージ上限到達)
- 長時間 eval (>60min) は Monitor を 60 分ごとに再武装

## 引き継ぎメモ

- True baseline = 0.293 (`evals/BASELINE.json`)、Phase 1 trigger = 0.238 (artifact 込み)
- **Phase 3 完了時点でも eval 未実施** — PLAN §3.5 (Phase 5) でまとめて再測定
- ARCHITECTURE.md `§A 補章 (Escalation framework)` と `§B 補章 (Pipeline state file)` は impl-orchestrator が常時参照する核ドキュメント
- Phase 3 で `skills/impl-orchestrator/REVIEW-AGENTS.md` は `skills/impl-orchestrator/references/review-prompts.md` に rename 済み (`git log --follow` で履歴追跡可能)
- Phase 3 では `scripts/` `assets/` を作らなかった: SKILL.md の責務が Markdown 指示書のみで決定論的処理がないため。Phase 4/5 で必要が出れば追加
- safe-fix の Mode 自動判別は SKILL.md description だけで決まる
- safe-fix の Finding 入力契約は `skills/safe-fix/references/finding.schema.json` (Phase 3 informal、Phase 4 で正式化)
- impl-orchestrator Stage 3-2 の Agent 委譲先は `robust-review` と `spec-audit --mode=conformance`、placeholders は `references/review-prompts.md` に集約済み

## メッセージ上限対策

- Phase 4 は frontmatter 編集中心で eval は走らない、互換性検証時のみ skill を 1 個ずつ手動呼び出して確認
- TodoWrite 推奨 (4 Sub を順次評価するため)
- 1 Sub ごとに 1 commit を切る (Phase 2 / 3 と同様)

---

## 新規セッション開始プロンプト

```
claude-pipeline 重量整理 Phase 3 完了、Phase 4 (公式新機能取り込み) 着手をお願いします。
- 作業ブランチ: redesign/heavy
- 状況: plans/REDESIGN-CHECKPOINT.md と plans/REDESIGN-PLAN.md §3.4 を最初に読んでください
- Phase 3 結果: 全 8 SKILL.md が ≤200 行 (平均 163)。references/ 構造完備。safe-fix の Finding contract を informal JSON Schema 化。
- Phase 4 のスコープ: PLAN §3.4。`context: fork` / `agent: parallel` / `skills:` プリロード / Finding schema 正式化を順に検証。互換性問題があれば旧方式維持 (R2)。
- 注意: skills/ 編集中は eval 禁止、main にはマージしない、Bash/Agent 並列禁止
```
