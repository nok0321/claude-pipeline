# Redesign Checkpoint: Phase 6 進行中 (dogfooding 期間)

Updated: 2026-04-29 (Phase 6 session 2 完了、`~/.claude/skills/` 配置整備、dogfooding 本格化)

## 現在地

- ブランチ: `redesign/heavy` (main は触らない、dogfooding で効果実感後に 1 回マージ)
- 計画書: [REDESIGN-PLAN.md](REDESIGN-PLAN.md)
- **状態**: Phase 6 session 2 完了。`~/.claude/skills/` を新 8 skill 構成に整備済み (safe-fix 追加 + 旧 dropped 8 skill broken リンク削除)。dogfooding 体験フェーズ進行中。
- 完了 commits (新しい順、Phase 6 session 1):
  - `2a99134` Phase 6 Step 4: MIGRATION Phase 5 results + Sub-V options + Option C interim (Sub-U-3 + Sub-V)
  - `4cc5538` Phase 6 Step 3: ARCHITECTURE §11.1 Phase 5 evaluation table (Sub-U-2)
  - `e560e24` Phase 6 Step 2: rewrite README for new 8-skill structure (Sub-U-1)
  - `67be84c` Phase 6 Step 1: relabel near-miss-* tags to new 8-skill names (Sub-W)
- Phase 5:
  - `505d540` Phase 5 Step 5: Sub-T decisions + CHECKPOINT for Phase 6 handoff
  - `04ada85` Phase 5 Step 4: Sub-S safe-fix description optimization (2 iter, accepted 0.000)
  - `ea440fc` Phase 5 Step 3: BASELINE → POST diff + M1 evaluation (Sub-R)
  - `e7bd1ea` Phase 5 Step 2: POST eval results (8 skills, WORKERS=3, 76min)
  - `4bc47f9` Phase 5 Step 1: prep POST eval (safe-fix queries + 8-skill scope)
- Phase 4:
  - `0e2cf8a` Phase 4 Step 2: formalize Finding schema + propagate JSON emission (Sub-P)
  - `92cd74f` Phase 4 Step 1: extend context: fork to safe-fix + boundary-test (Sub-M)
- Phase 3 / 2 / 1 / 0 (略、前 CHECKPOINT 参照)

---

## Phase 5 実行結果 (2026-04-29, redesign/heavy: 4 commits)

| Sub | 内容 | 判定 | commit |
|-----|------|------|--------|
| Q | POST eval (8 skills, WORKERS=3) | 完走 76min、rate-limit なし | `4bc47f9` `e7bd1ea` |
| R | BASELINE → POST diff + M1 評価 | 7/8 個別 PASS、7-skill 平均 PASS | `ea440fc` |
| S | safe-fix description 最適化 | 2 iter 共 0.000、構造的問題で受容 | `04ada85` |
| T | Sub-M案A/B + Sub-O の採否再判断 | 全て見送り維持 (本 commit) | この CHECKPOINT |

### Sub-Q / R: M1 達成状況 (新 8 skill)

| skill | BASELINE | POST | Δ | +20% target | M1 個別 |
|-------|---:|---:|---:|---:|:---:|
| boundary-test       | 0.417     | 0.500 | +0.083 | ≥ 0.500 | ✓ |
| checkpoint          | 0.333     | 0.433 | +0.100 | ≥ 0.400 | ✓ |
| code-review         | 0.183     | 0.233 | +0.050 | ≥ 0.220 | ✓ (marginal) |
| design-phase        | 0.417     | 0.500 | +0.083 | ≥ 0.500 | ✓ |
| impl-orchestrator   | 0.300     | 0.483 | +0.183 | ≥ 0.360 | ✓ (strong) |
| robust-review       | 0.100     | 0.267 | +0.167 | ≥ 0.120 | ✓ (strong) |
| **safe-fix**        | 0.317 *p* | **0.000** | **-0.317** | ≥ 0.380 | ✗ |
| spec-audit          | 0.450     | 0.583 | +0.133 | ≥ 0.540 | ✓ |

平均:
- 8 skill 全数: 0.3146 → 0.3749 (+19.2%) ← 30% target MISS by -0.034
- 7 skill (safe-fix 除外): 0.3143 → 0.4284 (+36.3%) ← 30% target PASS

