# OPUS48-DIFF: Opus 4.7 → 4.8 トリガー eval 再ベースライン

測定日: 2026-05-30 / 対象: 現行 7 skill / harness: [scripts/run_eval_compat.py](scripts/run_eval_compat.py)
比較元: [POST.json](POST.json) (`claude-opus-4-7`, Phase 5, 2026-04-29) / 比較先: [OPUS48.json](OPUS48.json) (`claude-opus-4-8`)
実行条件: `WORKERS=3 RUNS=3 TIMEOUT=30`、0 failures / 7、所要 66 分 (3976s)

> **背景**: Opus 4.8 への bump (commit `589da78`) を機に、[ARCHITECTURE.md](../ARCHITECTURE.md) §11「将来見直しチェックリスト」のうち「モデル配分は最新モデルの性能・価格カーブで依然合理的か」「description チューニングが 4.8 でも有効か」を再検証。Phase 5 POST (4.7) 以来の初の再測定で、4.8 の新ベースラインを確定する。

---

## 1. 結果サマリ (現行 7 skill, `trigger_rate_overall`)

| skill | 4.7 (POST) | 4.8 (OPUS48) | Δtrig | should_trigger 4.7→4.8 | should_not 4.7→4.8 | pass 4.7→4.8 |
|-------|---:|---:|---:|:---:|:---:|:---:|
| boundary-test     | 0.500 | 0.367 | **-0.133** | 1.000→0.733 | 1.0→1.0 | 20→18 |
| checkpoint        | 0.433 | 0.500 | +0.067 | 0.867→1.000 | 1.0→1.0 | 19→20 |
| code-review       | 0.233 | 0.367 | **+0.134** | 0.467→0.733 | 1.0→1.0 | 14→18 |
| design-phase      | 0.500 | 0.483 | -0.017 | 1.000→0.967 | 1.0→1.0 | 20→20 |
| impl-orchestrator | 0.483 | 0.483 | +0.000 | 0.967→0.967 | 1.0→1.0 | 20→20 |
| robust-review     | 0.267 | 0.350 | +0.083 | 0.533→0.700 | 1.0→1.0 | 17→18 |
| spec-audit        | 0.583 | 0.400 | **-0.183** | 0.967→0.800 | **0.8→1.0** | 18→19 |

### 平均 (公平な 7 skill 同士)

- avg `trigger_rate_overall`: **0.428 → 0.421 (-0.007、ほぼ横ばい)**
- avg `pass_rate`: **0.914 → 0.950 (+0.036)**
- `should_not_trigger_rate`: 全 7 skill で **1.000** (過剰発火ゼロ、compare.py も "intact" と確認)

> ⚠️ **compare.py 見出しの罠**: `compare.py POST.json OPUS48.json` は見出しで「AVERAGE trigger 0.375→0.421 (+0.046)」「pass 0.863→0.950」と出すが、これは **POST 側が廃止済み safe-fix(0.0) を含む 8 skill 平均**であり、7 skill の OPUS48 とは母数が異なる。**公平な 7 skill 同士は上表のとおり** (trigger ほぼ横ばい / pass +0.036)。出力中の `safe-fix 0.000 -> 0.000 ... Δpass -0.500` 行は OPUS48 に存在しない skill を 0 埋めした artifact なので無視する。

---

## 2. 解釈

### 2.1 description チューニングは 4.8 でも有効 (破綻なし)

全 7 skill が pass 閾値 0.7 超え (`skills_above_pass_threshold_0.7 = 7/7`)。4.7 で最適化した description が 4.8 でも機能しており、**bump に伴う description 作り直しは不要**。

### 2.2 過剰発火はむしろ改善

spec-audit の `should_not_trigger_rate` が 0.8→1.0。Phase 5 で「`near-miss-spec-check` が spec-audit を誤発火 (Phase 2 の spec-check 吸収による副作用)」と記録した現象が、4.8 + Sub-W tag リラベル後の現行 query では解消 (`near-miss-spec-audit` = 0.0)。precision 向上。

### 2.3 改善した skill

- **code-review +0.134** — casual 0.167→1.000 が主因。4.7 で弱かった口語短文の発火が 4.8 で大幅改善。Phase 6 retroactive 観察 (REDESIGN-CHECKPOINT) で「code-review が PR review 依頼に不発火 (Bash 直呼び)」と記録した課題に対し、追い風の変化。
- **robust-review +0.083** (should_trigger 0.533→0.700)
- **checkpoint +0.067** (should_trigger 0.867→1.000)

### 2.4 微減した skill (監視扱い・description は改変しない)

- **spec-audit -0.183**: explicit 1.0→0.733。ただし `should_not` が 0.8→1.0 に改善した振り替え込みで、純粋な発火力低下とは断定できない。
- **boundary-test -0.133**: casual 1.0→0.5、explicit 1.0→0.733。
- いずれも RUNS=3 の分散域 (1 query = 0.33 刻み) 内。**単発再測定で description を弄ると noise への over-fit になる**ため、現時点は監視にとどめ、次回 bump 時の再測定で傾向が継続したら対応する。

### 2.5 routing 前提の再検証 (Sub-V Option A の妥当性)

Phase 5/6 で safe-fix を廃止 (Option A) した根拠は「Opus 4.7 が fix 動詞 query を Skill 経由でなく Bash/Edit 直呼びにルーティング」。4.8 では safe-fix が存在しないため直接再現できないが、代理シグナルとして **impl-orchestrator の `near-miss-fix-only` tag が 4.8 でも 0.0**（= fix 単独 query はオーケストレーション skill に流れない、これは望ましい挙動）。fix 動詞が skill にルーティングされない構造は 4.8 でも不変であり、**standalone fix skill を持たず impl-orchestrator Stage 3 に inline 化した Option A は 4.8 でも妥当**と確認。

---

## 3. 結論

- 4.8 bump はトリガー品質を概ね維持 (横ばい〜微改善)、precision は改善。**description / モデル配分の作り直しは不要**。
- ARCHITECTURE §11 チェックリスト「モデル配分は最新モデルの性能・価格カーブで依然合理的か」→ **トリガー面では Yes** (合理的)。レビュー品質面は trigger eval では測れないため別途 (§11.2 参照)。
- 微減 2 skill (spec-audit, boundary-test) は監視項目として ARCHITECTURE §11.2 に記録。
- **`OPUS48.json` を 4.8 の新ベースラインとして確定**。次回モデル bump 時の比較元はこれ (4.7 系の BASELINE/POST は世代・skill 数が異なるため非互換)。
