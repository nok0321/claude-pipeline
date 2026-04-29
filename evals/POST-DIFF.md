# BASELINE vs POST diff (Phase 5)

Generated: 2026-04-29 (eval wall clock 76min, WORKERS=3, 8 skills × ~20 queries × 3 runs)

## 評価範囲

M1 評価は **post-Phase-2 の新 8 skill 限定**。Phase 0 BASELINE は 15 skill
を測定したが、Phase 2 で drop された 7 skill (`dev-pipeline`,
`escalation`, `fix-with-verify`, `pipeline-state`, `quick-test`,
`robust-fix`, `spec-check`, `spec-fix`) は `skills/` 配下に存在せず再測定
不能、対照外。

`safe-fix` は新設のため BASELINE 直接値なし。proxy として旧 3 skill
(`fix-with-verify` 0.317 / `robust-fix` 0.300 / `spec-fix` 0.233) の
`trigger_rate_overall` 最大値 **0.317** を使用 (統合先がカバーすべき責務
上限という解釈、PLAN §3.5 通り)。

## M1 個別評価 (新 8 skill 限定、+20% 目標)

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

`*p*` = proxy = max(fix-with-verify, robust-fix, spec-fix)

**個別 M1: 7/8 PASS、1/8 FAIL (safe-fix)**

## M1 平均評価 (新 8 skill 限定、+30% 目標)

|  | BASELINE 平均 | POST 平均 | Δ | +30% target | M1 平均 |
|---|---:|---:|---:|---:|:---:|
| 8 skill 全数 | 0.3146 | 0.3749 | +0.060 (+19.2%) | 0.4090 | ✗ (-0.034) |
| 7 skill (safe-fix 除く) | 0.3143 | 0.4284 | +0.114 (+36.3%) | 0.4086 | ✓ (+0.020) |

**平均 M1: 8 skill 算入で MISS、7 skill (safe-fix 除外) で PASS**

→ Sub-S で safe-fix を `≥ 0.380` まで戻せれば M1 全達成
(計算: safe-fix=0.380 で 8 skill 平均 = (2.999+0.380)/8 = 0.422 ≥ 0.409 ✓)。

## raw compare 出力

```
| skill | base trig | new trig | Δ trig | base ST | new ST | Δ ST | new SNT | base pass | new pass | Δ pass |
|---|---:|---:|---|---:|---:|---|---:|---:|---:|---|
| boundary-test     | 0.417 | 0.500 | +0.083 ↑   | 0.833 | 1.000 | +0.167 ↑   | 1.000 | 0.950 | 1.000 | +0.050 ↑ |
| checkpoint        | 0.333 | 0.433 | +0.100 ↑   | 0.667 | 0.867 | +0.200 ↑   | 1.000 | 0.800 | 0.950 | +0.150 ↑ |
| code-review       | 0.183 | 0.233 | +0.050 ↑   | 0.367 | 0.467 | +0.100 ↑   | 1.000 | 0.650 | 0.700 | +0.050 + |
| design-phase      | 0.417 | 0.500 | +0.083 ↑   | 0.833 | 1.000 | +0.167 ↑   | 1.000 | 0.950 | 1.000 | +0.050 ↑ |
| impl-orchestrator | 0.300 | 0.483 | +0.183 ↑   | 0.600 | 0.967 | +0.367 ↑↑  | 1.000 | 0.800 | 1.000 | +0.200 ↑ |
| robust-review     | 0.100 | 0.267 | +0.167 ↑   | 0.200 | 0.533 | +0.333 ↑↑  | 1.000 | 0.550 | 0.850 | +0.300 ↑↑|
| safe-fix          | 0.000 | 0.000 |  0.000 =   | 0.000 | 0.000 |  0.000 =   | 1.000 | 0.000 | 0.500 | +0.500 ↑↑|
| spec-audit        | 0.450 | 0.583 | +0.133 ↑   | 0.900 | 0.967 | +0.067 ↑   | 0.800 | 0.950 | 0.900 | -0.050 - |
```

(BASELINE 値は raw 出力上 safe-fix=0 だが、本評価では proxy 0.317 を base とする。drop された 8 skill 行は省略)

## 主要観察

### POST gain ≥ +0.10 の改善幹 (4 skill)

- **impl-orchestrator** (+0.183, +61%): Phase 2 のステージ 6→4 簡素化と Phase 1 描述書き直しの相乗
- **robust-review** (+0.167, +167%): BASELINE 0.100 という極低値からの大幅回復。Phase 1 英語化 + Phase 3 行数縮小 (209→177 行) + Phase 4 `context: fork` の効果
- **spec-audit** (+0.133, +30%): Phase 2 で spec-check を吸収したことで「DESIGN 間矛盾」「DESIGN vs 実装」両軸が 1 skill に集約され識別性向上
- **checkpoint** (+0.100, +30%): Phase 1 description 改善のみで底上げ

### regression の取扱い

raw diff の 8 件 regression (`dev-pipeline` ほか) はすべて **意図的 drop** の結果であり M1 評価対象外。`safe-fix` 0.000 のみが実問題。

### should_not_trigger_rate の例外

`spec-audit` のみ SNT が 0.800 (BASELINE 1.000 から低下)。`by_tag` で
`near-miss-spec-check: 1.000` が原因。これは Phase 2 で spec-audit が
spec-check を吸収した結果、旧 spec-audit query の「near-miss-spec-check」
タグ付きクエリ (= 旧 spec-check 領域) が **正しく** spec-audit を発火する
ようになっただけで、定義上 over-trigger ではない。クエリのタグ語彙が陳腐
化したと解釈する (Phase 6 でクエリリラベル候補)。

