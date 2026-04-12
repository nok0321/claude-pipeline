---
name: spec-cycle
description: spec-check → spec-fix → re-check の整合性サイクルを自動実行。全差分が解消されるまでループし、解消不能な項目はエスカレーションする。
argument-hint: "[component-name or 'all'] [--spec-wins | --impl-wins | --max-iterations N]"
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
model: claude-opus-4-6
---

# 仕様整合性サイクル

spec-check → spec-fix → re-check のサイクルを自動実行し、仕様と実装の整合性を確保する。

---

## 使い方

```
/spec-cycle              # 変更ファイルに関連するコンポーネントでサイクル実行
/spec-cycle all          # 全コンポーネントでサイクル実行
/spec-cycle backend      # 指定コンポーネントでサイクル実行
/spec-cycle --spec-wins  # 修正方向を仕様優先に固定
/spec-cycle --impl-wins  # 修正方向を実装優先に固定
/spec-cycle --max-iterations 5  # 最大イテレーション数を変更（デフォルト: 3）
```

---

## 実行フロー

```
┌─────────────────┐
│  Step 1: 準備    │
└────────┬────────┘
         ▼
┌─────────────────┐
│  Step 2: Check   │◄──────────────────┐
│  (spec-check)    │                   │
└────────┬────────┘                   │
         ▼                            │
    差分あり？ ─── No ──► 完了         │
         │                            │
        Yes                           │
         ▼                            │
┌─────────────────┐                   │
│  Step 3: Fix     │                   │
│  (spec-fix)      │                   │
└────────┬────────┘                   │
         ▼                            │
┌─────────────────┐                   │
│  Step 4: Verify  │                   │
│  (検証ゲート)     │                   │
└────────┬────────┘                   │
         ▼                            │
    iteration < max? ── Yes ──────────┘
         │
        No
         ▼
   エスカレーション
```

### Step 1: 準備

1. CLAUDE.md の `## Component Mapping` を読み取り
2. 対象コンポーネントを決定
3. 修正方向フラグの確認（--spec-wins / --impl-wins / デフォルト）
4. `max_iterations` の設定（デフォルト: 3）

### Step 2: Check（spec-check 相当）

対象コンポーネントに対して `/spec-check` 相当の整合性チェックを実行。

結果を記録:
```
iteration: {n}
findings: [
  { id: "SPEC-1", type: "Missing", ... },
  { id: "SPEC-2", type: "Diverged", ... },
]
```

**差分 0 件** → Step 5（完了）へ

### Step 3: Fix（spec-fix 相当）

Step 2 の Finding に対して `/spec-fix` 相当の修正を実行。

修正結果を分類:
- **修正成功**: 差分が解消された
- **スキップ**: エスカレーション候補（修正方向不明、設計判断必要）
- **修正失敗**: 検証ゲートで失敗してリバートされた

**全 Finding がスキップ** → 新たに修正できるものがないため、ループを打ち切り

### Step 4: Verify（検証ゲート）

実装に変更があった場合:
1. ビルド / コンパイル
2. 型チェック / Lint
3. テストスイート

CLAUDE.md の `## Commands` を優先使用。

検証ゲート失敗時:
- 失敗原因が今回の修正に起因 → リバート → 該当 Finding をスキップに分類
- 既存のエラー → 修正は維持 → 警告として報告

検証パス後: `iteration < max_iterations` なら Step 2 へ戻る。

### Step 5: 完了判定

| 状態 | 結果 |
|------|------|
| 差分 0 件 | **完了** — 仕様と実装が完全に整合 |
| スキップのみ残存 | **部分完了** — エスカレーション候補を報告 |
| max_iterations 到達 | **停止** — 残存差分を報告 |

---

## 収束保証

無限ループを防ぐ仕組み:

1. **max_iterations 上限**（デフォルト 3）
2. **進捗チェック**: 各イテレーションで Finding 数が減少していない場合、ループを打ち切る
3. **全スキップ検出**: 修正可能な Finding がない場合、即座に打ち切る
4. **同一 Finding 再出現**: 前回修正した Finding が再出現した場合、その Finding をスキップに昇格

---

## 出力形式

```
╔══════════════════════════════════════╗
║  仕様整合性サイクル 完了レポート       ║
║  対象: {component}                   ║
║  イテレーション: {n} / {max}          ║
╚══════════════════════════════════════╝

■ 最終結果: {完了 | 部分完了 | 停止}

■ イテレーション履歴
  #1: 検出 {n} 件 → 修正 {n} / スキップ {n} / 失敗 {n}
  #2: 検出 {n} 件 → 修正 {n} / スキップ {n} / 失敗 {n}
  #3: 検出 0 件 → 完了

■ 検証ゲート
  ビルド:    {pass/fail}
  型チェック: {pass/fail}
  テスト:    {pass/fail}

═══ 修正済みサマリー ═══

  実装修正: {n} 件
  仕様更新: {n} 件

═══ エスカレーション候補 ═══

[E-1] SPEC-5 | Diverged | 修正方向不明
  仕様: DESIGN/05_backend.md:90
  実装: handlers/routes.rs:15
  質問: {ユーザーへの具体的な質問}

═══ 残存差分（max_iterations 到達時） ═══

[R-1] SPEC-8 | Missing | 大規模機能
  仕様: DESIGN/03_optimizer.md:120
  推奨: 個別の実装タスクとして切り出し
```

---

## パイプライン統合

impl-orchestrator からは直接呼ばれない（オーケストレーターは check と fix を個別に制御する）。

以下のシナリオで使用:
- **スタンドアロン**: 開発中に仕様と実装の同期を取りたい時
- **design-phase 後**: 設計変更後の全体整合性回復
- **Sprint 4 (dev-pipeline)**: Phase 3 テストフェーズの最終整合性チェック
