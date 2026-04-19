---
name: spec-audit
description: DESIGN/*.md 仕様書間の矛盾（型名揺れ、フィールド不一致、API契約不一致、依存循環、DBスキーマ不整合、用語不統一、定数不整合）を検出する。USE WHEN 設計書を追加/更新した後の自己検証、design-phase からの自動呼び出し、PR で DESIGN/*.md 変更がある時の事前チェック。SKIP 仕様↔実装の差分検出は spec-check、自動修正は spec-fix を使うこと。
argument-hint: "[component-name or 'all']"
allowed-tools: Read, Grep, Glob, Bash
model: claude-opus-4-7
context: fork
---

# 設計仕様書間 矛盾検出

DESIGN/*.md 間の整合性をチェックし、仕様書同士の矛盾を検出する。
`/spec-check` が「仕様 vs 実装」なのに対し、こちらは「仕様 vs 仕様」。

---

## 準備

### 仕様書の収集

1. CLAUDE.md の `## Component Mapping` から仕様書パスを取得
2. Component Mapping がない場合: `DESIGN/*.md` を直接 Glob で収集
3. DESIGN/ ディレクトリが存在しない場合: 「仕様書が見つかりません」と報告して終了

### 対象の決定

| 引数 | 動作 |
|------|------|
| コンポーネント名 | そのコンポーネントの仕様書 + 依存先の仕様書 |
| `all` | 全仕様書 |
| なし | 全仕様書（`all` と同じ） |

### 仕様書の全文読み込み

対象の全仕様書を読み込み、以下を抽出する:
- 型定義（struct / interface / enum / type alias）
- 関数シグネチャ（pub fn / export function）
- API エンドポイント定義
- DB テーブル / コレクション定義
- 用語定義・ドメインモデル
- 依存関係の記述
- 定数・設定値

---

## チェック項目

### Check 1: 型名・フィールド名の揺れ

同じ概念を表す型が仕様書間で異なる名前を使用していないか。

検出方法:
1. 全仕様書から型定義を抽出
2. 類似名（例: `User` vs `UserInfo`, `Item` vs `ItemRecord`）をペアリング
3. 同一概念かどうかをフィールド構成から判定

出力例:
```
[AUDIT-1] 型名揺れ
  DESIGN/<component_a>.md:<N> — struct <TypeA> { <field_x>: T, <field_y>: T }
  DESIGN/<component_b>.md:<N> — struct <TypeB> { <field_from>: T, <field_to>: T }
  推奨: 型名とフィールド名を統一（<TypeA> / <field_x>, <field_y> に統一を推奨）
```

### Check 2: 共有型のフィールド不一致

複数の仕様書で参照される型のフィールド定義が一致しているか。

検出方法:
1. 同名の型が複数の仕様書に出現するケースを抽出
2. フィールドの名前・型・数を比較

### Check 3: API 契約の不一致

あるコンポーネントが提供する API と、別のコンポーネントが期待する API が一致しているか。

検出方法:
1. 各仕様書の「公開 API」と「依存関係 / 外部呼び出し」セクションを抽出
2. 提供側のシグネチャ / エンドポイントと消費側の呼び出し期待を照合

出力例:
```
[AUDIT-2] API契約不一致
  提供: DESIGN/<provider>.md:<N> — GET /<api_path> → Vec<<Item>>
  消費: DESIGN/<consumer>.md:<N> — fetch("/<api_path>") → expects { items: <Item>[] }
  差分: レスポンスが配列直接 vs オブジェクトラップ
  推奨: レスポンス形式を統一
```

### Check 4: 依存方向の循環

コンポーネント間の依存関係に循環がないか。

検出方法:
1. 各仕様書の依存関係セクションから有向グラフを構築
2. 循環検出（DFS + バックエッジ）

### Check 5: DB スキーマの不整合

DB 関連の仕様が複数箇所で定義されている場合の不整合。

検出方法:
1. テーブル / カラム定義を全仕様書から抽出
2. 同一テーブルの定義が複数ある場合、カラム・型・制約を比較

### Check 6: 用語の不統一

ドメイン用語が仕様書間で統一されているか。

検出方法:
1. 各仕様書の見出し・定義セクションから主要用語を抽出
2. 同義語（例: 「ユーザー」「利用者」「アカウント」などドメイン用語の揺れ）を検出
3. 英語 / 日本語 / 略語の混在を検出

### Check 7: 定数・設定値の不整合

複数仕様書で参照される定数（ポート番号、制限値、タイムアウト等）の値が一致しているか。

---

## 深刻度分類

| 深刻度 | 基準 | 例 |
|--------|------|-----|
| **Critical** | ビルド・実行時に必ず問題を起こす矛盾 | 型フィールドの不一致、API契約の破綻 |
| **Warning** | 混乱を招く不整合 | 型名揺れ、用語不統一 |
| **Info** | 改善推奨だが実害なし | 記述スタイルの不統一、コメント不足 |

---

## 出力形式

```
╔══════════════════════════════════════╗
║  仕様書間矛盾チェック結果             ║
║  対象: {n} 仕様書                    ║
╚══════════════════════════════════════╝

■ サマリー
  Critical: {n} 件 — 必ず解決
  Warning:  {n} 件 — 解決推奨
  Info:     {n} 件 — 改善余地

═══ Critical ═══

[AUDIT-1] API契約不一致
  DESIGN/<provider>.md:<N> — GET /<api_path> → Vec<<Item>>
  DESIGN/<consumer>.md:<N> — expects { items: <Item>[] }
  推奨: レスポンス形式を統一

═══ Warning ═══

[AUDIT-3] 型名揺れ
  DESIGN/<component_a>.md:<N> — <TypeA>
  DESIGN/<component_b>.md:<N> — <TypeB>
  推奨: <TypeA> に統一

═══ Info ═══

[AUDIT-5] 用語不統一
  「<用語A>」(DESIGN/<a>, <b>) vs 「<用語B>」(DESIGN/<c>)
  推奨: 用語集を作成して統一
```

---

## パイプライン統合

impl-orchestrator では直接使用しない（実装フェーズではなく設計フェーズのツール）。

design-phase（Sprint 3）から呼ばれる場合:
- 設計生成後の自己検証として実行
- Critical の矛盾は自律修正を試行
- ドメイン知識が必要な矛盾はエスカレーション

スタンドアロン実行:
- 設計レビュー時に手動で実行
- PR で DESIGN/*.md に変更がある場合の事前チェック
