---
name: spec-check
description: DESIGN仕様書と実装コードの整合性をチェックし、Missing/Diverged/Extra/Constraintの4分類で差分を報告する。
argument-hint: "[component-name or 'all']"
allowed-tools: Read, Grep, Glob, Bash
model: claude-opus-4-6
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
| geo_core | DESIGN/01_geo_core.md | crates/geo_core/src/ |
| backend | DESIGN/05_backend.md | crates/backend/src/ |
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
| **Constraint** | 設計制約に違反している | no_std 違反、座標系順序違反 |

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

制約ごとに具体的な検出方法を決定:
- `no_std` → `std::` import の Grep
- 座標系順序 → 変換境界での引数順序チェック
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
  仕様: DESIGN/01_geo_core.md:42 — pub fn calculate_distance(p1: Point, p2: Point) -> f64
  実装: （なし）
  推奨: 実装を追加

═══ Diverged ═══

[SPEC-2] Diverged | 関数シグネチャ
  仕様: DESIGN/01_geo_core.md:58 — fn optimize(route: &[Point]) -> Vec<Point>
  実装: crates/geo_core/src/optimizer.rs:23 — fn optimize(route: &[Point]) -> Result<Vec<Point>, Error>
  推奨: 仕様を更新（実装の方が堅牢）

═══ Extra ═══

[SPEC-3] Extra | 関数
  実装: crates/geo_core/src/utils.rs:15 — pub fn debug_print(route: &Route)
  推奨: 仕様に追記、または内部関数に変更

═══ Constraint ═══

[SPEC-4] Constraint | no_std 違反
  ファイル: crates/geo_core/src/math.rs:3
  制約: geo_core は no_std（CLAUDE.md Critical Constraints）
  違反: use std::collections::HashMap
  修正案: use hashbrown::HashMap（no_std 互換）
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
