# evals/ — Skill Trigger Rate 評価フレームワーク

`plans/REDESIGN-PLAN.md` Phase 0 / Phase 5 で使用する、各 skill の trigger rate を定量測定するための枠組み。

## 目的

- **Phase 0 (BASELINE)**: 現状16 skill のトリガー精度を baseline として測定し、再設計の効果を後から定量検証可能にする
- **Phase 1 (PHASE1)**: 英語化 + description 再設計後の中間測定
- **Phase 5 (POST)**: 全フェーズ完了後の最終測定。BASELINE と diff 取り、改善目標未達 skill は description 自動最適化 (`run_loop.py`) を走らせる

## ディレクトリ構造

```
evals/
├── README.md              # 本ファイル
├── queries/               # skill毎のクエリセット (各20件)
│   ├── spec-audit.json
│   ├── impl-orchestrator.json
│   ├── ... (16 skill 分)
├── results/               # run_eval.py の生出力
│   ├── baseline/          # Phase 0 結果 (各 skill 1ファイル)
│   ├── phase1/            # Phase 1 中間結果
│   └── post/              # Phase 5 最終結果
├── scripts/               # 実行wrapper
│   ├── run_baseline.sh    # 16 skill を順次走らせる (Phase 0/5)
│   ├── compare_evals.py   # BASELINE vs POST 差分集計
│   └── README.md          # スクリプト使用法
├── BASELINE.json          # Phase 0 集計 (全 skill metric)
├── PHASE1.json            # Phase 1 集計 (中間)
└── POST.json              # Phase 5 集計
```

## クエリ仕様

各 skill 20件、内訳は以下：

| 種別 | 件数 | 詳細 |
|------|------|------|
| should-trigger | 10件 | 該当 skill が呼ばれるべきクエリ |
| should-not-trigger | 10件 | 該当 skill が呼ばれてはいけないクエリ (近接 skill との境界 = near-miss が中心) |

### 言語ポリシー

**全クエリ100%英語**。理由：

- skillの description が Phase 1 で英語化される。日本語クエリ × 英語 description の組み合わせは Phase 5 では measurable variance として現れない (主用途が英語化される前提)
- baseline (Phase 0) は **現状の日本語 description × 英語クエリ** で測定する。これにより Phase 1 の英語化純効果が定量できる
- 公式 skill-creator も英語クエリ前提のフレームワーク

将来日本語 trigger 精度を別軸で測りたくなった場合は、`evals/queries-ja/` を別途作成する想定 (Phase 5 で必要になれば)。

### 品質基準 (skill-creator/SKILL.md §Description Optimization §Step 1 準拠)

- **具体性**: ファイル名・ディレクトリ名・列名・会社名・状況文を含む
- **realistic**: 略語・lowercase・casual 表現を混ぜる (`yo can u sanity check ...`)
- **near-miss 重視**: should-not-trigger では「キーワードは似ているが別 skill の責務」を狙う
- **過度に簡単な否定例は避ける**: "fibonacci function" のような無関係クエリは情報量ゼロなので入れない
- **短文 implicit 禁止**: "Quick test plz" のような1行未満で文脈が薄いクエリは false negative の温床。最低でも「状況設定 + 具体ファイル名/数値 + 1〜2文」のボリュームを確保する

### JSON フォーマット (`run_eval.py` 入力)

```json
[
  {"query": "...", "should_trigger": true, "tag": "explicit"},
  {"query": "...", "should_trigger": false, "tag": "near-miss-spec-check"}
]
```

`tag` は監査用 (run_eval.py は無視)。種類: `explicit`, `implicit`, `casual`, `near-miss-<adjacent-skill>`, `generic`。

## 実行手順 (Phase 0)

### 前提

- skill-creator の eval framework は `~/.claude/plugins/marketplaces/claude-plugins-official/plugins/skill-creator/skills/skill-creator/scripts/` にある (本リポジトリは参照のみ。コピーしない)
- `claude` CLI がPATHにあること
- 並行作業禁止期間: baseline 測定中 (約30分〜1時間) は 16 skill のSKILL.md を編集しない

### 実行

```bash
# claude-pipeline/ から
bash evals/scripts/run_baseline.sh

# または個別に走らせる
python "$SKILL_CREATOR_DIR/scripts/run_eval.py" \
  --eval-set evals/queries/spec-audit.json \
  --skill-path skills/spec-audit \
  --runs-per-query 3 \
  --num-workers 10 \
  --timeout 30 \
  --model claude-opus-4-7 \
  --verbose \
  > evals/results/baseline/spec-audit.json
```

### 集計

```bash
python evals/scripts/aggregate.py evals/results/baseline > evals/BASELINE.json
```

## 評価メトリクス (BASELINE.json スキーマ)

```json
{
  "phase": "baseline",
  "model": "claude-opus-4-7",
  "timestamp": "2026-04-28T...",
  "skills": {
    "spec-audit": {
      "trigger_rate_overall": 0.85,
      "should_trigger_rate": 0.92,
      "should_not_trigger_rate": 0.78,
      "passed": 17,
      "total": 20,
      "by_tag": {
        "explicit": 1.00,
        "implicit": 0.83,
        "casual": 0.75,
        "near-miss-spec-check": 0.50,
        "near-miss-design-phase": 1.00,
        "generic": 1.00
      }
    },
    ...
  },
  "summary": {
    "avg_trigger_rate": 0.72,
    "skills_above_threshold_0.7": 9
  }
}
```

## 注意事項

- `run_eval.py` は `claude -p` を subprocess 起動する。CLAUDECODE 環境変数を除去して走るため、入れ子実行可能
- 各クエリ 3回実行 (`--runs-per-query 3`) でばらつきを吸収
- num-workers=10 で並列。timeout=30秒/query
- 16 skill × 20 query × 3 runs = 960 回の `claude -p` 呼び出し。実時間 30〜60分程度を想定
- 測定中はネットワーク・モデル負荷の影響を受けるため、結果のばらつきは ±5%程度で評価する
