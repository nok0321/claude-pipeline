# Redesign Checkpoint: Phase 2 完了 → Phase 3 着手

Updated: 2026-04-29

## 現在地

- ブランチ: `redesign/heavy` (main は触らない、Phase 6 完了時に 1 回マージ)
- 計画書: [REDESIGN-PLAN.md](REDESIGN-PLAN.md)
- 完了 commits (新しい順):
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

## Phase 1 振り返り (2026-04-28)

- `avg_trigger` 0.293 → 0.238 (形式上は悪化)
- 5 skill が完全ゼロ化: spec-audit, spec-check, spec-fix, robust-fix, robust-review
- 9 skill は description rewrite で改善 (escalation +0.233 が最大)
- `should_not_trigger_rate` 全 15 skill とも 1.000 維持

## Sub-F 検証結果 (2026-04-29)

spec-check と spec-fix を `.quarantine/` に退避 → spec-audit 単独 eval:

| 指標 | BASELINE | Phase 1 | Sub-F |
|---|---:|---:|---:|
| trigger_rate | 0.450 | 0.000 | **0.467** |
| should_trigger_rate | 0.900 | 0.000 | 0.933 |
| should_not_trigger_rate | 1.000 | 1.000 | 1.000 |

by_tag (Sub-F): explicit=1.0 / implicit=0.889 / casual=0.833 / 全 near-miss=0.0

**結論**: sibling 共食い仮説**確定**。Phase 1 description rewrite 自体は機能、悪化は spec-* trio と robust-* duo の sibling 共食い artifact のみが原因。Phase 2 構造再編 (G1) で根絶する設計通りに進めた。

---

## Phase 2 実行結果 (2026-04-29, redesign/heavy: 8 commits)

| Step | 内容 | commit | 主要成果物 |
|------|------|--------|----------|
| 0 | Phase 1 検証 + Sub-F artifacts | `8629c9e` | evals/PHASE1*, results/phase1*, scripts/compare.py |
| 1 | Drop 6 skills | `3bace02` | dev-pipeline / quick-test / spec-check / spec-fix / robust-fix / fix-with-verify を削除 |
| 2 | spec-audit に conformance 統合 | `fa2c275` | spec-audit/SKILL.md (Mode A + B、`--mode=cross\|conformance\|both`) |
| 3 | safe-fix 新設 | `f8ae499` | safe-fix/SKILL.md (3 mode、共通 gate + revert) |
| 4 | Demote 補章吸収 | `312347c` | ARCHITECTURE.md §A (Escalation framework) + §B (Pipeline state file) |
| 5 | impl-orchestrator 6→4 ステージ | `d224ac3` | Setup / Implement & Verify / Review & Remediate / Iterate or Finalize |
| 6 | MIGRATION.md | `81de55e` | docs/MIGRATION.md (15 → 8 mapping + use-case 移行ガイド) |
| 7 | CHECKPOINT 更新 | (本 commit) | Phase 3 ハンドオフ |

**skill 数: 15 → 8** (PLAN §2 ターゲット達成)

### Phase 2 後の skill 行数 (Phase 3 分割対象判定)

| skill | 行数 | P5 (≤200) | Phase 3 分割対象 |
|-------|---:|:---:|:---:|
| `checkpoint` | 68 | ✓ | — |
| `code-review` | 131 | ✓ | — |
| `spec-audit` | 190 | ✓ | — |
| `robust-review` | 209 | × | △ (微調整) |
| `safe-fix` | 236 | × | **要分割** |
| `impl-orchestrator` | 299 | × | **要分割** |
| `boundary-test` | 331 | × | **要分割** |
| `design-phase` | 346 | × | **要分割** |

合計 1810 行。Phase 3 完了時の目標: 全て ≤200 行。

---

## Phase 3 サブタスク

PLAN §3.3 通り、Progressive Disclosure を適用して全 SKILL.md を 200 行以下にする。

### Sub-I: 行数超過 4 skill の references/ 分割

