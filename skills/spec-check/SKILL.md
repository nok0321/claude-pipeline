---
name: spec-check
description: DESIGN/*.md と実装コードの整合性チェック。差分を Missing（仕様にあるが未実装）/ Diverged（不一致）/ Extra（仕様外実装）/ Constraint（設計制約違反）の4分類で報告する。USE WHEN 実装完了後の整合性確認、impl-orchestrator Stage 4 の Spec Reviewer、PR 前の最終確認。SKIP 仕様書同士の矛盾検出は spec-audit、自動修正したい時は spec-fix を直接使うこと。
argument-hint: "[component-name or 'all']"
allowed-tools: Read, Grep, Glob, Bash
model: claude-opus-4-7
context: fork
---

# 設計仕様 ↔ 実装 整合性チェック

DESIGN/*.md の仕様書と実装コードを照合し、差分を報告する。

---

## 準備

### コンポーネントマッピングの取得

CLAUDE.md の `## Component Mapping` を読み取る:

```markdown
## Component Mapping
| コンポーネント | 仕様書 | 実装ディレクトリ |
|---------------|--------|-----------------|
| <component_a> | DESIGN/01_<component_a>.md | <path/to/component_a>/ |
| <component_b> | DESIGN/02_<component_b>.md | <path/to/component_b>/ |
```

**Component Mapping が存在しない場合:**
1. DESIGN/ ディレクトリが存在するか確認
2. 存在する場合: DESIGN/*.md のファイル名からコンポーネント名を推定し、プロジェクト構造から実装ディレクトリを探索
3. 存在しない場合: 「DESIGN/ ディレクトリと Component Mapping が見つかりません」と報告して終了

### 対象の決定

| 引数 | 動作 |
|------|------|
| コンポーネント名 | 該当コンポーネントのみ |
| `all` | Component Mapping の全コンポーネント |
| なし | `git diff --name-only HEAD` に関連するコンポーネントを自動判定 |

### プロジェクト固有情報

CLAUDE.md から追加取得（存在する場合のみ）:
- **`## Critical Constraints`** — Constraint チェックに使用
- **`## Project-Specific Checks`** — 追加のチェック項目

---

## 差分分類

| 分類 | 意味 | 典型例 |
|------|------|--------|
| **Missing** | 仕様に定義があるが実装が存在しない | 関数未実装、エンドポイント未作成 |
| **Diverged** | 実装が仕様と異なる | 引数型の不一致、フィールド名の違い |
| **Extra** | 仕様に無い実装が存在する | 仕様外の追加API（意図的拡張の可能性） |
| **Constraint** | 設計制約に違反している | アーキテクチャ制約違反、データ形式順序違反 |

---

## チェック手順

### Step 1: 公開 API の存在確認

仕様書に記載された公開インターフェースが実装に存在するか:

| 言語 | 検索対象 |
|------|---------|
| Rust | `pub fn`, `pub struct`, `pub enum`, `pub trait`, `pub type` |
| TypeScript | `export function`, `export class`, `export interface`, `export type`, `export const` |
| Go | 大文字始まりの関数・型・定数 |
| Java | `public class`, `public interface`, `public enum` |
| Python | `def` (モジュールレベル), `class` |

仕様にあるが実装にない → **Missing**
実装にあるが仕様にない → **Extra**

### Step 2: 関数シグネチャの照合

仕様書のシグネチャと実装を比較:
- 引数の名前・型・順序
- 戻り値の型
- ジェネリクス / 型パラメータ
- 可視性 (pub / export)

不一致 → **Diverged**

**例外**: 実装が仕様より堅牢な場合（例: 戻り値を `Result` でラップ）は Diverged + 仕様更新推奨として報告。

### Step 3: 型 / 構造体フィールドの照合

仕様書の構造体・インターフェース定義と実装を比較:
- フィールド名・型・可視性
- enum バリアント
- デフォルト値

### Step 4: API エンドポイントの照合

仕様書に REST API 定義がある場合:
- Method (GET/POST/PUT/DELETE)
- Path
- リクエスト / レスポンス型
- ステータスコード

実装のルーティング定義（Router, @app.route, @RequestMapping 等）と照合。

### Step 5: DB スキーマの照合

仕様書にテーブル / コレクション定義がある場合:
- テーブル名 / カラム名 / 型
- インデックス
- 外部キー制約

実装のマイグレーション / スキーマ定義と照合。

### Step 6: 設計制約の確認

CLAUDE.md の `## Critical Constraints` に記載された制約が実装で守られているか:

制約ごとに具体的な検出方法を決定（例）:
- アーキテクチャ制約（特定ディレクトリで禁止依存）→ import 文の Grep
- データ形式順序 → 変換境界での引数順序チェック
- フレームワーク規約 → 引数順序・デコレータ順序等

違反 → **Constraint**

---

## 出力形式

```
╔══════════════════════════════════════╗
║  仕様整合性チェック結果               ║
║  対象: {component}                   ║
╚══════════════════════════════════════╝

■ サマリー
  Missing:    {n} 件 — 仕様にあるが未実装
  Diverged:   {n} 件 — 仕様と実装が不一致
  Extra:      {n} 件 — 仕様に無い実装
  Constraint: {n} 件 — 設計制約違反

═══ Missing ═══

[SPEC-1] Missing | 公開API
  仕様: DESIGN/<component>.md:<N> — pub fn <function_name>(<args>) -> <ReturnType>
  実装: （なし）
  推奨: 実装を追加

═══ Diverged ═══

[SPEC-2] Diverged | 関数シグネチャ
  仕様: DESIGN/<component>.md:<N> — fn <function_name>(<args>) -> <ReturnType>
  実装: <path/to/file>:<N> — fn <function_name>(<args>) -> Result<<ReturnType>, Error>
  推奨: 仕様を更新（実装の方が堅牢）

═══ Extra ═══

[SPEC-3] Extra | 関数
  実装: <path/to/file>:<N> — pub fn <helper_name>(<args>)
  推奨: 仕様に追記、または内部関数に変更

═══ Constraint ═══

[SPEC-4] Constraint | アーキテクチャ制約違反
  ファイル: <path/to/file>:<N>
  制約: <component> は <禁止依存>（CLAUDE.md Critical Constraints）
  違反: <違反している import/呼び出し>
  修正案: <代替手段>
```

全チェック項目がクリーンの場合は「仕様と実装は完全に整合しています」と報告する。

---

## パイプライン統合

impl-orchestrator の Stage 4 (Agent 3: Spec Compliance Reviewer) から呼ばれる場合:
- 対象ファイルとマッピングはオーケストレーターから渡される
- Finding はオーケストレーターの統合フォーマットに変換される

スタンドアロン実行時:
- CLAUDE.md から自分で Component Mapping を取得
- 出力後、`/spec-fix` での修正を推奨
