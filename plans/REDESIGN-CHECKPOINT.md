# Redesign Checkpoint: Phase 1 完了 → Phase 1 検証＋Phase 2 着手前

Updated: 2026-04-28

## 現在地

- ブランチ: `redesign/heavy` (main は触らない、Phase 6完了時に1回マージ)
- 計画書: [REDESIGN-PLAN.md](REDESIGN-PLAN.md)
- 完了 commit:
  - `4991cdf` 計画書追加
  - `db36059` Phase 0 scaffolding (250 queries + scripts + PLAN.md skill count fix)
  - `2054bb7` Phase 0 baseline 測定結果 (15 skills, run_eval_compat.py)
  - `3f9fbeb` checkpoint: phase 0 done, phase 1 handoff doc
  - `80d9f60` **Phase 0 fix: 5 skill 再測定 + scripts/README.md 全面書き換え**
  - `6fbdff7` **Phase 1: 15 skill 英語化 + pushy description + severity 統一**

## True Baseline 数値 ([../evals/BASELINE.json](../evals/BASELINE.json))

Phase 0 fix (`80d9f60`) で rate-limit artifact 解消後の真値:

```
avg_pass_rate: 0.79 (12/15 skills above 0.7 threshold)
avg_trigger_rate: 0.293
```

| skill | trigger | should_trigger | pass | 備考 |
|---|---|---|---|---|
| spec-audit | 0.45 | 0.90 | 19/20 | 良好 |
| design-phase | 0.42 | 0.83 | 19/20 | 良好 |
| boundary-test | 0.42 | 0.83 | 19/20 | 良好 |
| spec-check | 0.40 | 0.80 | 18/20 | 良好（再測定） |
| quick-test | 0.40 | 0.80 | 18/20 | 良好 |
| checkpoint | 0.33 | 0.67 | 16/20 | |
| fix-with-verify | 0.32 | 0.63 | 18/20 | |
| impl-orchestrator | 0.30 | 0.60 | 16/20 | |
| robust-fix | 0.30 | 0.60 | 16/20 | 再測定 |
| spec-fix | 0.23 | 0.47 | 14/20 | 再測定 |
| pipeline-state | 0.20 | 0.40 | 7/10 | |
| dev-pipeline | 0.18 | 0.37 | 14/20 | |
| code-review | 0.18 | 0.37 | 13/20 | |
| escalation | 0.17 | 0.33 | 6/10 | |
| **robust-review** | **0.10** | **0.20** | 11/20 | ⚠️ 最低（再測定後も低い） |

注: robust-review は再測定後も低い → トリガー不全が真の問題。Phase 1 description rewrite で改善するかを Phase 1 eval で確認。

## Phase 1 で実施した内容 (`6fbdff7`)

### 全 15 SKILL.md + impl-orchestrator/REVIEW-AGENTS.md を書き換え

**frontmatter**:
- description を 公式 pushy 三人称形式 ("Use this skill whenever the user wants to ...") に書き換え
- 各 skill に 4–7 個の具体的なトリガーフレーズを列挙
- "Trigger even when the user does not say `<skill-name>`" 行を追加（implicit triggers のため）
- SKIP 句は最大 1 個に削減（大半はゼロ） — A1 準拠

**本文**:
- 全セクションを英語の imperative grammar に翻訳。二人称代名詞排除 — A5 準拠
- MUST / NEVER に **Why:** 注記追加 — A6 準拠
  - 例: impl-orchestrator Stage 1 "Component Mapping 不在ならエスカレーション" の理由（ハードコード排除原則）
  - 例: fix-with-verify "1 ファイルずつ修正" の理由（リバート粒度）
  - 例: 設計変更ループ上限 1 回の理由（要件誤りシグナル）