副次観察:
- spec-audit `should_not_trigger_rate` が 0.800 に低下 (BASELINE 1.000) — 原因は `near-miss-spec-check` タグ (旧 spec-check 領域) が今 spec-audit を発火するため。Phase 2 の spec-check 吸収による正しい挙動、over-trigger ではない。Phase 6 でクエリリラベル候補
- 旧 8 skill (drop された 7 + safe-fix BASELINE proxy 元) は raw diff 上 -0.000 ↓↓ で並ぶが M1 評価対象外

詳細: [evals/POST-DIFF.md](../evals/POST-DIFF.md)

### Sub-S: safe-fix 描述最適化 (受容)

- iter1 (v1, skill 名引用排除版): trigger 0/30
- iter2 (v2, batch/loop/pipeline 強調版): trigger 0/30
- 手動 probe で根本原因確定 — Opus 4.7 は **「fix」動詞 query を Skill 経由ではなく Bash/Glob/Read 直接呼びでルーティング**。description を v0/v1/v2 のいずれに変えても routing 行動は変化せず
- safe-fix の value-add (verification gate, attribution-level revert) が直接ツール sequence で代替可能なため、wrapper skill 経由が選ばれない構造
- **採用方針**: v2 description 確定 (skill 名引用 6→0 で本文 quality 改善)、POST trigger 0.000 を受容、Phase 6 で構造再考 (Option A/B/C を後述)

### Sub-T: 構造変更採否

| 案 | 内容 | 判定 | 理由 |
|-----|------|------|------|
| Sub-M案A | orchestrator Stage 3-2 を Skill ツール経由 (robust-review + spec-audit conformance) で 2 軸並列に縮退 | **見送り維持** | impl-orchestrator が +0.183 / +61% で M1 強 PASS、Stage 3-2 inline 3-Agent dispatch は機能している。axis 分離 (3 → 2 軸縮退) のリスク取る合理性なし |
| Sub-M案B | `.claude/agents/<reviewer>.md` カスタム subagent 3 個新設 | **見送り維持** | 案 A と同じく改善動機なし。`.claude/agents/` 新設は eval 検証不能で効果見積もり不可 |
| Sub-O | impl-orchestrator frontmatter に `skills:` 追加 | **見送り維持** | 公式仕様で `skills:` は subagent frontmatter フィールドのみ、orchestrator は subagent でないため採用不可。`.claude/agents/` 経由の移行パスは Sub-M案B と同根 |

→ Phase 6 で再考すべき構造変更は **safe-fix の構造再考のみ** (Sub-S findings 由来)。

---

## Phase 6 サブタスク (引き継ぎ)

PLAN §3.6 + Sub-S/T 結論を踏まえた更新版。

### Sub-U: README / ARCHITECTURE / MIGRATION 更新 (PLAN §3.6 既定)

- README.md: 構成図と Component Mapping を新 8 skill 構造で更新
- ARCHITECTURE.md: §11 チェックリスト全項目を再評価、現状反映、§A/§B 補章 (Phase 2 で追加済み) との整合確認
- docs/MIGRATION.md: 旧 15 → 新 8 skill 対応表は Phase 2 で作成済み、Sub-S findings (safe-fix 0.000) と Phase 6 構造再考 Option を追記

### Sub-V: safe-fix 構造再考

Sub-S 結果を受けて 3 オプションのいずれかを採用:

| Option | 内容 | 影響 | 判定材料 |
|--------|------|------|---------|
| A | safe-fix skill を廃止し、impl-orchestrator Stage 3 escalation/remediation に inline 化 | M2 (skill 本数) 8 → 7、`finding.schema.json` は orchestrator 直接参照に移行 | 最も radical、impl-orchestrator が肥大化するリスク |
| B | safe-fix を `process-findings` (batch only、Mode C 削除) にリネーム | 名前変更で trigger 動詞 ("process" / "remediate") 試行可能、Mode C は impl-orchestrator から explicit 委譲のみ | 中庸、要再 eval |
| C | 現状維持 (description は v2)、impl-orchestrator から Skill tool explicit 呼び出しのみで使う設計と認める | M1 個別 MISS を運用上許容、人手も `/safe-fix` slash で呼ぶ前提 | 最も保守的、コード変更ゼロ |

