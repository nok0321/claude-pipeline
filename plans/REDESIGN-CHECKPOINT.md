# Redesign Checkpoint: Phase 1 検証完了 → 共食い仮説検証＋Phase 2 着手判断

Updated: 2026-04-29

## 現在地

- ブランチ: `redesign/heavy` (main は触らない、Phase 6完了時に1回マージ)
- 計画書: [REDESIGN-PLAN.md](REDESIGN-PLAN.md)
- 完了 commit:
  - `4991cdf` 計画書追加
  - `db36059` Phase 0 scaffolding (250 queries + scripts + PLAN.md skill count fix)
  - `2054bb7` Phase 0 baseline 測定結果 (15 skills, run_eval_compat.py)
  - `3f9fbeb` checkpoint: phase 0 done, phase 1 handoff doc
  - `80d9f60` Phase 0 fix: 5 skill 再測定 + scripts/README.md 全面書き換え
  - `6fbdff7` Phase 1: 15 skill 英語化 + pushy description + severity 統一
- 未 commit (作業ディレクトリのみ):
  - `evals/PHASE1.json` Phase 1 集計結果
  - `evals/PHASE1-DIFF.md` BASELINE vs PHASE1 markdown diff
  - `evals/results/phase1/` per-skill 結果 + stderr.log (15 ファイル）
  - `evals/scripts/compare.py` 比較スクリプト（新規追加, smoke-test 済）
  - `plans/REDESIGN-CHECKPOINT.md` 本ファイル

## Phase 1 eval 結果 (2026-04-28 19:41–21:08, 5044s, WORKERS=3)

`evals/PHASE1.json` / `evals/PHASE1-DIFF.md` 参照。

```
avg_trigger_rate: 0.293 → 0.238 (-0.055)
avg_pass_rate:    0.790 → 0.737 (-0.053)
skills_above_0.7:    12 →     9 (-3)
should_not_trigger_rate: 全15 skill とも 1.000 維持（near-miss 誤発火なし）
```

### 改善 9 skill (1 ファイルずつの description rewrite が機能)

| skill | trigger Δ | pass Δ |
|---|---:|---:|
| escalation | +0.233 | +0.300 |
| checkpoint | +0.134 | +0.150 |
| impl-orchestrator | +0.133 | +0.200 |
| code-review | +0.100 | +0.100 |
| dev-pipeline | +0.100 | +0.050 |
| boundary-test | +0.083 | +0.050 |
| design-phase | +0.066 | +0.050 |
| fix-with-verify | +0.066 | 0 |
| pipeline-state | +0.033 | 0 |

### 完全ゼロ化 5 skill (artifact の可能性大)

| skill | base trigger | phase1 trigger | should_trigger_rate |
|---|---:|---:|---:|
| spec-audit | 0.450 | **0.000** | 0.000 |
| spec-check | 0.400 | **0.000** | 0.000 |
| spec-fix | 0.233 | **0.000** | 0.000 |
| robust-fix | 0.300 | **0.000** | 0.000 |
| robust-review | 0.100 | **0.000** | 0.000 |

これら 5 件は **3 runs × 全クエリで一切発火していない**。stderr.log でも全件 `rate=0/3`。

### 部分悪化 1 skill

- `quick-test` 0.400 → 0.100 (-0.300, pass 18/20→12/20)

## 共食い仮説（最有力原因）

`evals/scripts/run_eval_compat.py` のトリガー判定:
```python
if isinstance(skill_arg, str) and skill_arg.lower() == target_lower:
    triggered = True
```
**指定 skill 名と完全一致したときだけ triggered=True**。model が sibling skill (例: `spec-audit` を期待した query で `spec-check` を選ぶ) を選んでも `triggered=False` で記録される。

Phase 1 rewrite で 15 skill の description を **同一テンプレ "Use this skill whenever the user wants to..."** に揃えた結果、近接プレフィックスの skill 間で文体が同質化し、disambiguation 不能になった疑い:

- `spec-audit` / `spec-check` / `spec-fix` (spec-* trio): query は同じ DESIGN/ ドメインを言及するため、3つのうち 1 つが選ばれて他 2 つは見かけ上ゼロ
- `robust-fix` / `robust-review` (robust-* duo): 同様
- `fix-with-verify` は trigger=0.383 と健在 (sibling 共食いの "勝者" 側になっている可能性)

description 長 (740–1014 chars) は broken/working 両群で重なるため、**長さは原因ではない**。

## Sub-F 実行結果 (2026-04-29)

選択肢 A を採用、`skills/spec-check/` と `skills/spec-fix/` を `.quarantine/` に `git mv` で退避して spec-audit 単独 eval を実行 (`evals/results/phase1-isolation/`)。

| 指標 | BASELINE | Phase 1 | Sub-F (phase1-iso) |
|---|---:|---:|---:|
| trigger_rate | 0.450 | 0.000 | **0.467** |
| should_trigger_rate | 0.900 | 0.000 | 0.933 |
| should_not_trigger_rate | 1.000 | 1.000 | 1.000 |

by_tag (Sub-F): explicit=1.0, implicit=0.889, casual=0.833 / near-miss-spec-check=0.0, near-miss-spec-fix=0.0, near-miss-design-phase=0.0, near-miss-robust-review=0.0, generic=0.0

**判定**: trigger_rate 0.467 ≥ 0.30 → sibling 共食い仮説**確定**。Phase 1 の description rewrite 自体は機能していて、悪化は spec-* trio と robust-* duo の sibling 共食い artifact が原因。退避状態のまま Sub-G (Phase 2 構造再編) に進行する判断 (G1 採択)。

## 判定結果と推奨方針

判定基準（CHECKPOINT 旧版）:
- avg_trigger ≥ 0.40 → Phase 2
- 0.30–0.40 → 個別 description 調整 → Phase 2
- 改善なし or 悪化 → ユーザーに Phase 1 設計に戻る判断を仰ぐ ← **形式上ここに該当 (0.238)**

ただし **悪化の主因は sibling 共食い artifact** であり、Phase 2 構造再編 (`spec-check` → `spec-audit` 統合 / `spec-fix` + `robust-fix` + `fix-with-verify` → `safe-fix` 統合) はまさにこの共食いを根絶する設計になっている。

**よって以下の 3 択をユーザーに提示する**:

| 選択肢 | 内容 | 工数 |
|--------|------|------|
| **A 推奨** | 仮説検証 1 件（spec-check と spec-fix を skills/ から一時退避→ spec-audit を単独 eval）→ trigger 復活確認 → Phase 2 着手 | +1 セッション |
| B | Phase 2 を即着手 (sibling 共食い解消が目的そのもの, eval は Phase 5 で再測定) | 0 |
| C | Phase 1 description 設計に戻す (artifact を真の悪化と解釈する場合) | 巻き戻し |

**A を推奨**: 共食い仮説が誤りなら Phase 2 やっても改善しないリスクがあるため、1 件で実証する価値が高い。検証コストは低い (1 skill × 17 queries × 3 runs ÷ 3 workers = 約 9 分 + 退避/復元手順)。

## 次セッションのサブタスク（並列実行禁止、1 つずつ確認）

> **メモ**: 並列で複数 Bash/Agent を走らせるとメッセージ上限に達したため、次セッションでは個別実行する。Monitor は 60 分上限のため、長時間 eval は再武装が必要。

### Sub-F: sibling 共食い仮説の単一 skill 検証

1. `git status` で作業ディレクトリ確認
2. `skills/spec-check/` と `skills/spec-fix/` を一時退避（git で管理されているため revert 可能）:
   ```bash
   mkdir -p .quarantine
   git mv skills/spec-check .quarantine/
   git mv skills/spec-fix .quarantine/
   ```
3. spec-audit を単独 eval:
   ```bash
   ONLY_SKILLS=spec-audit WORKERS=3 bash evals/scripts/run_baseline.sh evals/results/phase1-isolation
   ```
4. 結果確認:
   ```bash
   python evals/scripts/aggregate.py evals/results/phase1-isolation --phase phase1-iso > /tmp/iso.json
   python -c "import json; d=json.load(open('/tmp/iso.json')); print(d['skills']['spec-audit'])"
   ```
5. **判定**:
   - trigger_rate ≥ 0.30 → 共食い仮説確定 → Sub-G へ
   - trigger_rate < 0.10 → 仮説否定 → Sub-H (description 個別調整) へ

### Sub-G (Sub-F が仮説確定したとき): Phase 2 着手

`REDESIGN-PLAN.md §3.2` どおりに進める。並列禁止のため 1 操作ずつ commit:

1. 退避 skill の正式削除コミット (spec-check, spec-fix を含む):
   - **Drop**: `dev-pipeline`, `quick-test` (機能重複)
   - **Drop**: `spec-check` (spec-audit に機能統合)
   - **Drop & Merge**: `spec-fix`, `robust-fix`, `fix-with-verify` → 新 `safe-fix` skill
2. `spec-audit` SKILL.md に spec-check 機能 (impl 突合) を追記
3. `safe-fix` skill を新設（JSON Finding 入力契約、refs `references/finding.schema.json` 予定）
4. **Demote**: `pipeline-state`, `escalation` を `ARCHITECTURE.md` 補章へ吸収
5. `boundary-test`: Phase 1 で +0.083 改善・SNT=1.0 維持 → **独立維持** が妥当
6. `impl-orchestrator` の 6 ステージ → 4 ステージに簡素化 (P4)
7. `docs/MIGRATION.md` 新設

**ターゲット skill 数: 7** (spec-audit, impl-orchestrator, checkpoint, robust-review, code-review, design-phase, boundary-test) **+ safe-fix = 8**。

### Sub-H (Sub-F が仮説否定したとき): description 個別調整

1. `evals/results/phase1/spec-audit.stderr.log` の FAIL 行を読み、どんなクエリで発火しないか確認
2. spec-audit description を pushy 度を一段下げて個別 rewrite (例: テンプレ冒頭を変える)
3. 単独 eval で再測定
4. 改善するまで反復（最大 3 回）

## 維持事項

- ARCHITECTURE.md / README.md / plans/* / evals/ は日本語維持
- ユーザー出力は日本語可
- skills/ 編集中は eval 実行禁止（測定汚染防止）
- main にはマージしない（Phase 6 完了まで `redesign/heavy` 1 本）
- **新規**: 並列 Bash/Agent 実行を避ける（メッセージ上限対策）
- **新規**: 長時間 eval (>60min) は Monitor を 60 分ごとに再武装

## 引き継ぎメモ

- True baseline = 0.293 (`evals/BASELINE.json`)
- Phase 1 trigger = 0.238 だが artifact 込み (sibling 共食い)
- 9/15 skill は description rewrite 自体は機能 (escalation +0.233 が最大改善)
- should_not_trigger_rate は全 skill 1.000 維持（誤発火リスクなし）
- 完全ゼロ 5 skill のうち spec-* trio と robust-* duo は Phase 2 統合対象 → Phase 2 完了時点で構造的に解消する見込み
- `quick-test` 単独悪化 (-0.300) は Phase 2 で Drop 対象 → 個別調整しない
- `evals/scripts/compare.py` 新規 (smoke-test 済, BASELINE↔自己比較で全 Δ=0 確認)

## メッセージ上限対策（次セッション運用ルール）

- Sub-F の eval (~9 分, spec-audit 単体) は短いので block 通しで実行可
- 長時間タスクは `run_in_background` + Monitor 1 本のみ。並列の Monitor/Agent は走らせない
- 各 skill 完了通知は短い ack（または無視）でよい

---

## 新規セッション開始プロンプト

```
claude-pipeline 重量整理 Phase 1 検証完了、共食い仮説検証 → Phase 2 着手判断をお願いします。
- 作業ブランチ: redesign/heavy
- 状況: plans/REDESIGN-CHECKPOINT.md と evals/PHASE1-DIFF.md を最初に読んでください
- Phase 1 結果: avg_trigger 0.293→0.238 で形式上は「悪化」だが、5/15 skill が完全ゼロ化（spec-audit/spec-check/spec-fix/robust-fix/robust-review）= sibling 共食い artifact 仮説あり
- 最初の作業: Sub-F (共食い仮説の単一 skill 検証, 約 15 分) — spec-check/spec-fix を一時退避して spec-audit 単独 eval。CHECKPOINT に手順記載
- Sub-F 結果で:
  - trigger ≥ 0.30 → 共食い確定 → Sub-G (Phase 2 着手) を進めてよい
  - trigger < 0.10 → 仮説否定 → Sub-H (description 個別調整) に進む前にユーザー判断を仰ぐ
- 並列実行禁止 (前セッションで上限到達)。Bash/Agent は 1 つずつ完了を確認してから次へ
- skills/ 編集中は eval 実行禁止
```
