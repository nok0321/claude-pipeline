# Migration: skill 15 → 8 (Phase 2) → 7 (Phase 6 Sub-V Option A)

Phase 2 (2026-04-29) で skill 群を 15 個から 8 個に再編、Phase 6 Sub-V (2026-05-23) で `safe-fix` を廃止し **7 skill 構造**に確定。
このドキュメントは旧 skill から新構成への対応表と、ユースケース別の移行ガイドを提供する。

詳細な再設計理由は [REDESIGN-PLAN.md](../plans/REDESIGN-PLAN.md)、Phase 1 (英語化) 結果は [PHASE1-DIFF.md](../evals/PHASE1-DIFF.md)、Phase 5 (POST eval) 結果は [POST-DIFF.md](../evals/POST-DIFF.md)、Phase 2 着手判断 (sibling 共食い検証) と Phase 6 引き継ぎは [REDESIGN-CHECKPOINT.md](../plans/REDESIGN-CHECKPOINT.md)、全体設計は [ARCHITECTURE.md](../ARCHITECTURE.md) を参照。

---

## 削除 / 統合 / 補章吸収された skill

| 旧 skill | 状態 | 移行先 | 説明 |
|---------|------|--------|------|
| `dev-pipeline` | Drop (Phase 2) | `impl-orchestrator` | 3 層オーケストレーションは未稼働 (30日 0 回)。impl-orchestrator がエントリーポイント兼務 (DESIGN/*.md 不在時は design-phase へフォールバック) |
| `quick-test` | Drop (Phase 2) | hook (`post-edit-lint.sh`) | 差分ベース確認は post-edit-lint hook が編集後に常時実施 |
| `spec-check` | Merge (Phase 2) | `spec-audit --mode=conformance` | spec-audit に Mode B として統合 |
| `spec-fix` | Merge (Phase 2) → Inline (Phase 6) | `impl-orchestrator` Stage 3 (`references/conformance-fix.md`) | Phase 2 で safe-fix Mode A、Phase 6 Sub-V Option A で impl-orchestrator inline 化 |
| `robust-fix` | Merge (Phase 2) → Inline (Phase 6) | `impl-orchestrator` Stage 3 (`references/robust-fix.md`) | Phase 2 で safe-fix Mode B、Phase 6 Sub-V Option A で impl-orchestrator inline 化 |
| `fix-with-verify` | Merge (Phase 2) → Drop (Phase 6) | Claude 直接 (Edit + Bash gate) | Phase 2 で safe-fix Mode C、Phase 6 Sub-V で adhoc は廃止 (Claude が直接ハンドリング) |
| `safe-fix` | **Drop (Phase 6 Sub-V Option A)** | `impl-orchestrator` Stage 3 inline | Phase 5 で trigger 0.000、routing 構造由来。Mode A/B は impl-orchestrator/references/ へ移動、Mode C は廃止 |
| `pipeline-state` | Demote (Phase 2) | `ARCHITECTURE.md §B 補章` | skill ではなく impl-orchestrator が PIPELINE-STATE.md を更新する形に |
| `escalation` | Demote (Phase 2) | `ARCHITECTURE.md §A 補章` | Tier 1/2/3 基準は補章で集中定義、各 skill が参照 |

## 維持された skill (Phase 6 後の構成 = 7 個)

| skill | Phase 2-6 での変更点 |
|-------|--------|
| `impl-orchestrator` | 6 ステージ → 4 ステージに簡素化 (Phase 2)、Stage 3 で safe-fix にディスパッチ → Phase 6 Sub-V Option A で inline 化 (conformance/robust 修正ロジックを `references/` に格納)。エントリーポイント兼務、DESIGN/*.md 不在時 design-phase フォールバック |
| `spec-audit` | Mode A (cross-spec、旧 spec-audit) + Mode B (conformance、旧 spec-check) の二モード化、`--mode=cross\|conformance\|both` 引数追加。Phase 6 で Diverged conformance の Tier 1 escalation 前に `technical-arbiter` 経由 |
| `robust-review` | (Phase 1 で英語化 + severity 表記統一済み) |
| `code-review` | (Phase 1 で英語化 + severity 表記統一済み) |
| `design-phase` | (Phase 1 で英語化済み) |
| `boundary-test` | (Phase 1 で英語化済み、独立維持を Phase 2 で確定) |
| `checkpoint` | (Phase 1 で英語化済み) |

## 新規追加 (Phase 6 ESCALATION-REDESIGN)

| 種別 | 名前 | 役割 |
|-----|-----|-----|
| Subagent | `technical-arbiter` | 命名/型/定数 drift の canonical 判定 (sonnet 4.6, read-only) |
| Subagent | `regression-judge` | Test failure の fix-related / pre-existing 判定 (sonnet 4.6) |
| Hook | `.claude/settings.json` Stop hook drift gate | skill 終了時に DESIGN/*.md との不一致を 10〜15s チェック (sonnet 4.6, 警告のみ) |

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

- 旧 (Phase 0): `/spec-fix all --loop 3`
- Phase 2: `/safe-fix all --mode=conformance --loop 3`
- 新 (Phase 6): `/impl-orchestrator <component>` で Stage 3 が自動 inline 修正 (single component) / spec-audit の JSON Findings ブロックを参照に Claude が直接編集 (multi-component / 部分修正)

### 「robust-review の Critical/High を一括修正」

- 旧 (Phase 0): `/robust-fix all`
- Phase 2: `/safe-fix all --mode=robust`
- 新 (Phase 6): `/impl-orchestrator <component>` の Stage 3 で自動 inline 修正 / robust-review の JSON Findings ブロックを Claude が直接処理

### 「単発バグ修正」

- 旧 (Phase 0): `/fix-with-verify <issue-description>`
- Phase 2: `/safe-fix <issue-description> --mode=adhoc`
- 新 (Phase 6): skill 経由なし。Claude が直接 Edit + Bash gate で対応 (Phase 5 dogfooding でこれが実態と確認、Mode C は廃止)

### 「差分ベースの素早いテスト」

- 旧: `/quick-test`
- 新: 不要 — `post-edit-lint.sh` hook が編集後に自動実行する。

### 「Finding を Tier 1/2/3 に分類」

- 旧: `/escalation classify <finding>`
- 新: skill 呼び出しは廃止。基準は [ARCHITECTURE.md §A 補章](../ARCHITECTURE.md) を参照。impl-orchestrator が Stage 3-5 で自動分類して `escalation_queue` (Tier 1) または inline 修正 (Tier 2/3、conformance-fix.md / robust-fix.md) にディスパッチする。命名/型 drift は Tier 1 escalation 前に `technical-arbiter` subagent 経由。

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

## Phase 5 実測結果 (2026-04-29)

| 指標 | BASELINE | Phase 1 | Phase 5 目標 | Phase 5 実測 | 達成 |
|------|---:|---:|---:|---:|:---:|
| skill 数 | 15 | 15 | **8** | **8** | ✅ |
| avg trigger_rate (8 skill 平均) | 0.293 *p* | 0.238 (artifact) | **+30%** | 0.375 (+19.2%) | ✗ (-0.034) |
| avg trigger_rate (7 skill, safe-fix 除外) | 0.314 *p* | — | **+30%** | 0.428 (+36.3%) | ✅ |
| avg pass_rate | 0.790 | 0.737 (artifact) | **≥ 0.80** | 0.863 (8 skill 平均) | ✅ |
| should_not_trigger_rate | 1.000 | 1.000 | **1.000** 維持 | 0.975 (spec-audit のみ 0.800) | △ (Phase 2 spec-check 吸収による正しい挙動) |
| 30 日 0 回呼び出しの遊休 skill 数 | 9 | — | **0** | **0** | ✅ |

`*p*` = proxy値 (safe-fix BASELINE は新設のため、旧 fix-with-verify/robust-fix/spec-fix の max を proxy として使用)

詳細な per-skill 分解と raw メトリクスは [evals/POST-DIFF.md](../evals/POST-DIFF.md)。

## Phase 5 個別 M1 (新 8 skill、+20% target)

| skill | BASELINE | POST | Δ | M1 個別 | 主な改善要因 |
|-------|---:|---:|---:|:---:|----|
| boundary-test       | 0.417     | 0.500 | +0.083 | ✓ | Phase 1 description 強化 |
| checkpoint          | 0.333     | 0.433 | +0.100 | ✓ | Phase 1 description 改善 |
| code-review         | 0.183     | 0.233 | +0.050 | ✓ (marginal) | Phase 1 英語化 |
| design-phase        | 0.417     | 0.500 | +0.083 | ✓ | Phase 1 英語化 |
| impl-orchestrator   | 0.300     | 0.483 | +0.183 | ✓ (strong) | Phase 2 ステージ 6→4 簡素化 + Phase 1 描述 |
| robust-review       | 0.100     | 0.267 | +0.167 | ✓ (strong) | Phase 1 英語化 + Phase 3 行数縮小 + Phase 4 `context: fork` |
| **safe-fix**        | 0.317 *p* | **0.000** | **-0.317** | ✗ | description で覆せず (Sub-V で構造再考) |
| spec-audit          | 0.450     | 0.583 | +0.133 | ✓ | Phase 2 spec-check 吸収による識別性向上 |

**結果**: 7/8 個別 M1 PASS、1/8 FAIL (safe-fix only)。

---

## Phase 6 Sub-V: safe-fix 構造再考

Phase 5 Sub-S で safe-fix description を 2 反復最適化 (v0/v1/v2) したが、全 iter で trigger 0.000。手動 probe 診断により **Opus 4.7 の routing 構造由来** が確定:

| 観察 | 内容 |
|------|------|
| 1 | `claude -p` を 2 回手動実行 (暗黙 query / 明示 "safe-fix Mode A" query) すると Skill emit = 0、Bash/Glob/Read を直接呼ぶ |
| 2 | description を v0 (skill 名 6 引用) → v1 (skill 名 0 引用) → v2 (batch/loop/pipeline 強調) のどれに変えても routing 行動は不変 |
| 3 | 他 7 skill (boundary-test, design-phase, impl-orchestrator, robust-review, spec-audit, checkpoint, code-review) は trigger 動詞が **直接ツールで代替不能** (例: cross-spec 走査、multi-stage 実装ループ、deep security audit) |
| 4 | safe-fix の value-add (verification gate, attribution-level revert, 3 連続失敗 escalation) は `Edit + Bash test + Bash revert` の 3 step sequence で代替可能 → wrapper skill が直接ツールに対し優位性を提供しない場合、Skill 経由を選ばない routing pattern |

### 構造再考 Options

Phase 6 dogfooding (1 週間) 中の実呼び出しログを根拠に、以下のいずれかを採用:

| Option | 内容 | 影響 | 採用条件 |
|--------|------|------|---------|
| **A** | `safe-fix` skill を廃止し、impl-orchestrator Stage 3 (escalation/remediation) に inline 化 | M2: 8 → 7、`finding.schema.json` は orchestrator 直接参照に移行、impl-orchestrator が肥大化 | dogfooding で impl-orchestrator → safe-fix の Skill 経由委譲が **完全に機能していない** ことが確認された場合 |
| **B** | `safe-fix` を `process-findings` (batch only、Mode C 削除) にリネーム | 名前変更で trigger 動詞 ("process" / "remediate") 試行可能、Mode C は impl-orchestrator から explicit 委譲のみ。要再 eval | dogfooding で **Mode A/B (batch) は機能、Mode C (adhoc) のみ trigger 0** が観察された場合 |
| **C** | 現状維持 (description は v2)、impl-orchestrator から `Skill` tool explicit 呼び出しのみで使う設計と認める | M1 個別 MISS を運用上許容、人手も `/safe-fix` slash で呼ぶ前提。コード変更ゼロ | dogfooding で impl-orchestrator → safe-fix の Skill 経由委譲が **機能している** ことが確認された場合 |

### Phase 6 確定採択: **Option A** (2026-05-23)

**根拠**: Phase 5 期間中の retroactive 観察 5 セッションで impl-orchestrator → safe-fix の Skill 経由委譲が 0/5、加えて impl-orchestrator/code-review も自然な口語短文クエリで unfired (1/5 のみ checkpoint が発火) — safe-fix 単独の routing 問題ではなく、natural-query での systemic な現象であることが確認された。Option C (現状維持) の前提条件 (impl-orchestrator → safe-fix Skill 委譲 ≥ 3 件) が満たされず、Option B (リネーム) も "process"/"remediate" が "fix" と同様 Bash 直接呼びに流される構造リスクが残るため、最も radical な **Option A (廃止 + inline 化)** を採用。

**実装サマリ (Phase 6 Sub-V 確定 commit)**:

- `skills/safe-fix/` ディレクトリ全削除 (SKILL.md + references 5 ファイル)
- `skills/safe-fix/references/finding.schema.json` → `skills/impl-orchestrator/references/finding.schema.json` へ移動 ($id を更新)
- `skills/safe-fix/references/mode-conformance.md` → `skills/impl-orchestrator/references/conformance-fix.md` へ移動 (CLI 引数 `--loop`/`--spec-wins`/`--impl-wins` 廃止、orchestrator の outer loop に統合)
- `skills/safe-fix/references/mode-robust.md` → `skills/impl-orchestrator/references/robust-fix.md` へ移動 (per-edit verification と revert policy を `regression-judge` 経由で拡張)
- `skills/safe-fix/references/mode-adhoc.md` および `output-format.md` は廃止 (Mode C は Claude 直接ハンドリングへ、output format は impl-orchestrator/references/final-report.md に吸収)
- `~/.claude/skills/safe-fix` シンボリックリンク削除
- `evals/queries/safe-fix.json` 削除、他 query JSON 内 `near-miss-safe-fix` タグ → `near-miss-impl-orchestrator` / `near-miss-fix-only` にリラベル
- `evals/scripts/run_baseline.sh` の `ALL_SKILLS` 配列から `safe-fix` 削除 (7 skill 構成)
- spec-audit / code-review / robust-review の SKILL.md 内 safe-fix 参照を impl-orchestrator references/ への参照に更新
- impl-orchestrator/SKILL.md Stage 3 タイトルを "Review & Remediate (opus reviewers ×3 + inline fix)" に変更、Stage 3-5 を inline dispatch + prefix 別 reference 参照に書き換え、Stage 3-6 (subagent-backed judgement) を追加
- impl-orchestrator/SKILL.md は約 225 行 (M3 200 行を 25 行超過、Option A trade-off として受容、内訳は inline dispatch 表 + subagent section)

**残存課題 (Phase 7 以降の観察対象)**:

- impl-orchestrator の line count が M3 制約を超えた点。さらなる references/ 分割で 200 行以下に戻すか、M3 を 250 行に緩和するかは Phase 7 dogfooding で判断
- impl-orchestrator 自体も自然な口語短文クエリでは trigger 0/5 だった点。これは safe-fix 廃止では解決せず、Option A の射程外。description 強化 / hook 補助 / slash 明示の選択肢を Phase 7 で検討

---

## Phase 6 Sub-W: query tag リラベル (2026-04-29 完了)

Phase 5 副次観察として、query JSON 内の `near-miss-*` tag に dropped skill 名が残存していた。新 8 skill 名へ literal rename 済み (commit `67be84c`):

| 旧 tag | 新 tag |
|--------|--------|
| `near-miss-spec-check` | `near-miss-spec-audit` |
| `near-miss-spec-fix` | `near-miss-safe-fix` |
| `near-miss-fix-with-verify` | `near-miss-safe-fix` |
| `near-miss-robust-fix` | `near-miss-safe-fix` |
| `near-miss-pipeline-state` | `near-miss-impl-orchestrator` |

旧 8 skill 用の query JSON ファイル (`evals/queries/{dev-pipeline,quick-test,spec-check,spec-fix,robust-fix,fix-with-verify,pipeline-state,escalation}.json`) は CHECKPOINT 方針 (Sub-X 後の整理予定) により未削除。

**注**: spec-audit.json には 2 件の self-reference (`near-miss-spec-audit` with `should_trigger: false`) が発生。これらの query は spec-audit Mode B (旧 spec-check 領域) の正しいトリガー対象だが、Phase 5 BASELINE/POST 比較性維持のため `should_trigger` は flip せず literal rename のみ実施。後続の eval 再実行時に flip 検討候補。
