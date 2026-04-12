---
name: dev-pipeline
description: 計画→設計→実装→テスト→報告の全フェーズを統合実行するメタオーケストレーター。エスカレーション駆動でユーザー介入を最小化。
argument-hint: "<task-description>"
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, Agent
model: claude-opus-4-6
---

# 自律開発パイプライン

要件記述から、設計→実装→テスト→報告までを自律的に実行する。
ユーザーの介入は「計画承認」と「エスカレーション応答」の2箇所のみ。

---

## フェーズ概要

```
Phase 0: 計画（対話）      ← ユーザー承認必須
Phase 1: 設計（自律）      ← エスカレーション時のみユーザー介入
Phase 2: 実装（自律）      ← 同上
Phase 3: テスト（自律）
Phase 4: 報告
```

---

## Phase 0: 計画（対話）

### 0-1: 要件の整理

引数の `<task-description>` を元に、以下を整理してユーザーに提示:

```
╔══════════════════════════════════════╗
║  パイプライン計画                     ║
╚══════════════════════════════════════╝

■ タスク概要
  {task-description の要約}

■ スコープ
  - 新規作成: {ファイル/コンポーネント}
  - 変更: {既存ファイル/コンポーネント}
  - 影響範囲: {テスト、設定等}

■ コンポーネント分割案
  1. {component_a} — {責務}
  2. {component_b} — {責務}

■ 技術的アプローチ
  {主要な設計判断・技術選定}

■ リスク・懸念
  {事前に判明しているリスク}

■ 推定規模
  - 設計書: {n} ファイル
  - 実装: {概算ファイル数}

→ この計画で進めてよいですか？ [y / 修正指示]
```

### 0-2: ユーザー承認

**これがパイプライン全体で唯一の必須ゲート。**

- ユーザーが `y` → Phase 1 へ
- ユーザーが修正指示 → 計画を修正して再提示
- ユーザーが中止 → パイプライン終了

### 0-3: PIPELINE-STATE.md 初期化

承認後:
1. `/pipeline-state init {task-name}` 相当の処理を実行
2. 計画サマリーを記入
3. コンポーネント構成を記録

---

## Phase 1: 設計（自律 + エスカレーション）

### 1-1: 設計書生成

`/design-phase` 相当のロジックを実行:

