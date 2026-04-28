# Redesign Checkpoint: Phase 0 完了 → Phase 1 着手前

Updated: 2026-04-28

## 現在地

- ブランチ: `redesign/heavy` (main は触らない、Phase 6完了時に1回マージ)
- 計画書: [REDESIGN-PLAN.md](REDESIGN-PLAN.md)
- 完了 commit:
  - `4991cdf` 計画書追加
  - `db36059` Phase 0 scaffolding (250 queries + scripts + PLAN.md skill count fix)
  - `2054bb7` Phase 0 baseline 測定結果 (15 skills, run_eval_compat.py)

## Phase 0 baseline 数値 ([../evals/BASELINE.json](../evals/BASELINE.json))

```
avg_pass_rate: 0.70 (8/15 skills above 0.7 threshold)
avg_trigger_rate: 0.19
```

| skill | trigger | should_trigger | pass | 備考 |
|---|---|---|---|---|
| boundary-test | 0.42 | 0.83 | 19/20 | 良好 |
| design-phase | 0.42 | 0.83 | 19/20 | 良好 |
| quick-test | 0.40 | 0.80 | 18/20 | 良好 |
| fix-with-verify | 0.32 | 0.63 | 18/20 | |
| checkpoint | 0.33 | 0.67 | 16/20 | |
| impl-orchestrator | 0.30 | 0.60 | 16/20 | |
| dev-pipeline | 0.18 | 0.37 | 14/20 | |
| code-review | 0.18 | 0.37 | 13/20 | |
| pipeline-state | 0.20 | 0.40 | 7/10 | |
| escalation | 0.17 | 0.33 | 6/10 | |
| **robust-fix** | **0.00** | **0.00** | 10/20 | ⚠️ rate-limit artifact 疑い |
| **robust-review** | **0.00** | **0.00** | 10/20 | ⚠️ |
| **spec-audit** | **0.00** | **0.00** | 10/20 | ⚠️ smoke 1run では 19/20 |
| **spec-check** | **0.00** | **0.00** | 10/20 | ⚠️ |
| **spec-fix** | **0.00** | **0.00** | 10/20 | ⚠️ |

## Phase 0 で得た重要な知見

1. **probe skill 戦略は使えない**: skill-creator/run_eval.py が `.claude/commands/<id>.md` (旧版) や `.claude/skills/<id>/SKILL.md` に unique probe を作る方式は、Claude (claude-opus-4-7 + claude-code 2.1.119) が prompt-injection bait と判定して**拒否**する。代わりに実 skill name で直接 trigger 検出する設計に変更した（[../evals/scripts/run_eval_compat.py](../evals/scripts/run_eval_compat.py)）

2. **Windows 互換性**: 公式の `select.select()` は file handle に対応せず WinError 10038。threading-based stdout reader で代替

3. **claude -p の Skill tool は呼ばれるが execute は error 返却**: tool_use イベントは記録されるので trigger 検出には十分

4. **既存日本語 description でも一部 skill は良好**: design-phase / boundary-test / quick-test は 80%+ の trigger rate

## Phase 1 着手前に必須のサブタスク

### Sub-A: 後半5 skill の subset 再測定 (rate-limit artifact 解消)
```bash
cd C:/Users/monum/work/private/claude-pipeline
ONLY_SKILLS="robust-fix robust-review spec-audit spec-check spec-fix" \
  WORKERS=3 \
  bash evals/scripts/run_baseline.sh evals/results/baseline-resub
# 結果を baseline/ に手動マージ → aggregate.py で BASELINE.json 再生成
# (rate limit を避けるため WORKERS=3 推奨)
```

### Sub-B: scripts/README.md 更新
- `skill-creator dependency` の記述を削除
- `run_eval_compat.py` の設計理由 (probe 廃止 + threading) を追記

## Phase 1 計画 (REDESIGN-PLAN.md §3)

**目的**: 全15 skill の SKILL.md を英語化、description を pushy 三人称形式に書き換え、trigger rate を改善。

### 作業内容
1. 全 SKILL.md frontmatter (name, description) を英語化
2. description は公式 skill-creator スタイルに：
   - 三人称 + pushy ("Use this skill whenever...")
   - 具体的なトリガー句を列挙
   - "Even if the user does not explicitly say X, use this skill..."
3. 本文も英語化、imperative grammar、二人称禁止
4. USE WHEN / SKIP 句は最大1個まで（公式仕様外なので原則ゼロが望ましい）
5. severity 軸を Critical/High/Medium/Low に統一 (現状は4種類混在)
6. MUST/NEVER の理由を明記 (黄信号回避)

### Phase 1 検証 (Phase 5 で改善幅測定の中間 baseline)
```bash
bash evals/scripts/run_baseline.sh evals/results/phase1
python evals/scripts/aggregate.py evals/results/phase1 --phase phase1 > evals/PHASE1.json
```
期待: trigger_rate 平均 0.19 → 0.40+ に改善

### 維持事項
- ARCHITECTURE.md / README.md / plans/*.md は日本語維持
- ユーザー出力は日本語可
- skills/ 編集中は eval 実行禁止 (測定汚染防止)

## 引き継ぎメモ

- Phase 0 baseline は workers=10 で rate limit を踏んだ可能性大。subset 測定は workers=3 推奨
- evals/queries/*.json は完成済み (250件)、Phase 5 で同じセットを使う
- evals/scripts/run_eval_compat.py が真の eval runner (skill-creator 依存なし、self-contained)
- memory `feedback_skill_language.md`: skill本体は英語、ARCHITECTURE/README/plans は日本語維持
- memory `feedback_batch_when_reversible.md`: バッチ実行は git管理時に提案承認のみ求める

---

## 新規セッション開始プロンプト

```
claude-pipeline の重量整理計画の Phase 1 を着手してください。
- 作業ブランチ: redesign/heavy (既に切り替え済み、main は触らない)
- 状況: plans/REDESIGN-CHECKPOINT.md と plans/REDESIGN-PLAN.md を最初に読んでください
- 最初の作業は CHECKPOINT 内「Phase 1 着手前に必須のサブタスク」(Sub-A: 後半5 skill 再測定 / Sub-B: scripts/README.md 更新) です
- その後 Phase 1 (15 skill の英語化 + pushy 化) に進みます
```
