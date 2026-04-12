---
name: design-phase
description: 計画サマリーからDESIGN/*.mdを自律生成し、spec-auditで自己検証する。既存仕様書のフォーマットを学習して統一。
argument-hint: "[component-name or 'all'] [--from-scratch | --update]"
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, Agent
model: claude-opus-4-6
---

# 設計フェーズ自動化

計画（要件）から DESIGN/*.md を自律生成し、仕様書間の矛盾を自動検出・修正する。

---

## コマンド

```
/design-phase              # PIPELINE-STATE.md の計画サマリーから全コンポーネントの設計書を生成
/design-phase backend      # 指定コンポーネントのみ
/design-phase --from-scratch  # 既存の DESIGN/*.md を無視して再生成（確認あり）
/design-phase --update     # 既存の DESIGN/*.md を計画に合わせて差分更新
```

---

## 実行フロー

```
Step 1: 入力収集
  ↓
Step 2: フォーマット学習
  ↓
Step 3: 設計書生成（sonnet サブエージェント）
  ↓
Step 4: 矛盾検出（opus サブエージェント — spec-audit 相当）
  ↓
Step 5: 自律修正 or エスカレーション
  ↓
Step 6: PIPELINE-STATE.md 更新
```

---

## Step 1: 入力収集

### 1-1: 計画サマリーの取得

優先順:
1. **PIPELINE-STATE.md** の「計画サマリー」セクション（パイプライン実行時）
2. **会話コンテキスト** — ユーザーが直前に記述した要件（スタンドアロン実行時）
3. どちらもない → ユーザーに要件の入力を求める

### 1-2: プロジェクト情報の取得

CLAUDE.md から取得（存在する場合）:
- **`## Component Mapping`** — 既存コンポーネント構成
- **`## Critical Constraints`** — 設計に反映すべき制約
- **`## Tech Stack`** — 使用技術（言語、FW、DB等）
- **`## Escalation Overrides`** — エスカレーション基準のカスタマイズ

### 1-3: 既存コードの走査

プロジェクトに既存コードがある場合:
1. ディレクトリ構造を把握（`ls -R` or Glob）
2. 主要な型定義・API定義を抽出
3. 設計書との整合性を保つための参考情報とする

---

## Step 2: フォーマット学習

### 2-1: 既存仕様書の検出

```
Glob: DESIGN/*.md, docs/design/*.md, spec/*.md
```

### 2-2: フォーマットの学習

既存の DESIGN/*.md がある場合:
1. 全ファイルを読み込み
2. 共通構造を抽出:
   - セクション構成（見出しの順序と命名）
   - コードスニペットの言語・スタイル
   - 型定義の表記法
   - テーブル・リストの使い方
   - メタデータ（フロントマター等）
3. 学習した構造を「テンプレート」として使用

### 2-3: デフォルトテンプレート

既存仕様書がない場合、以下のデフォルト構造を使用:

```markdown
# {Component Name}

## 概要
{コンポーネントの目的と責務}

## 依存関係
| 依存先 | 用途 |
|--------|------|

## 公開API

### {function/method_name}
```{lang}
{signature}
```
{説明}

## 型定義

### {TypeName}
```{lang}
{definition}
```

## 内部構造
{モジュール構成、主要な内部型}

## エラーハンドリング
{エラー型、エラーケース一覧}

## テスト要件
- [ ] {テストケース1}
- [ ] {テストケース2}

## 制約・注意事項
{Critical Constraints から該当するもの}
```

---

## Step 3: 設計書生成

### 3-1: コンポーネント分割

計画サマリーからコンポーネントを識別:
1. 明示的に分割が記述されている → その通りに分割
2. 記述がない → 責務ベースで分割を提案（フロントエンド / バックエンド / コアロジック / DB層）
3. 既存の Component Mapping がある → それに合わせる

### 3-2: 依存順序の決定

コンポーネント間の依存関係を分析し、基盤から順に設計:
```
例: <基盤層> → <ドメイン層> → <永続化層> → <API層> → <UI層>
```

### 3-3: 設計書の生成（sonnet サブエージェント）

コンポーネントごとに **sonnet モデル** のサブエージェントで生成:

```
Agent(
  description: "{component} の設計書生成",
  model: "sonnet",
  prompt: "
    あなたは設計担当です。以下の要件に基づいてコンポーネントの設計書を作成してください。

    ## 要件
    {計画サマリーの該当部分}

    ## プロジェクト制約
    {CLAUDE.md の Critical Constraints}

    ## 技術スタック
    {CLAUDE.md の Tech Stack、または既存コードから推定}

    ## 依存コンポーネント（設計済み）
    {先に生成された依存先の設計書の公開API部分}

    ## フォーマット
    {Step 2 で学習したテンプレート or デフォルトテンプレート}

    ## ルール
    - 公開APIは具体的なシグネチャ（引数型・戻り値型）まで記述
    - 型定義はフィールドレベルまで記述
    - エラーケースを網羅的に列挙
    - テスト要件は具体的なテストケースとして記述
    - 制約事項を明示的にセクションに記載
    - 依存先の公開APIと整合する形で設計
  "
)
```

### 3-4: --update モードの場合

既存の DESIGN/*.md がある場合:
1. 計画サマリーの変更点を特定
2. 変更が影響するセクションのみ更新
3. 既存の設計判断（過去のエスカレーション結果等）は維持

---

## Step 4: 矛盾検出（spec-audit 相当）

生成された設計書群に対して、**opus モデル** のサブエージェントで矛盾チェック:

```
Agent(
  description: "設計書間矛盾チェック",
  model: "opus",
  prompt: "
    あなたは設計レビューアーです。
    以下の設計書群を読み、仕様書間の矛盾を検出してください。

    {生成された全 DESIGN/*.md の内容}

    チェック項目:
    1. 型名・フィールド名の揺れ
    2. 共有型のフィールド不一致
    3. API契約の不一致（提供側と消費側）
    4. 依存方向の循環
    5. DB スキーマの不整合
    6. 用語の不統一
    7. 定数・設定値の不整合

    各 Finding を以下の形式で出力:
    [AUDIT-N] {Critical|Warning|Info} | {カテゴリ}
      関連: {file1:line} ↔ {file2:line}
      内容: {矛盾の説明}
      推奨: {修正案}
  "
)
```

---

## Step 5: 矛盾の解決

### 5-1: Finding の分類

エスカレーションフレームワークに基づき分類:

| 矛盾の種類 | 分類 | 対応 |
|-----------|------|------|
| 型名揺れ・用語不統一 | Tier 2 | 自律修正 — より一般的/正確な名前に統一 |
| フィールド不一致（軽微） | Tier 2 | 自律修正 — 依存元の定義に合わせる |
| API契約不一致 | Tier 2 | 自律修正 — 提供側の定義を正とする |
| 定数値の不整合 | Tier 2 | 自律修正 — 最初に定義された値に統一 |
| 設計方針に関わる矛盾 | Tier 1 | エスカレーション — ユーザーに判断を仰ぐ |
| ドメインモデルの根本的不整合 | Tier 1 | エスカレーション |
| 依存循環 | Tier 1 | エスカレーション — アーキテクチャ判断が必要 |

### 5-2: 自律修正

Tier 2/3 の矛盾を修正:
1. 該当する DESIGN/*.md を Edit で更新
2. 修正ログを記録

### 5-3: 再チェック

修正後に Step 4 を再実行（最大2回）:
- 修正で新たな矛盾が生じていないか確認
- 2回目でも矛盾が残る → エスカレーション

---

## Step 6: 完了処理

### 6-1: PIPELINE-STATE.md の更新

PIPELINE-STATE.md が存在する場合:

1. 設計成果物セクションを更新:
   ```markdown
   ## 設計成果物
   - [x] DESIGN/01_<component_a>.md
   - [x] DESIGN/02_<component_b>.md
   - [x] DESIGN/03_<component_c>.md
   - [ ] DESIGN/04_<component_d>.md  ← エスカレーション待ち
   ```

2. エスカレーションキューに Tier 1 項目を追加

3. 引き継ぎ内容を記入:
   ```markdown
   ## 次フェーズへの引き継ぎ
   設計完了。エスカレーション #1 の回答後に実装フェーズへ遷移可能。
   注意: <component_d> の <未確定要素> は未確定（#1 待ち）。
   ```

### 6-2: Component Mapping の提案

CLAUDE.md に Component Mapping がない場合:
- 生成した設計書に基づく Component Mapping を提案
- ユーザーの承認後に CLAUDE.md に追記（impl-orchestrator が利用）

---

## 出力形式

```
╔══════════════════════════════════════╗
║  設計フェーズ 完了レポート             ║
║  コンポーネント数: {n}                ║
╚══════════════════════════════════════╝

■ 生成した設計書
  [1] DESIGN/01_<component_a>.md    — <責務の要約>
  [2] DESIGN/02_<component_b>.md    — <責務の要約>
  [3] DESIGN/03_<component_c>.md    — <責務の要約>
  [4] DESIGN/04_<component_d>.md    — <責務の要約>

■ 矛盾チェック結果
  検出: {n} 件 → 自律修正: {n} / エスカレーション: {n}

═══ 自律修正ログ ═══

[1] AUDIT-2 | Warning | 型名揺れ
  修正: <TypeA> / <TypeB> → <TypeA> に統一
  影響: DESIGN/01, DESIGN/03

═══ エスカレーション（ユーザー確認必要） ═══

[E-1] AUDIT-5 | Critical | <設計判断が必要な箇所>
  DESIGN/<component_x>.md — <選択肢A> vs <選択肢B>
  DESIGN/<component_y>.md — <選択肢C> を前提
  質問: <選択肢> のどれを採用しますか？

═══ Component Mapping 提案 ═══
（CLAUDE.md に未定義の場合のみ）

## Component Mapping
| コンポーネント | 仕様書 | 実装ディレクトリ |
|---------------|--------|-----------------|
| <component_a> | DESIGN/01_<component_a>.md | <path/to/component_a>/ |
| <component_b> | DESIGN/02_<component_b>.md | <path/to/component_b>/ |
| <component_c> | DESIGN/03_<component_c>.md | <path/to/component_c>/ |
| <component_d> | DESIGN/04_<component_d>.md | <path/to/component_d>/ |

→ CLAUDE.md に追加しますか？ [y/n]
```

---

## パイプライン統合

dev-pipeline（Sprint 4）の Phase 1 として呼ばれる場合:
- PIPELINE-STATE.md から計画サマリーを自動取得
- エスカレーションキューに pending 項目があればユーザーに提示して回答を待つ
- 全エスカレーション解決後に Phase 2（実装）へ遷移可能

スタンドアロン実行時:
- ユーザーが会話で要件を記述 → それを計画サマリーとして使用
- PIPELINE-STATE.md がなくても動作