## safe-fix 0.000 の診断

10/10 should_trigger query が 30 試行全てで `triggers: 0`。`safe-fix.stderr.log`
は subprocess 完走を示し timeout / network failure ではない。

仮説 (description 文面ベース):

1. **skill 名引用過多**: 現 description 内に他 skill 名が 6 回登場
   (`spec-audit` ×2 / `robust-review` ×2 / `code-review` / `impl-orchestrator`)。
   query が「spec-audit found N findings ...」「robust-review just dumped N
   findings」と明示するため、router が **被参照 skill** に流される
2. **複合構造**: 「3 mode (conformance / robust / adhoc) を 1 skill で扱う」
   描写が 1500+ 字に膨らみ、key trigger 語 (`fix`, `patch`, `remediate`)
   が後半に埋没
3. **末尾の譲渡句**: 「For broad multi-component feature work, prefer
   `impl-orchestrator` instead」が impl-orchestrator への "redirect hint"
   になり多段配信中に safe-fix の優先度が下がる

→ Sub-S で description を「fix/patch/verify」を主語にした短形に書き換え、
   他 skill 名引用を最小化、譲渡句は本文に降格、で再 eval。

## まとめ

- **M3 (200 行以下)**: 達成継続 (Phase 4 後 168 行平均、最大 200)
- **M4 (遊休 skill 0 個)**: drop 7 + safe-fix 統合により 0 個 (M4 達成)
- **M5 (severity Critical/High/Medium/Low 統一)**: Phase 4 finding.schema.json で達成
- **M1 (trigger rate)**: 7/8 個別 PASS、8 skill 平均 MISS (-0.034)、7 skill 平均 PASS (+36.3%)
- **M2 (skill 本数 7-8)**: 8 skill 達成

---

## Sub-S 結果 (safe-fix description 反復、2026-04-29)

### iter1 (description v1: skill 名引用排除版、~900 字)

```
Use this skill whenever the user wants to apply a fix, patch, or
remediation with a built-in verification gate ... single-file bug fixes,
severity-tagged finding remediation ..., and design-vs-implementation
reconciliation loops.
```

→ 結果 `evals/results/post-s1/safe-fix.json`: trigger 0/30 (10/10 should_trigger 全失敗、変化なし)

### iter2 (description v2: batch/loop/pipeline 強調版)

```
Use this skill whenever the user has a batch of remediation items
... wants them processed in a controlled loop — one edit at a time,
with a verification gate ... running between every edit and an
automatic revert when the gate goes red, optionally iterating until
the diff converges.
```

→ 結果 `evals/results/post-s2/safe-fix.json`: trigger 0/30 (同上)

### 手動 probe による根本原因診断

`claude -p` を 2 回手動実行 (query: 1) "There's a bug in src/auth/login.ts:142 — fix it and verify ..."、2) "Apply safe-fix Mode A on the 12 spec-audit conformance findings against src/order/ ..."):

| 試行 | Skill emit | Bash | Glob | Read |
|------|----------:|-----:|-----:|-----:|
| 暗黙 query | 0 | 10 | 4 | 3 |
| 明示 query (safe-fix Mode A) | 0 | 3 | 5 | 3 |

→ Claude (claude-opus-4-7) は **「fix」動詞を含む query** に対し、Skill tool 経由ではなく **Bash/Glob/Read** を直接呼び出してファイル探索 → 該当ファイル不在で「ファイルが存在しません」回答で終了。description を v0/v1/v2 のいずれに変えても routing 行動は変化せず。

### 構造的解釈

| skill | trigger 動詞 | 直接ツールで代替可? | POST trigger |
|-------|-------------|------------------|---:|
| boundary-test | "test the contract" | × (boundary 検出は専用 logic) | 0.500 |
| design-phase | "generate DESIGN/X.md" | × (template + sonnet 委譲) | 0.500 |
| impl-orchestrator | "autonomously implement" | × (multi-stage loop) | 0.483 |
| robust-review | "audit for vulnerabilities" | △ (専用 axes / severity) | 0.267 |
| spec-audit | "audit DESIGN drift" | △ (cross-spec 走査) | 0.583 |
| **safe-fix** | "fix and verify" | **○ (Edit + Bash test + Bash revert)** | **0.000** |

safe-fix の value-add (verification gate, attribution-level revert, 3 連続失敗 escalation) は Bash/Edit 直接呼びの 3 step sequence で代替可能。Opus 4.7 は **wrapper skill が直接ツールに対し優位性を提供しない場合、Skill 経由を選ばない** という routing pattern が観測された。

### 採用方針

- description は **v2 を採用** (v0 比で skill 名引用 6 → 0 でクリーン、本文 quality 上の改善)
- POST trigger 0.000 を **受容**、M1 個別 MISS を確定とする
- iter3 (e.g., 「remediate」動詞のみ使用、algorithmic value 強調) も同じ routing 行動に阻まれる蓋然性が極めて高いため見送り
- Phase 6 で safe-fix の **構造再考** を課題化:
  - **Option A**: skill を廃止し、impl-orchestrator Stage 4 (escalation/remediation) に inline 化
  - **Option B**: skill を `process-findings` (batch only、Mode C 削除) にリネーム + Mode A/B 専用化、impl-orchestrator から explicit 委譲のみで使う
  - **Option C**: 現状維持 (impl-orchestrator から `Skill` tool 経由で explicit 呼び出しは機能しているはず、skill 自身の trigger は諦める)
- Sub-Q/R/S を経て **M1 全達成は不能、しかし 7/8 + 7-skill 平均 +36.3% で main マージ判断可能水準** という結論