判定タイミング: Phase 6 dogfooding (1 週間) 中の実呼び出しログ (memory に書き溜め) を参照、impl-orchestrator → safe-fix の Skill 経由委譲が機能していれば Option C で十分、機能していなければ Option B → A と昇格

### Sub-W: クエリリラベル / 拡張 (Phase 5 副次課題)

Phase 5 で観測した tag 名陳腐化:
- `near-miss-spec-check` / `near-miss-spec-fix` / `near-miss-fix-with-verify` / `near-miss-quick-test` / `near-miss-pipeline-state` / `near-miss-robust-fix` / `near-miss-dev-pipeline` etc. はすべて drop された skill 名で、tag 語彙として陳腐化
- Phase 6 で query JSON の tag を新 8 skill 名にリラベル
- spec-audit の `should_not_trigger_rate` 0.800 は Phase 2 spec-check 吸収による正しい挙動だが、tag リラベル後は 1.000 に戻る想定

### Sub-X: 1 週間 dogfooding (PLAN §3.6 既定)

- 新構造を実運用に乗せる (1 週間)
- skill 発火/誤発火の観察、CHECKPOINT.md に記録
- 1 週間後にホットフィックス commit を 1〜2 件で完結
- main にマージ (Phase 6 完了)

### 成果物

更新された README/ARCHITECTURE、MIGRATION.md (Phase 5 findings 追記)、safe-fix 構造変更 commit (Option 採用時)、main マージ。

---

## Phase 6 session 1 完了サマリ (2026-04-29)

| Sub | 内容 | 判定 | commit |
|-----|------|------|--------|
| W | query tag リラベル (8 現役 skill) | 完了 (literal rename) | `67be84c` |
| U-1 | README.md を新 8 skill 構造で書き直し | 完了 | `e560e24` |
| U-2 | ARCHITECTURE.md §11.1 Phase 5 評価追記 | 完了 | `4cc5538` |
| U-3 + V | MIGRATION.md に Phase 5 findings + Sub-V Options + Option C 暫定採択 | 完了 (eval 再実行なし) | `2a99134` |
| X | dogfooding 観察ログ受け皿 | (本 commit) 受け皿のみ準備、観察は 1 週間 |  |

**未完**: Sub-X dogfooding 期間 (1 週間)、その後 Sub-V Option 確定 + main マージ。

---

## Phase 6 dogfooding 観察ログ (2026-04-29 〜 2026-05-06 予定)

**目的**: 新 8 skill 構造を実運用に乗せ、(1) skill 発火/誤発火、(2) impl-orchestrator → safe-fix の Skill 経由委譲頻度、(3) ARCHITECTURE §11.1 ⏳ 項目 (CLAUDE.md 動的読み取り、状態管理レイヤ役割分離、検証ゲート→レビュー順序) の実運用観察。

### 観察テンプレート (実例追記、日付順)

```
### YYYY-MM-DD <短いタスク名>
- プロジェクト: <repo / 用途>
- 起動 skill: </impl-orchestrator | /spec-audit | ...>
- 実行モデル: <claude-opus-4-7 / sonnet / etc>
- 観察:
  - skill 発火: <成功 | 失敗 (Bash/Edit 直接呼びへ流れた等)>
  - 誤発火: <あり/なし、内容>
  - safe-fix 経由委譲: <あり (件数) / なし>
  - CLAUDE.md セクション活用: <Component Mapping / Critical Constraints / etc 何が読まれたか>
  - 検証ゲート→レビュー順序: <順守 / 逸脱>
  - hook 動作: <pre-bash-safety / post-edit-lint / stop-verify / session-start の発動 + 効果>
- 課題 / hotfix 候補: <あれば>
```

### 観察エントリ

#### 2026-04-29 Phase 5 期間中の retroactive 観察 (5 セッション)

Phase 5 着手 (01:17) 〜 Phase 6 session 1 着手 (06:54) の間、claude-pipeline working dir 上で発生した自然な実運用クエリ 5 セッションを Claude Code セッションログから retroactive に集計。