1. 計画サマリーから DESIGN/*.md を生成（sonnet サブエージェント）
2. 既存 DESIGN/*.md がある場合はフォーマットを学習して統一
3. spec-audit 相当の矛盾チェック（opus サブエージェント）
4. 自律修正可能な矛盾を修正

### 1-2: エスカレーション確認

Tier 1 の Finding がある場合:

```
═══ Phase 1 エスカレーション ═══

設計フェーズで以下の判断が必要です:

[E-1] 認証方式の選定
  内容: JWT / Session / OAuth2 のいずれを採用するか
  影響: api_layer, frontend の設計に直結
  → どの方式を採用しますか？

[E-2] DBスキーマにGeoJSON型カラムが必要
  内容: 空間クエリのためにDB側でGeoJSON型をサポートする必要あり
  → GeoJSON型の使用を承認しますか？
```

- ユーザーの回答を受けて設計書を修正
- 全 pending 解消後に次フェーズへ

### 1-3: フェーズ境界処理

1. PIPELINE-STATE.md を更新（設計成果物リスト）
2. PIPELINE-STATE.md の Phase を `design` → `implementation` に遷移
3. Component Mapping が CLAUDE.md にない場合は提案・追記

### 1-4: コンテキスト管理

設計フェーズ完了時にコンテキスト量を自己評価:
- 肥大化している場合 → checkpoint save を実行し `/compact` を推奨
- 設計書の全文がコンテキストにある必要はない（以降は必要時に Read で取得）

---

## Phase 2: 実装（自律 + 並列レビュー + 検証ゲート）

### 2-1: コンポーネント単位の実装ループ

依存順にコンポーネントを処理。各コンポーネントで impl-orchestrator 相当の6ステージを実行:

```
for component in dependency_order:
    Stage 1: 準備（DESIGN/*.md + CLAUDE.md 読み取り）
    Stage 2: 実装（sonnet サブエージェント）
    Stage 3: 検証ゲート（build / type / test）
    Stage 4: 並列レビュー（opus × 3: security / robustness / spec）
    Stage 5: 指摘解決（エスカレーション分類 → 修正 or 報告）
    Stage 6: 完了判定（PIPELINE-STATE.md 更新）
```

### 2-2: 境界テスト

全コンポーネントの実装完了後:

1. `/boundary-test detect` — 境界を検出
2. `/boundary-test generate` — テストを生成
3. `/boundary-test run` — テストを実行
4. 失敗があれば修正（最大3回）

### 2-3: エスカレーション確認

Phase 2 中に蓄積された Tier 1 をまとめて提示。

### 2-4: フェーズ境界処理

1. PIPELINE-STATE.md を更新（実装ステータス）
2. Phase を `implementation` → `testing` に遷移
3. checkpoint save

**コンテキスト管理**: Phase 2 は最もコンテキストが肥大化するフェーズ。
- コンポーネント間で checkpoint save を実行
- 必要に応じて `/compact` を推奨

---

## Phase 3: テスト（自律）

### 3-1: フルテストスイート

プロジェクト全体のテストを実行:

CLAUDE.md の `## Commands` を優先。なければ自動検出:

| マーカー | コマンド |
|---------|---------|
| Cargo.toml | `cargo test --workspace` |
| package.json | `npm test` |
| build.gradle | `./gradlew test` |
| go.mod | `go test ./...` |
| pyproject.toml | `pytest` |

### 3-2: 最終整合性チェック

spec-check 相当のチェックを全コンポーネントに対して実行:
- Missing / Diverged / Extra / Constraint の検出
- 実装フェーズで意図せず乖離が生じていないか確認

### 3-3: 最終堅牢性チェック

robust-review 相当のチェックを変更ファイルに対して実行:
- Phase 2 のレビューで修正した箇所が他の問題を生んでいないか
- 新たな S-Critical / S-High がないか

### 3-4: 問題修正ループ

テスト/チェックで問題が見つかった場合:

```
iteration = 0
while issues_remain and iteration < 3:
    修正を実行
    テストスイート再実行
    整合性再チェック
    iteration++

if issues_remain:
    エスカレーション報告に残存問題を含める
```

### 3-5: フェーズ境界処理

1. PIPELINE-STATE.md を更新（テスト結果）
2. Phase を `testing` → `reporting` に遷移

---

## Phase 4: 報告

### 4-1: 変更概要

```bash
git diff --stat HEAD~{commits}
```

変更ファイル数、追加/削除行数のサマリー。

### 4-2: 最終レポート

```
╔══════════════════════════════════════════════════╗
║  自律開発パイプライン 完了レポート                  ║
║  タスク: {task-name}                              ║
║  フェーズ: Phase 0 → Phase 4                      ║
╚══════════════════════════════════════════════════╝

■ 変更概要
  ファイル: {n} changed, {n} insertions(+), {n} deletions(-)
  設計書: {n} ファイル（DESIGN/）
  実装: {n} ファイル
  テスト: {n} ファイル

■ 検証ゲート結果
  ビルド:       pass ✓
  型チェック:    pass ✓
  テスト:       pass ✓ ({n} passed, {n} failed)
  境界テスト:    pass ✓ ({n} boundaries verified)
  仕様整合性:    pass ✓ (0 差分)
  堅牢性:       pass ✓ (0 S-Critical, 0 S-High)

■ レビュー結果サマリー
  Security:    S-Critical: {n} / S-High: {n} / S-Medium: {n} / S-Low: {n}
  Robustness:  S-Critical: {n} / S-High: {n} / S-Medium: {n} / S-Low: {n}
  Spec:        Missing: {n} / Diverged: {n} / Extra: {n} / Constraint: {n}

■ 対応結果
  自律修正済み:   {n} 件（Tier 2 + Tier 3）
  エスカレーション: {n} 件（Tier 1 — Phase 0-2 で解決済み）

═══ 自律修正ログ（Tier 2: 事後報告） ═══

[1] SEC-1 | S-Critical | handlers/routes.rs:45
  修正: format!() → .bind()（SQLインジェクション対策）

[2] ROB-3 | S-Critical | geo_core/path.rs:78
  修正: unwrap() → ? 変換

[3] SPEC-2 | Diverged | DESIGN/01_geo_core.md:58
  修正: 仕様を更新（Result ラップ追加を反映）

═══ エスカレーション履歴 ═══

[E-1] Phase 1 | 認証方式選定 → resolved: JWT 採用
[E-2] Phase 1 | GeoJSON型 → resolved: 承認済み

═══ 残存リスク ═══

[R-1] ROB-8 | S-Medium | api/search.rs:33 — 空リスト未処理
[R-2] SEC-4 | S-Low | .env.example にサンプル値が残存

═══ 推奨アクション ═══

  - ブラウザでの動作確認: {確認すべきページ/機能}
  - 手動テスト: {自動化できなかったシナリオ}
  - 残存リスクの対応判断
```

### 4-3: PIPELINE-STATE.md 最終更新

Phase を `reporting` に更新。パイプライン完了状態を記録。

---

## エスカレーションポリシー

パイプライン全体を通じたエスカレーションの扱い:

| タイミング | 動作 |
|-----------|------|
| Phase 0（計画） | 即時対話（ユーザーと合意形成中） |
| Phase 1（設計） | 蓄積 → フェーズ末に一括提示 → 回答待ち |
| Phase 2（実装） | 蓄積 → コンポーネント完了ごとに提示 → 回答待ち |
| Phase 3（テスト） | 蓄積 → 最終レポートに含める |

**重要**: エスカレーション待ちでもパイプラインは停止しない。
- pending の Tier 1 がある場合、影響を受けないコンポーネントの作業は続行
- Phase 末でまとめて回答を求め、回答後に影響箇所を修正

---

## コンテキスト管理戦略

| フェーズ境界 | アクション |
|-------------|-----------|
| Phase 0 → 1 | — （コンテキスト小） |
| Phase 1 → 2 | checkpoint save + 設計書を閉じる（以降 Read で必要時取得） |
| Phase 2 内（コンポーネント間） | checkpoint save + `/compact` 推奨 |
| Phase 2 → 3 | checkpoint save + `/compact` 推奨 |
| Phase 3 → 4 | — （レポート生成のみ） |

コンテキストが圧迫された場合の緊急対応:
1. checkpoint save で状態を保存
2. ユーザーに `/clear` を推奨
3. 再開時は PIPELINE-STATE.md + CHECKPOINT.md から状態を復元

---

## 中断と再開

パイプラインは任意のタイミングで中断・再開できる:

### 中断

1. 現在のフェーズの状態を PIPELINE-STATE.md に保存
2. checkpoint save を実行
3. 「`/dev-pipeline` で再開可能」とユーザーに通知

### 再開

`/dev-pipeline` を引数なしで実行:
1. PIPELINE-STATE.md を検出
2. 現在の Phase と状態を読み取り
3. 中断箇所から続行

```
Pipeline "todo-crud-api" を検出しました。
現在: Phase 2 (implementation) — backend コンポーネント完了、frontend 未着手
→ 続行しますか？ [y / 最初からやり直し / 中止]
```

---

## 注意事項

- Phase 0 のユーザー承認は省略不可（安全装置）
- 各フェーズのサブスキル（design-phase, impl-orchestrator 等）のロジックを直接実行する（スキル呼び出しではなく、同等の処理を埋め込む）
- モデル配分: オーケストレーター本体 = opus、実装 = sonnet、レビュー = opus
- 全フェーズを1セッションで完了する必要はない — フェーズ境界で区切り、次セッションで再開可能
