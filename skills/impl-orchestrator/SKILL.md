---
name: impl-orchestrator
description: DESIGN仕様書から自律的に実装→検証ゲート→並列レビュー→修正のループを実行するオーケストレーター。
argument-hint: "[component-name or 'all']"
allowed-tools: Read, Write, Edit, MultiEdit, Bash, Grep, Glob, Agent
model: claude-opus-4-6
---

# 実装オーケストレーター

DESIGN/*.md の仕様書を元に、以下の6ステージを自律的にループ実行する:

```
Stage 1: 準備 → Stage 2: 実装(sonnet) → Stage 3: 検証ゲート
  → Stage 4: 並列レビュー(opus×3) → Stage 5: 指摘解決 → Stage 6: 完了判定
```

---

## 内部状態（維持する）

```
component: <対象コンポーネント名>
iteration: 1 / 3
design_files: []     # 対応する DESIGN/*.md
impl_files: []       # 実装対象ファイル
gate_results: {}     # 検証ゲート結果
findings: []         # レビュー Finding の累積
escalation_queue: [] # Tier 1 エスカレーション項目
```

---

## Stage 1: 準備

### 1-1: プロジェクト情報の取得

CLAUDE.md から以下を読み取る:

1. **Component Mapping** — コンポーネントと仕様書・実装ディレクトリの対応
   ```
   ## Component Mapping
   | コンポーネント | 仕様書 | 実装ディレクトリ |
   ```
   - このセクションが存在しない場合: **エスカレーション**（「Component Mapping が CLAUDE.md に未定義です。定義してください」）

2. **Commands** — ビルド/テスト/lint コマンド

3. **Critical Constraints** — 制約事項（座標系順序、no_std 等）

4. **Project-Specific Checks** — プロジェクト固有のチェック項目

5. **Escalation Overrides** — エスカレーション基準のオーバーライド（存在する場合のみ）

### 1-2: 仕様書の読み込み

引数のコンポーネントに対応する DESIGN/*.md を全て読み取る。

- 引数が `all` の場合: Component Mapping に列挙された全コンポーネントを依存順に処理
- 依存順序: CLAUDE.md に記載がなければ、仕様書の依存関係セクションから推定

### 1-3: PIPELINE-STATE.md の確認

存在する場合: 前フェーズの文脈（計画サマリー、エスカレーションキュー）を読み取る。
存在しない場合: 初期化なしで続行（スタンドアロン実行モード）。

### 1-4: 実装計画の作成

仕様書から実装単位（ファイル単位）を列挙し、依存順に並べる。
TaskCreate で進捗を管理する。

---

## Stage 2: 実装（sonnet サブエージェント）

コンポーネントの実装を **sonnet モデルのサブエージェント** に委任する。

### 2-1: 実装エージェントの生成

```
Agent(
  description: "{component} の実装",
  model: "sonnet",
  prompt: "
    あなたは実装担当です。以下の仕様書に従ってコードを実装してください。

    ## 仕様書
    {DESIGN/*.md の内容}

    ## プロジェクト制約
    {CLAUDE.md の Critical Constraints}

    ## 実装ディレクトリ
    {Component Mapping から特定したパス}

    ## ルール
    - 仕様書のコードスニペットをベースに実装
    - CLAUDE.md の NEVER ルールを厳守
    - 既存コードのパターンに合わせる
    - テストも仕様書のテスト要件に従って追加
    - 完了したら実装したファイル一覧を報告
  "
)
```

### 2-2: 実装結果の確認

エージェントの報告から実装ファイル一覧を `impl_files` に記録。

---

## Stage 3: 検証ゲート

全て機械的なチェック。エスカレーション判断に依存しない。**全パスが必須。**

### 3-1: ビルド/コンパイル

CLAUDE.md の Commands セクションから適切なコマンドを選択して実行。

コマンドが不明な場合の自動検出:
| マーカーファイル | コマンド |
|----------------|---------|
| Cargo.toml | `cargo check --workspace` |
| package.json | `npm run build` or `npx tsc --noEmit` |
| build.gradle / pom.xml | `./gradlew compileJava` or `mvn compile` |
| go.mod | `go build ./...` |

### 3-2: 型チェック / Lint

| マーカー | コマンド |
|---------|---------|
| Cargo.toml | `cargo clippy --workspace -- -D warnings` |
| tsconfig.json + svelte | `npx svelte-check` |
| tsconfig.json | `npx tsc --noEmit` |
| pyproject.toml / ruff.toml | `ruff check .` |
| go.mod | `go vet ./...` |

### 3-3: テストスイート

| マーカー | コマンド |
|---------|---------|
| Cargo.toml | `cargo test --workspace` |
| package.json | `npm test` |
| build.gradle | `./gradlew test` |
| go.mod | `go test ./...` |

### 3-4: 境界契約テスト（オプション）

境界テストファイルが存在する場合のみ実行（Sprint 2 で追加予定）:
```
Glob: **/boundary_*.{rs,ts,test.ts,java}
```
存在すれば通常のテストスイートに含まれるため、3-3 でカバーされる。

### 3-5: ゲート失敗時の処理

1. エラー出力を解析し、失敗原因を特定
2. 自律修正を試行（最大3回）:
   - コンパイルエラー → エラーメッセージに基づき修正
   - テスト失敗 → 失敗テストの期待値と実装を照合して修正
   - lint 警告 → 警告に基づき修正
3. 3回失敗 → **エスカレーション**:
   ```
   Tier 1: 検証ゲートが最大リトライ後もパスしない
   内容: {ゲート名} が3回修正後も失敗。エラー: {エラー概要}
   ```

### 3-6: ゲート結果の記録

`gate_results` に各ゲートの結果を記録:
```
gate_results: {
  build: "pass",
  type_check: "pass",
  test_suite: "pass (42 passed, 0 failed)",
  boundary: "skipped (no boundary tests found)"
}
```

---

## Stage 4: 並列レビュー（opus サブエージェント ×3）

検証ゲートを全パスした後、3つの **opus モデル** レビューエージェントを **同時に** 生成する。

### 4-1: レビューエージェントの準備

REVIEW-AGENTS.md を読み取り、プレースホルダーを展開:

| プレースホルダー | 値 |
|-----------------|-----|
| `{target_files}` | Stage 2 で実装/変更されたファイル一覧 |
| `{design_docs}` | Stage 1 で読み取った DESIGN/*.md 一覧 |
| `{project_checks}` | CLAUDE.md の Critical Constraints + Project-Specific Checks |
| `{component_mapping}` | CLAUDE.md の Component Mapping |

### 4-2: 3エージェントの同時生成

**重要: 3つのAgent呼び出しを単一メッセージ内で並列実行する。**

```
Agent(
  description: "Security Review: {component}",
  model: "opus",
  prompt: "{REVIEW-AGENTS.md の Agent 1 テンプレートをプレースホルダー展開した内容}"
)