| セッション | 起動時刻 | Query (要約) | 期待 skill | 実呼び出し tool | 判定 |
|---|---|---|---|---|---|
| 831852e1 | 01:39 | "long task, gonna take a nap. checkpoint the state..." | checkpoint | Skill(checkpoint), Bash×2, Glob×2, Read×2 | ✅ 発火 |
| e20426b0 | 01:44 | "Transition the pipeline to Phase 3 ... PIPELINE-STATE.md..." | impl-orchestrator | Glob×3, Read×4 | ❌ 不発火 (Read/Glob 直呼び) |
| e4d7edcc | 01:47 | "5 min PR review on my changes..." | code-review | Bash×4 | ❌ 不発火 (Bash 直呼び) |
| 613dd06e | 01:47 | "5 min PR review..." (重複起動) | code-review | Bash×2 | ❌ 不発火 (Bash 直呼び) |
| 43be4571 | 02:32 | "Help me write a CONTRIBUTING.md..." | (skill 対象外) | Glob×3, Read×3 | — (対象外) |

**集計**: Skill 発火 1/5 (checkpoint のみ) / 不発火 3/5 (impl-orchestrator ×1, code-review ×2) / 誤発火 0 / safe-fix 経由委譲 0 / skill 対象外 1/5。

**気付き**: Phase 5 で safe-fix 0.000 を「Opus 4.7 の "fix" 動詞 routing 由来」と判定したが、実運用観察では **impl-orchestrator (PIPELINE-STATE 更新依頼)** と **code-review (PR review 依頼)** も Skill 経由されず Bash/Read 直呼びになっている。safe-fix 単独の routing 問題ではなく、**主要 Layer 1/2 skill 全体に系統的に発生している現象** の可能性が高い。eval (構造化トリガーフレーズ含む 20 query 平均) では 7/8 個別 M1 PASS だが、自然な口語短文クエリ (5〜50 文字) では発火率が大幅に下がる。eval スコアと実運用体感のギャップを示唆。

**注**: 上記 5 セッションは Phase 5 着手後の偶発的観察であり、Phase 6 dogfooding 期間 (1 週間) の正式観察ではない。本格的 dogfooding (`~/.claude/skills/` 経由で全プロジェクトから新 8 skill を呼べる状態) は session 2 で初めて整備された (下記)。

#### 2026-04-29 Phase 6 環境整備 (session 2)

- `~/.claude/skills/` の状況確認:
  - 旧 15 skill 構造 (4月12日作成) のシンボリックリンクが残存していた
  - 新 8 skill 中 7 個 (boundary-test, checkpoint, code-review, design-phase, impl-orchestrator, robust-review, spec-audit) は OK
  - **safe-fix MISSING**、旧 dropped 8 skill (dev-pipeline, escalation, fix-with-verify, pipeline-state, quick-test, robust-fix, spec-check, spec-fix) が **BROKEN** として残存
- 配置修正:
  - `ln -s` で safe-fix シンボリックリンク作成 (Windows directory junction として作成、Claude Code は認識)
  - 旧 dropped 8 個の broken シンボリックリンクを削除
- 検証: 起動中セッションの skill list に新 8 skill 全て出現を確認

**方針更新**: ある程度実運用 (dogfooding) で効果実感してから main マージへ。Sub-V Option 確定 / ARCHITECTURE §11.1 ⏳ 項目最終評価 / orphan query JSON 整理 / main マージは全て **dogfooding 体験後に保留**。

#### (dogfooding 期間中、新規セッションでの観察はここへ追記)

### Sub-V 判断材料 (1 週間後に集計)

- impl-orchestrator → safe-fix 経由委譲 観察件数: ___ / ___
- safe-fix 単発呼び出し (Mode C / `/safe-fix` slash) 件数: ___
- safe-fix 不発で impl-orchestrator が直接 Edit + Bash で remediation した件数: ___
- → Option A / B / C 採用判断 (詳細条件は [docs/MIGRATION.md](../docs/MIGRATION.md) §Phase 6 Sub-V)

#### Phase 5 期間中 retroactive 観察 (暫定値、上記 5 セッション分のみ)

- impl-orchestrator → safe-fix 経由委譲: 0/5
- safe-fix 単発呼び出し: 0
- impl-orchestrator が発火しなかった件数: 1/1 (期待されたが Read/Glob 直呼び)
- code-review が発火しなかった件数: 2/2 (期待されたが Bash 直呼び)
- 暫定判断: Option C 妥当だが、**構造的課題が safe-fix 単独でなく系統的** なため、Option A/B 採用しても上流不発火を解決しない可能性。Phase 6 dogfooding で正式再検証必要。

