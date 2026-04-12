---
name: spec-fix
description: spec-checkのFindingを元に、仕様書または実装を双方向に自動修正する。修正方向はFinding種別とヒューリスティクスで判定。
argument-hint: "[component-name or 'all'] [--spec-wins | --impl-wins | --dry-run]"
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
model: claude-opus-4-6
---

# 仕様 ↔ 実装 双方向自動修正

`/spec-check` で検出された差分（Missing / Diverged / Extra / Constraint）を修正する。
仕様書と実装のどちらを修正するかは、Finding の種別とヒューリスティクスで判定する。

---

## 使い方

```
/spec-fix                # 直前の spec-check Finding を修正
/spec-fix all            # spec-check all を実行してから修正
/spec-fix backend        # 指定コンポーネントの spec-check → 修正
/spec-fix --spec-wins    # 常に実装側を修正（仕様が正）
/spec-fix --impl-wins    # 常に仕様側を修正（実装が正）
/spec-fix --dry-run      # 修正計画のみ出力
```

---

## 修正方向の判定

### デフォルト（フラグなし）: ヒューリスティクス判定

| Finding 種別 | デフォルト修正方向 | 理由 |
|-------------|-------------------|------|
| **Missing** | 実装を追加 | 仕様にあるべきものが未実装 |
| **Diverged** | ケース判定（下記） | どちらが正しいか文脈による |
| **Extra** | 仕様に追記 | 実装が先行した有用な追加の可能性 |
| **Constraint** | 実装を修正 | 制約は仕様側の絶対ルール |

#### Diverged の修正方向ヒューリスティクス

| 条件 | 方向 | 理由 |
|------|------|------|
| 実装が仕様より堅牢（Result ラップ、Option 化等） | 仕様を更新 | 実装側の改善を採用 |
| テストが実装側の振る舞いを検証済み | 仕様を更新 | テストが通っている実装を尊重 |
| 仕様の方が詳細で具体的 | 実装を修正 | 設計意図を尊重 |
| git blame で実装が最近変更された | 実装を修正 | 意図しない変更の可能性 |
| 判断不能 | **エスカレーション** | ユーザーに方向を確認 |

### --spec-wins: 仕様優先モード

全ての Finding で実装側を修正。仕様書は変更しない。

### --impl-wins: 実装優先モード

全ての Finding で仕様書側を修正。実装は変更しない。

---

## 実行フロー

### Step 1: Finding の取得

1. 会話中に直前の `/spec-check` 出力がある → そこから Finding を抽出
2. 引数指定あり → `/spec-check` 相当のチェックを先に実行
3. どちらもない → `git diff --name-only HEAD` に関連するコンポーネントをチェック

### Step 2: 修正計画の作成

各 Finding について:
1. 修正方向を判定（上記ヒューリスティクス or フラグ）
2. 修正内容を決定
3. 修正の難易度を判定:
   - **自動修正可能**: シグネチャ変更、フィールド追加、型名変更等
   - **半自動**: スケルトン生成 + TODO コメント（Missing の大きな機能）
   - **手動必要**: 設計判断を伴う変更 → エスカレーション

`--dry-run` 指定時はここで停止し、修正計画を出力する。

### Step 3: 修正の実行

#### 実装側の修正（spec-wins / Missing / Constraint）

| Finding | 修正内容 |
|---------|---------|
| Missing (関数) | 仕様書のシグネチャでスケルトン生成 + `todo!()` or 仕様のコードスニペットで実装 |
| Missing (型) | 仕様書の定義をコードに変換 |
| Missing (エンドポイント) | ルーティング + ハンドラスケルトン生成 |
| Diverged (シグネチャ) | 仕様に合わせてシグネチャ変更 + 呼び出し元も修正 |
| Diverged (フィールド) | フィールド名・型を仕様に合わせて変更 |
| Constraint | 違反箇所を制約に準拠する形に修正 |

#### 仕様側の修正（impl-wins / Extra / Diverged の一部）

| Finding | 修正内容 |
|---------|---------|
| Extra | DESIGN/*.md の該当セクションに実装の定義を追記 |
| Diverged (実装が堅牢) | 仕様のシグネチャ・型定義を実装に合わせて更新 |

### Step 4: 検証

修正後に以下を実行:

1. **実装を修正した場合**: ビルド → 型チェック → テスト（検証ゲート）
2. **仕様を修正した場合**: `/spec-check` を再実行して差分が解消されたことを確認
3. **両方修正した場合**: 両方のチェックを実行

検証失敗時:
- 実装修正の失敗 → 修正をリバート → スキップとして報告
- 仕様修正の失敗 → 新たな矛盾が生じていないか確認

### Step 5: エスカレーション判定

以下の場合はエスカレーション候補として報告（自律修正しない）:
- Diverged で修正方向が判断不能
- Missing で機能が大きく、スケルトン生成では不十分
- 修正が他コンポーネントの仕様にも影響する

---

## 出力形式

```
╔══════════════════════════════════════╗
║  仕様整合性修正レポート               ║
║  対象: {component}                   ║
║  モード: {default|spec-wins|impl-wins}║
╚══════════════════════════════════════╝

■ サマリー
  実装修正:    {n} 件
  仕様更新:    {n} 件
  スキップ:    {n} 件（エスカレーション候補）
  検証: build:{result} type:{result} test:{result}

═══ 実装を修正 ═══

[1] SPEC-1 | Missing → 実装追加
  仕様: DESIGN/01_geo_core.md:42
  追加: crates/geo_core/src/distance.rs — pub fn calculate_distance()
  検証: build:pass type:pass test:pass

═══ 仕様を更新 ═══

[2] SPEC-2 | Diverged → 仕様更新（実装が堅牢）
  実装: optimizer.rs:23 — fn optimize() -> Result<Vec<Point>, Error>
  更新: DESIGN/01_geo_core.md:58 — 戻り値を Result 型に変更

═══ スキップ（要ユーザー判断） ═══

[S-1] SPEC-5 | Diverged | 修正方向不明
  仕様: DESIGN/05_backend.md:90 — POST /api/routes
  実装: handlers/routes.rs:15 — PUT /api/routes
  質問: HTTPメソッドはPOSTとPUTのどちらが正しいですか？
```

---

## パイプライン統合

impl-orchestrator の Stage 5 から呼ばれる場合:
- Spec Finding はオーケストレーターのエスカレーション分類を経由
- Constraint 違反は自律修正（Tier 2）
- Missing / Diverged でスコープ外の判断が必要なものは Tier 1 エスカレーション