Agent(
  description: "Robustness Review: {component}",
  model: "opus",
  prompt: "{REVIEW-AGENTS.md の Agent 2 テンプレートをプレースホルダー展開した内容}"
)

Agent(
  description: "Spec Compliance Review: {component}",
  model: "opus",
  prompt: "{REVIEW-AGENTS.md の Agent 3 テンプレートをプレースホルダー展開した内容}"
)
```

### 4-3: エージェント失敗時のフォールバック

- タイムアウト（5分超）→ 該当軸をスキップし `findings` に記録:
  ```
  { agent: "security", status: "timeout", note: "事後報告: セキュリティレビューがタイムアウト" }
  ```
- エラー終了 → 同上（status: "error"）
- 残り2軸の結果で続行

### 4-4: Finding の統合

3エージェントの出力から Finding を抽出し、`findings` に追加。
同一ファイル・同一行の重複 Finding は統合（より高い深刻度を採用）。

---

## Stage 5: 指摘解決

### 5-1: エスカレーション分類

各 Finding をエスカレーションフレームワーク（`/escalation` スキル）の基準で分類。

CLAUDE.md に `## Escalation Overrides` がある場合はオーバーライドを優先適用。

### 5-2: Tier 1（必ずエスカレーション）

- `escalation_queue` に追加
- PIPELINE-STATE.md のエスカレーションキューにも追加（存在する場合）
- **作業は停止しない** — 他の Finding の処理を続行し、最後にまとめて報告