優先度順 (行数の多い順):
1. **design-phase** (346 行) — 設計書生成のテンプレートを `references/templates.md` に分離、validation 詳細を `references/spec-audit-handoff.md` に
2. **boundary-test** (331 行) — 言語別の境界検出ルール (API / WASM / DB / 単位変換 / 座標系) を `references/<topic>.md` に分離
3. **impl-orchestrator** (299 行) — Stage 2 verification gate のコマンド表 + Stage 3 review prompt template を `references/gate-commands.md` と `references/review-prompts.md` に分離
4. **safe-fix** (236 行) — Mode 別 procedure を `references/<mode>.md` に分離 (`mode-conformance.md` / `mode-robust.md` / `mode-adhoc.md`)

各 skill で:
1. SKILL.md を熟読し「呼び出し時に常に必要な核」と「詳細リファレンス」を切り分け
2. 詳細を `skills/<name>/references/<topic>.md` に分離
3. SKILL.md 本文に `For X, see references/x.md` を明示 (P3)
4. SKILL.md 行数が ≤200 に収まることを確認

### Sub-J: safe-fix の Finding 入力契約定義

PLAN §3.4 (Phase 4) で正式定義予定だが、Phase 3 のうちに informal な JSON Schema を `skills/safe-fix/references/finding.schema.json` に置く価値あり。SKILL.md からは "For the formal contract, see references/finding.schema.json" で参照。

### Sub-K (オプション): robust-review 微調整

209 行 = P5 をわずか超過。短い節を削除するか小分割。優先度低 — Sub-I 完了後の余力で実施可。

### Sub-L: Phase 4 着手判断

Phase 3 完了時に Phase 4 (公式新機能取り込み: `context: fork` / `agent: parallel` / `skills:` プリロード) に進むか判断。互換性に問題があれば旧方式維持 (R2)。

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
- **Phase 2 完了時点では eval 未実施** — PLAN §3.5 (Phase 5) でまとめて再測定
- ARCHITECTURE.md `§A 補章 (Escalation framework)` と `§B 補章 (Pipeline state file)` は impl-orchestrator が常時参照する核ドキュメント。Phase 3 で skill 分割する際にも本文中の参照リンクは維持すること
- safe-fix の Mode 自動判別は SKILL.md description だけで決まる (Markdown 指示書、内部実装なし)。混乱が出たら description で disambiguation 強化
- impl-orchestrator Stage 3-2 の Agent 委譲先は `robust-review` と `spec-audit --mode=conformance`。`REVIEW-AGENTS.md` (Phase 1 時点の内容) は Phase 3 で更新を要するかもしれない — 現状は本文 placeholders で `<robust-review template, security axis>` 等と参照
- skill ディレクトリは `skills/{boundary-test,checkpoint,code-review,design-phase,impl-orchestrator,robust-review,safe-fix,spec-audit}/` の 8 個

## メッセージ上限対策

- Phase 3 は skill 編集中心で eval は走らないため、Bash/Agent の並列実行リスクは低い
- TodoWrite 推奨 (4-5 skill を順次分割するため進捗可視化が役立つ)
- 1 skill 分割ごとに 1 commit を切る (Phase 2 と同様)

---

## 新規セッション開始プロンプト

```
claude-pipeline 重量整理 Phase 2 完了、Phase 3 (Progressive Disclosure) 着手をお願いします。
- 作業ブランチ: redesign/heavy
- 状況: plans/REDESIGN-CHECKPOINT.md と docs/MIGRATION.md を最初に読んでください
- Phase 2 結果: skill 数 15 → 8 (impl-orchestrator, spec-audit, safe-fix, robust-review, code-review, design-phase, boundary-test, checkpoint)。pipeline-state/escalation は ARCHITECTURE.md §A/§B 補章へ吸収。
- Phase 3 のスコープ: PLAN §3.3。200 行超の 4 skill (design-phase 346, boundary-test 331, impl-orchestrator 299, safe-fix 236) を references/ に分割。robust-review 209 は微調整。
- 注意: skills/ 編集中は eval 禁止、main にはマージしない、Bash/Agent 並列禁止
```