**severity 統一** — A3 準拠:
- `S-Critical / S-High / S-Medium / S-Low` (robust-review, robust-fix) → `Critical / High / Medium / Low`
- `Critical / Warning / Info` (code-review, spec-audit) → `Critical / High / Medium / Low` (Warning ≈ High, Info ≈ Low, 必要に応じ Medium 追加)
- escalation の `Tier 1 / 2 / 3` は **severity と直交する別軸** として温存
- spec-check の `Missing / Diverged / Extra / Constraint` は **diff 種別** として温存（severity は新たに上乗せ）

**REVIEW-AGENTS.md**:
- impl-orchestrator が Stage 4 で `{target_files}` 等を展開して reviewer agent に渡すテンプレート → 英語化 + severity 統一
- これを残すと impl-orchestrator SKILL.md の severity 表記と reviewer agent 出力が乖離するため必須対応

### 検証

- `grep [\p{Hiragana}\p{Katakana}\p{Han}] skills/` → empty（日本語残存なし）
- `grep -E 'S-Critical|S-High|S-Medium|S-Low' skills/` → empty
- ARCHITECTURE.md / README.md / plans/* / evals/ は **日本語維持** (言語ポリシー §1.3)

### 行数（参考、Phase 3 で 200 超を分割予定）

| 範囲 | 件数 | 該当 |
|------|------|------|
| ≤ 100 | 3 | checkpoint(68), quick-test(71), fix-with-verify(94) |
| 101–200 | 7 | code-review, escalation, pipeline-state, robust-fix, spec-audit, spec-fix, spec-check |
| 201–300 | 2 | robust-review(209), dev-pipeline(243) |
| 301+ | 3 | boundary-test(331), design-phase(346), impl-orchestrator(356) |

→ 5 file が Phase 3 (Progressive Disclosure) で `references/` 分割対象。

## Phase 1 着手前に必須のサブタスク（完了済み）

- [x] **Sub-A**: 5 skill 再測定 (rate-limit artifact 解消) → `80d9f60`
- [x] **Sub-B**: scripts/README.md 全面書き換え → `80d9f60`

## 次のサブタスク

### Sub-C: Phase 1 trigger rate 測定 (必須)

```bash
cd C:/Users/monum/work/private/claude-pipeline
WORKERS=3 bash evals/scripts/run_baseline.sh evals/results/phase1
python evals/scripts/aggregate.py evals/results/phase1 --phase phase1 > evals/PHASE1.json
```

**重要**: WORKERS=3 を使う（Phase 0 で WORKERS=10 が rate-limit を踏んだ）。
所要時間: 約 45-60 分（15 skill × 17 queries × 3 runs ÷ 3 workers）。

**期待値**: avg_trigger_rate **0.293 → 0.40+**
- 旧 CHECKPOINT の "0.19 → 0.40+" は汚染ベースライン基準。真値ベースだと若干緩めの目標
- Phase 5 で +30% 平均改善 (M1) を狙う最終目標は変わらず

### Sub-D: BASELINE vs PHASE1 比較

```bash
# 簡易比較（差分が見やすいように整形）
python -c "
import json
b = json.load(open('evals/BASELINE.json'))
p = json.load(open('evals/PHASE1.json'))
print(f'{'skill':25} {'baseline':>10} {'phase1':>10} {'delta':>10}')
for sk in sorted(b['skills']):
    bv = b['skills'][sk]['trigger_rate_overall']
    pv = p['skills'][sk]['trigger_rate_overall']
    d = pv - bv
    flag = '↑↑' if d >= 0.20 else ('↑' if d > 0 else ('↓' if d < 0 else '='))
    print(f'{sk:25} {bv:>10.3f} {pv:>10.3f} {d:>+10.3f} {flag}')
print(f'{'AVERAGE':25} {b[\"summary\"][\"avg_trigger_rate\"]:>10.3f} {p[\"summary\"][\"avg_trigger_rate\"]:>10.3f} {p[\"summary\"][\"avg_trigger_rate\"] - b[\"summary\"][\"avg_trigger_rate\"]:>+10.3f}')
"
```

判定基準:
- avg_trigger 0.40 以上 → Phase 1 成功 → Phase 2 着手
- avg_trigger 0.30–0.40 → 部分成功 → 個別の悪化 skill を特定して description を再調整
- avg_trigger 改善なし or 悪化 → description rewrite に問題 → 設計に戻る

### Sub-E: 個別悪化 skill の特定（PHASE1 < BASELINE のもの）

Phase 1 description は **pushy 化で trigger rate を上げる** 想定だが、副作用として **near-miss を誤発火** するリスクがある。
`should_not_trigger_rate`（near-miss 識別精度）が 0.95 を切る skill は description を緩める方向で調整。

## Phase 2 計画 (REDESIGN-PLAN.md §3.2)

Phase 1 検証 OK 後に着手。**構造再編** で 15 skill → 7-8 skill。

| 操作 | 対象 |
|------|------|
| **Drop** | dev-pipeline (impl-orchestrator が前提条件チェック付きエントリ兼務), quick-test (post-edit-lint hook と機能重複) |
| **Merge spec** | spec-check の機能を spec-audit に取り込み、spec-check 削除 |
| **New `safe-fix`** | spec-fix + robust-fix + fix-with-verify を統合（JSON Finding を入力契約） |
| **Demote** | pipeline-state, escalation を ARCHITECTURE.md 補章として吸収 |
| **boundary-test** | 単独維持 vs impl-orchestrator 統合を Phase 1 trigger rate を見て決定 |
| impl-orchestrator | 6→4 ステージに簡素化 (P4) |

成果物: `skills/` 配下が 7-8 個に整理、`docs/MIGRATION.md` 新設。

## 維持事項

- ARCHITECTURE.md / README.md / plans/* / evals/ は日本語維持
- ユーザー出力は日本語可
- skills/ 編集中は eval 実行禁止（測定汚染防止）
- main にはマージしない（Phase 6 完了まで `redesign/heavy` 1 本）

## 引き継ぎメモ

- **真の Phase 0 baseline は 0.293**（旧記録 0.194 は汚染ベースライン）
- robust-review は再測定後も `trigger_rate=0.10` と最低 → Phase 1 description で改善するかが重要なシグナル
- Phase 1 description は **公式 pdf/pptx/xlsx skill のスタイル**（"Use this skill whenever..." + concrete triggers + "Trigger even if..."）に倣った
- `evals/queries/*.json` は Phase 0 で完成済み（250 件）。Phase 1, Phase 5 で同じセットを使う
- `evals/scripts/run_eval_compat.py` が真の eval runner（skill-creator 依存なし）
- memory `feedback_skill_language.md`: skill本体は英語、ARCHITECTURE/README/plans は日本語維持
- memory `feedback_batch_when_reversible.md`: バッチ実行は git管理時に提案承認のみ求める
- 5 SKILL.md (>200 行) が Phase 3 で `references/` 分割対象

---

## 新規セッション開始プロンプト

```
claude-pipeline の重量整理計画の Phase 1 検証 → Phase 2 着手をお願いします。
- 作業ブランチ: redesign/heavy (既に切り替え済み、main は触らない)
- 状況: plans/REDESIGN-CHECKPOINT.md と plans/REDESIGN-PLAN.md を最初に読んでください
- 最初の作業は CHECKPOINT 内「次のサブタスク」(Sub-C: Phase 1 trigger rate 測定 / Sub-D: BASELINE vs PHASE1 比較 / Sub-E: 個別悪化 skill の特定) です
- 測定中は skills/ 編集禁止
- Sub-C–E の判定で avg_trigger_rate ≥ 0.40 なら Phase 2 (構造再編 15→7-8 skill) に進みます
- 0.30–0.40 の場合は悪化 skill の description を個別調整してから Phase 2
- 改善なし or 悪化の場合は Phase 1 設計に戻る判断をユーザーに仰いでください
```
