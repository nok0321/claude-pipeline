# Migration: skill 15 → 8 (Phase 2 redesign)

Phase 2 (2026-04-29) で skill 群を 15 個から 8 個に再編。
このドキュメントは旧 skill から新構成への対応表と、ユースケース別の移行ガイドを提供する。

詳細な再設計理由は [REDESIGN-PLAN.md](../plans/REDESIGN-PLAN.md)、Phase 1 (英語化) 結果は [PHASE1-DIFF.md](../evals/PHASE1-DIFF.md)、Phase 2 着手判断 (sibling 共食い検証) は [REDESIGN-CHECKPOINT.md](../plans/REDESIGN-CHECKPOINT.md)、全体設計は [ARCHITECTURE.md](../ARCHITECTURE.md) を参照。

---

## 削除 / 統合 / 補章吸収された skill

| 旧 skill | 状態 | 移行先 | 説明 |
|---------|------|--------|------|
| `dev-pipeline` | Drop | `impl-orchestrator` | 3 層オーケストレーションは未稼働 (30日 0 回)。impl-orchestrator がエントリーポイント兼務 (DESIGN/*.md 不在時は design-phase へフォールバック) |
| `quick-test` | Drop | hook (`post-edit-lint.sh`) | 差分ベース確認は post-edit-lint hook が編集後に常時実施 |
| `spec-check` | Merge | `spec-audit --mode=conformance` | spec-audit に Mode B として統合 |
| `spec-fix` | Merge | `safe-fix --mode=conformance` | safe-fix の Mode A として統合 |
| `robust-fix` | Merge | `safe-fix --mode=robust` | safe-fix の Mode B として統合 |
| `fix-with-verify` | Merge | `safe-fix --mode=adhoc` | safe-fix の Mode C として統合 |
| `pipeline-state` | Demote | `ARCHITECTURE.md §B 補章` | skill ではなく impl-orchestrator が PIPELINE-STATE.md を更新する形に |
| `escalation` | Demote | `ARCHITECTURE.md §A 補章` | Tier 1/2/3 基準は補章で集中定義、各 skill が参照 |

## 維持された skill (Phase 2 後の構成 = 8 個)

| skill | Phase 2 での変更点 |
|-------|--------|
| `impl-orchestrator` | 6 ステージ → 4 ステージに簡素化 (Setup / Implement & Verify / Review & Remediate / Iterate or Finalize)、エントリーポイント兼務、DESIGN/*.md 不在時 design-phase フォールバック、Stage 3 で safe-fix にディスパッチ |
| `spec-audit` | Mode A (cross-spec、旧 spec-audit) + Mode B (conformance、旧 spec-check) の二モード化、`--mode=cross\|conformance\|both` 引数追加 |
| `safe-fix` | **新設**。Mode A (conformance) / Mode B (robust) / Mode C (adhoc) の三モード修正、共通の検証ゲート + 失敗時 revert + 3 連続失敗で escalate |
| `robust-review` | (Phase 1 で英語化 + severity 表記統一済み) |
| `code-review` | (Phase 1 で英語化 + severity 表記統一済み) |
| `design-phase` | (Phase 1 で英語化済み) |
| `boundary-test` | (Phase 1 で英語化済み、独立維持を Phase 2 で確定) |
| `checkpoint` | (Phase 1 で英語化済み) |

---

## ユースケース別の移行コマンド

### 「設計書から実装まで自律化したい」

- 旧: `/dev-pipeline <task>` → 計画→設計→実装→テスト→報告
- 新: `/impl-orchestrator <component>` (DESIGN/*.md がある前提)。DESIGN/*.md が無ければ自動的に `design-phase` を Agent 委譲する。

### 「仕様書同士の矛盾を検出」

- 旧: `/spec-audit all`
- 新: `/spec-audit all --mode=cross` (省略可、デフォルトはユーザー語彙から推定)

### 「仕様↔実装の差分を検出」

- 旧: `/spec-check all`
- 新: `/spec-audit all --mode=conformance`

### 「spec-check の指摘を一括修正」

- 旧: `/spec-fix all --loop 3`
- 新: `/safe-fix all --mode=conformance --loop 3`

### 「robust-review の Critical/High を一括修正」

- 旧: `/robust-fix all`
- 新: `/safe-fix all --mode=robust`

### 「単発バグ修正 (revert 保証付き)」

- 旧: `/fix-with-verify <issue-description>`
- 新: `/safe-fix <issue-description> --mode=adhoc`

### 「差分ベースの素早いテスト」

- 旧: `/quick-test`
- 新: 不要 — `post-edit-lint.sh` hook が編集後に自動実行する。

### 「Finding を Tier 1/2/3 に分類」

- 旧: `/escalation classify <finding>`
- 新: skill 呼び出しは廃止。基準は [ARCHITECTURE.md §A 補章](../ARCHITECTURE.md) を参照。impl-orchestrator が Stage 3-5 で自動分類して `escalation_queue` (Tier 1) または `safe-fix` (Tier 2/3) にディスパッチする。

### 「PIPELINE-STATE.md の初期化 / 更新」

- 旧: `/pipeline-state init <task>` / `/pipeline-state update impl <row>`
- 新: skill 呼び出しは廃止。フォーマットと運用は [ARCHITECTURE.md §B 補章](../ARCHITECTURE.md) を参照。impl-orchestrator が phase 遷移時に自動更新する。手動編集も可 (セクション見出し・テーブル形式の維持必須)。

---

## 設計判断の経緯

- **3 層 → 2 層**: 旧 dev-pipeline 経由の 3 層委譲は実測で機能せず (30 日 0 回呼び出し)。impl-orchestrator が直接エントリーポイントになる方が実態に即している (PLAN P4)。
- **検査↔修正の暗黙契約 → JSON Finding 契約**: spec-fix が spec-check の出力を「察する」設計が引き継ぎ精度を下げていた。safe-fix では Finding 入力契約を informally に明文化 (Phase 3 で `references/finding.schema.json` 化予定、Phase 4 で正式)。
- **severity 軸の統一 (4 種類 → 1 種類)**: Critical/Warning/Info, S-Critical〜S-Low, Missing/Diverged/Extra/Constraint, Tier 1/2/3 が並走していた。Phase 1 で全 skill を Critical/High/Medium/Low に統一 (PLAN A3)。
- **escalation/pipeline-state の補章化**: skill としては 30 日 0 回でほぼ呼ばれていなかったが、内容は impl-orchestrator から「常に参照される」。skill ではなく ARCHITECTURE.md の参照ドキュメントとする方が責務が明確になる。
- **sibling 共食い対策**: Phase 1 evals で spec-* trio (spec-audit/spec-check/spec-fix) と robust-* duo (robust-review/robust-fix) が完全ゼロ化した原因は description 同質化による sibling 共食いだった (Sub-F isolation test で確定: spec-audit trigger 0.000 → 0.467)。Phase 2 で spec-* trio を spec-audit (二モード) に集約、robust-* duo を robust-review + safe-fix (Mode B) に分離することで構造的に解消する。

## Phase 5 で再測定する目標値

| 指標 | BASELINE | Phase 1 | Phase 5 目標 |
|------|---:|---:|---:|
| skill 数 | 15 | 15 | **8** |
| avg trigger_rate (旧 15 skill 平均) | 0.293 | 0.238 (artifact) | **+30%** (新 8 skill 平均) |
| avg pass_rate | 0.790 | 0.737 (artifact) | **≥ 0.80** |
| should_not_trigger_rate | 1.000 | 1.000 | **1.000** 維持 |
| 30 日 0 回呼び出しの遊休 skill 数 | 9 | — | **0** |