---

## 維持事項

- ARCHITECTURE.md / README.md / plans/* / docs/MIGRATION.md / evals/POST-DIFF.md は日本語維持
- ユーザー出力は日本語可
- skills/ 編集中は eval 実行禁止 (測定汚染防止)
- main にはマージしない (Phase 6 完了まで `redesign/heavy` 1 本)
- 並列 Bash/Agent 実行を避ける (前セッションで上限到達)
- 長時間 eval (>60min) は run_in_background + 通知待ち

## 引き継ぎメモ

- True baseline (Phase 0) = 0.293, Phase 1 = 0.238 (artifact 込み), **Phase 5 POST = 0.375** (8 skill 平均)
- 7/8 個別 M1 PASS、7-skill 平均 +36.3% PASS、main マージ可能水準
- safe-fix 0.000 は Opus 4.7 の routing 構造由来 (description で覆せず)、Phase 6 Sub-V で構造再考
- ARCHITECTURE.md `§A 補章 (Escalation framework)` と `§B 補章 (Pipeline state file)` は impl-orchestrator が常時参照する核ドキュメント
- safe-fix の Finding 入力契約は `skills/safe-fix/references/finding.schema.json` (Phase 4 formal、Phase 6 で safe-fix 構造変更時は schema も移動可能性)
- 上流 reviewer (spec-audit / robust-review / code-review / orchestrator inline reviewer ×3) はすべて schema 準拠 JSON Findings block を末尾出力
- `context: fork` 適用済み skill: robust-review, code-review, spec-audit (Phase 1)、safe-fix, boundary-test (Phase 4)
- `context: fork` 未適用 skill とその理由: design-phase (Agent 入れ子)、impl-orchestrator (orchestrator 状態)、checkpoint (session history)
- Sub-N/O は公式仕様の不在により frontmatter 経由の単純化が不可。並列化は既存「1 メッセージ × 複数 Agent」が公式パターン
- `evals/results/{baseline,baseline-resub,smoke,smoke-direct,smoke-pushy,phase1,phase1-isolation,post,post-s1,post-s2}/` の整理は Phase 6 Sub-X 後にまとめて整頓予定
- `.claude/` も untracked。Sub-O 移行パスを採用しないため当面 untracked 維持

## メッセージ上限対策

- Phase 6 は eval 実行不要 (Sub-V で構造変更後に 1 回再 eval する可能性のみ)、message 量は Phase 5 より軽減見込み
- TodoWrite 推奨
- 1 Sub ごとに 1 commit を切る

---

## 新規セッション開始プロンプト

### dogfooding 中の hotfix セッション (Phase 6 session 1.5)

```
claude-pipeline Phase 6 dogfooding 中、観察ログ追記 / hotfix の作業をお願いします。
- 作業ブランチ: redesign/heavy
- 状況: plans/REDESIGN-CHECKPOINT.md §Phase 6 dogfooding 観察ログ を最初に読んでください
- 今回の観察 / hotfix 内容: <ここに具体タスク>
- 注意: main にマージしない、Bash/Agent 並列禁止、skill SKILL.md 編集中は eval を回さない
```

### dogfooding 完了後の最終セッション (Phase 6 session 2)

```
claude-pipeline Phase 6 dogfooding 完了、Sub-V 確定 + main マージをお願いします。
- 作業ブランチ: redesign/heavy
- 状況: plans/REDESIGN-CHECKPOINT.md §Phase 6 dogfooding 観察ログ を最初に読んでください
- 集計済み観察結果: <skill 発火 / safe-fix 経由委譲 / 誤発火 件数を要約>
- 必要作業:
  1. Sub-V Option (A/B/C) の最終確定 (条件は docs/MIGRATION.md §Phase 6 Sub-V)
  2. Option A/B 採用時は SKILL 編集 → eval 1 回打ち直し
  3. ARCHITECTURE.md §11.1 ⏳ 項目を実運用結果で更新
  4. evals/queries/ の旧 8 skill orphan JSON を整理 (削除 or アーカイブ)
  5. main にマージ (Phase 6 完了)
- 注意: Bash/Agent 並列禁止、main マージは最後の操作
```