### 5-3: Tier 2（自律対応 + 事後報告）

1. Finding の修正を実行
2. 修正後に **Stage 3 の検証ゲートを再実行**（全パス確認）
3. 事後報告用の修正ログを記録:
   ```
   [自律対応] SEC-1 | S-Critical | backend/handlers/routes.rs:45
     修正: format!() → .bind() に変更（SQLインジェクション対策）
     検証: cargo test --workspace → PASS
   ```

### 5-4: Tier 3（自律対応、報告不要）

1. Finding の修正を実行
2. 修正後に検証ゲート通過を確認

### 5-5: 設計変更が必要な場合

レビューで「仕様書に記載のない新規要件」や「設計の根本的な問題」が見つかった場合:

1. **1回目**: DESIGN/*.md を更新 → Stage 2 に戻って再実装
2. **2回目以降**: **エスカレーション**（設計変更ループの上限）

---

## Stage 6: 完了判定

### 6-1: 状態確認

```
open_findings = findings.filter(status == "open")
tier1_pending = escalation_queue.filter(status == "pending")
```

### 6-2: 判定ロジック

| 条件 | 行動 |
|------|------|
| `open_findings == 0` | **完了** → 報告出力 |
| `open_findings > 0` ∧ `iteration < 3` | `iteration += 1` → Stage 4 へ |
| `iteration == 3` | **停止** → 残存 Finding を報告 |

### 6-3: PIPELINE-STATE.md の更新

存在する場合、実装ステータステーブルを更新:
```
| {component} | done | build:{result} type:{result} test:{result} | security:{result} robustness:{result} spec:{result} |
```

### 6-4: コンテキスト管理

コンポーネント処理完了ごとに:
- 引数が `all` で複数コンポーネントを処理中 → 次のコンポーネントに進む前にコンテキスト量を自己評価
- 肥大化している場合 → checkpoint save を実行し、`/compact` を推奨

---

## 最終報告

```
╔══════════════════════════════════════════════════╗
║  実装オーケストレーター 完了レポート               ║
║  対象: {component}                               ║
║  イテレーション: {iteration} / 3                  ║
╚══════════════════════════════════════════════════╝

■ 検証ゲート結果
  ビルド:       {pass/fail}
  型チェック:    {pass/fail}
  テスト:       {pass/fail} ({passed} passed, {failed} failed)
  境界テスト:    {pass/fail/skipped}

■ レビュー結果サマリー
  Security:    S-Critical: {n} / S-High: {n} / S-Medium: {n} / S-Low: {n}
  Robustness:  S-Critical: {n} / S-High: {n} / S-Medium: {n} / S-Low: {n}
  Spec:        Missing: {n} / Diverged: {n} / Extra: {n} / Constraint: {n}

■ 対応結果
  自律修正済み:   {n} 件（Tier 2 + Tier 3）
  エスカレーション: {n} 件（Tier 1 — 以下に詳細）

═══ 自律修正ログ（Tier 2: 事後報告） ═══

[1] SEC-1 | S-Critical | handlers/routes.rs:45
  修正: format!() → .bind()（SQLインジェクション対策）
  検証: test suite PASS

[2] ROB-3 | S-High | geo_core/path.rs:78
  修正: unwrap() → ? 変換
  検証: test suite PASS

═══ エスカレーション（Tier 1: ユーザー確認必要） ═══

[E-1] SPEC-2 | Missing | 仕様書に未定義のAPIが必要
  内容: {詳細}
  質問: {ユーザーへの具体的な質問}

═══ 残存 Finding（未解決） ═══

（iteration 上限到達時のみ）

═══ 次のアクション ═══
  - エスカレーション項目への回答
  - 手動確認: {ブラウザでの動作確認等}
```

---

## 注意事項

- Component Mapping が CLAUDE.md にない場合は Stage 1 でエスカレーションし停止
- 検証ゲートの build/test コマンドは CLAUDE.md の Commands を最優先で使用
- レビューエージェントは opus モデル（判断力重視）、実装エージェントは sonnet モデル（コスト効率重視）
- 設計変更の逆流は最大1回（2回目はエスカレーション）
- `all` 指定時はコンポーネント間で context が肥大化するため、適宜 checkpoint を推奨
