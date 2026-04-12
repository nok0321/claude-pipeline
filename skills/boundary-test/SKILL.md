---
name: boundary-test
description: コンポーネント間の境界契約（API型、座標変換、DB↔App、WASM��TS等）を検出し、境界テストを自動生成する。
argument-hint: "[detect | generate | run | all] [component-name]"
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
model: claude-opus-4-6
---

# 境界契約テスト

コンポーネント間の境界（API、WASM、DB、変換関数等）を自動検出し、契約テストを生成・実行する。
レビューの「判断」に頼らず、型不一致・変換ミスを機械的に検出する。

---

## コマンド

```
/boundary-test detect              # 境界を検出して一覧表示
/boundary-test detect backend      # 指定コンポーネントの境界のみ
/boundary-test generate            # 検出した境界のテストを生成
/boundary-test generate backend    # 指定コンポーネントのテストのみ生成
/boundary-test run                 # 既存の境界テストを実行
/boundary-test all                 # detect → generate → run を一括実��
```

---

## Step 1: 境界の検出（detect）

### 1-1: プロジェクト情報の取得

CLAUDE.md から取得（存在する場合）:
- **`## Component Mapping`** — コンポーネントと実装ディレクトリの対応
- **`## Critical Constraints`** — 変換ルール等の制約（座標系順序等）
- **`## Boundary Definitions`** — プロジェクト固有の境界定義（存在する場合）

Component Mapping がない場合: プロジェクト構造から自動推定。

### 1-2: 境界タイプ別の検出

#### Type A: REST API ↔ Frontend

**ソース側（API）検出:**

| 言語/FW | 検索パターン |
|---------|-------------|
| Rust (Axum) | `async fn` + ハンドラ型（`Json<T>`, `Path<T>`, `State<T>`）|
| Rust (Actix) | `#[get]`, `#[post]` + ハンドラ関数 |
| Node (Express) | `router.get`, `router.post` + レスポンス型 |
| Python (FastAPI) | `@app.get`, `@app.post` + Pydantic モデル |
| Java (Spring) | `@GetMapping`, `@PostMapping` + DTO クラス |
| Go (gin/echo) | `r.GET`, `r.POST` + レスポンス構造体 |

**消費側（Frontend）検出:**

| パターン | 検索対象 |
|---------|---------|
| fetch / axios | `fetch("`, `axios.get(`, `axios.post(` + URL パターン |
| 型定義 | レスポンスの interface / type 定義 |
| API クライアント | 生成された client（openapi-generator 等） |

**マッチング:** URL パス + HTTP メソッドで対応付け。

#### Type B: WASM ↔ TypeScript

**ソース側（WASM）検出:**

| 言語 | 検索パターン |
|------|-------------|
| Rust | `#[wasm_bindgen]` + `pub fn` / `pub struct` |
| Go | `//export` ディレクティブ |
| C/C++ | `EMSCRIPTEN_KEEPALIVE` |

**消費側（TypeScript）検出:**
- WASM import: `import { ... } from '*.wasm'` / `init()` パターン
- 型定義: 対応する `.d.ts` ファイル

**マッチング:** エクスポート名で対応付け。

#### Type C: DB ↔ Application

**スキーマ側検出:**

| 方式 | 検索パターン |
|------|-------------|
| マイグレーション | `CREATE TABLE`, `ALTER TABLE` (SQL) |
| ORM 定義 | `#[derive(Entity)]`, `@Entity`, `models.Model`, `Schema({` |
| SurrealQL | `DEFINE TABLE`, `DEFINE FIELD` |

**アプリケーション側検出:**
- モデル構造体 / Entity クラス
- クエリ内のカラム参照

**マッチング:** テーブル名 + カラム名で対応付け。

#### Type D: 変換境界（座標系、単位、エンコーディング等）

CLAUDE.md の `## Critical Constraints` から変換ルールを抽出。

検出方法:
1. 変換関数の Grep（`to_`, `from_`, `convert_`, `transform_`）
2. 制約に記載された型ペア間の変換関数を特定
3. ラウンドトリップ可能な変換ペアを識別

例（座標系）:
```
制約: geo_core=[lat,lon], SurrealDB=[lon,lat], Leaflet=[lat,lon]
検出: to_surrealdb_point(), from_surrealdb_point()
テスト: point → to_surrealdb → from_surrealdb → assert_eq(point)
```

### 1-3: 検出結果の出力

```
╔══════���═══════════════════════════════╗
║  境界検出結果                         ║
╚══════��═══════════════════════════════╝

■ サマリー
  Type A (REST API ↔ Frontend):  {n} 境界
  Type B (WASM ↔ TypeScript):    {n} 境界
  Type C (DB ↔ Application):     {n} 境界
  Type D (変換境界):              {n} 境界

═══ Type A: REST API ↔ Frontend ═══

[A-1] GET /api/routes
  API: backend/handlers/routes.rs:23 → Json<Vec<Route>>
  FE:  frontend/src/api/routes.ts:15 → expects Route[]
  状態: 型一致 ✓ / テストなし ✗

[A-2] POST /api/routes
  API: backend/handlers/routes.rs:45 → Json<CreateRouteResponse>
  FE:  frontend/src/api/routes.ts:28 → expects { id: string }
  状態: 型不一致 ✗ — レスポンス形状が異なる

═══ Type D: 変換境界 ═══

[D-1] Point座標系変換
  制約: geo_core=[lat,lon] ↔ SurrealDB=[lon,lat]
  変換: geo_core/convert.rs:10 — to_surrealdb_point / from_surrealdb_point
  状態: テストなし ✗
```

---

## Step 2: テスト生成（generate）

### 2-1: 言語別テスト配置

| 言語 | テストファイル | フレームワーク |
|------|--------------|---------------|
| Rust | `tests/boundary_*.rs` | `#[tokio::test]` + reqwest (API) / 直接呼び出し (変換) |
| TypeScript | `__tests__/boundary_*.test.ts` or `*.boundary.test.ts` | vitest / jest |
| Python | `tests/test_boundary_*.py` | pytest |
| Java | `src/test/**/Boundary*IT.java` | JUnit5 + TestContainers + MockMvc |
| Go | `*_boundary_test.go` | testing パッケージ |

CLAUDE.md に `## Test Conventions` がある場合はその配置規約に従う。

### 2-2: 境界タイプ別テスト生成

#### Type A: REST API ↔ Frontend テスト

```
テスト戦略: レスポンスJSON構造の一致検証

1. APIエンドポイントにリクエストを送信
2. レスポンスのJSON構造（フィールド名・型）を検証
3. Frontend側の型定義と照合

検証項目:
- レスポンスのフィールド名がFE型定義と一致
- フィールドの型（string/number/boolean/array/object）が一致
- 必須/オプショナルフィールドが一致
- ネストしたオブジェクトの構造が一致
- 配列要素の型が一致
```

#### Type B: WASM ↔ TypeScript テスト

```
テスト戦略: 型付き入出力の形状一致

1. WASM関数を直接呼び出し
2. 入力型の変換が正しいか検証
3. 出力型がTypeScript側の期待と一致するか検証

検証項目:
- 引数の型変換（JS → WASM）が正しい
- 戻り値の型変換（WASM → JS）が正しい
- エラーハンドリングが正しく伝播する
```

#### Type C: DB ↔ Application テスト

```
テスト戦略: ラウンドトリップ（insert → select → assert）

1. アプリケーションモデルからDBへ挿入
2. DBから読み取り
3. 元のモデルと一致するか検証

検証項目:
- 全フィールドが正しくマッピングされる
- 型変換（DateTime, JSON, Enum等）が正しい
- NULL/デフォルト値のハンドリング
- 関連テーブルの整合性
```

#### Type D: 変換境界テスト

```
テスト戦略: ラウンドトリップ（値 → 変換 → 逆変換 → 一致）

1. テスト値を用意（通常値 + エッジケース）
2. 正方向変換を実行
3. 逆方向変換を実行
4. 元の値と一致するか検証

テスト値:
- 通常値（代表的な値）
- 境界値（0, 最大, 最小, 負数）
- エッジケース（NaN, Infinity, 空, 極座標の特異点等）

検証項目:
- ラウンドトリップの一致（epsilon許容）
- 中間値の範囲チェック（変換後の値が期待範囲内か）
```

### 2-3: 既存テストとの重複チェック

生成前に既存テストを Grep し、同等の検証が既に存在する場合はスキップ。

---

## Step 3: テス��実行（run）

### 3-1: 境界テストの検出

```
Glob: **/boundary_*.{rs,ts,test.ts,test.js,py,java,go}
Glob: **/*.boundary.test.{ts,js}
Glob: **/Boundary*IT.java
Glob: **/*_boundary_test.go
```

### 3-2: 言語別実行

CLAUDE.md の `## Commands` を優先。なければ自動検出:

| 言語 | コマンド |
|------|---------|
| Rust | `cargo test --test 'boundary_*'` |
| TypeScript | `npx vitest run --reporter verbose **/*.boundary.test.ts` or `npx jest --testPathPattern boundary` |
| Python | `pytest tests/test_boundary_*.py -v` |
| Java | `./gradlew test --tests '*BoundaryIT*'` |
| Go | `go test -run Boundary ./...` |

### 3-3: 結果の出力

```
╔══════════════════════════════════════╗
║  境界テスト実行結果                   ║
╚═══��══════════��═══════════════════════╝

■ サマリー
  実行: {n} テスト
  成功: {n} ✓
  失敗: {n} ✗
  スキップ: {n} —

═══ 失敗テスト詳細 ═══

[FAIL] boundary_api::test_get_routes_response_shape
  期待: { routes: Route[] }（frontend/src/api/routes.ts:15）
  実際: Vec<Route>（直接配列、ラップなし）
  境界: [A-2] GET /api/routes
  修正案: APIレスポンスを { routes: [...] } でラップ、またはFE側の型を配列に変更

[FAIL] boundary_convert::test_point_roundtrip_nan
  入力: Point { lat: NaN, lon: 0.0 }
  期待: ラウンドトリップ一致 or エラー
  実際: パニック at convert.rs:15
  境界: [D-1] Point座標系変換
```

---

## パイプライン統合

### impl-orchestrator Stage 3 との統合

impl-orchestrator の Stage 3（検証ゲート）Step 3-4:

```
境界テストファイルが存在する場合:
  → 通常のテストスイート（Step 3-3）に含まれるため自動実行される

存在しない場合:
  → /boundary-test detect を実行して境界一覧を記録
  → テスト生成は Stage 5 の一部として実行（Finding扱い）
```

### エスカレーション連携

境界テストの失敗は以下のように分類:
- **型不一致の検出** → Tier 2（自律修正 + 事後報告）: 型定義の修正
- **設計上の不整合**（API契約の根本的な違い）→ Tier 1（エスカレーション）: どちらを正とするか判断が必要
- **変換エラー** → Tier 2: 変換関数のバグ修正

---

## プロジェクト固有の境界定義

CLAUDE.md に `## Boundary Definitions` セクションを追加して、プロジェクト固有の境界を定義できる:

```markdown
## Boundary Definitions
| 境界名 | ソース | 消費側 | 変換ルール |
|--------|--------|--------|-----------|
| 座標系 | geo_core [lat,lon] | SurrealDB [lon,lat] | swap(0,1) |
| 座標系 | geo_core [lat,lon] | Leaflet [lat,lon] | identity |
| 時刻 | backend (UTC) | frontend (local) | timezone convert |
```

この定義がある場合、detect はこのテーブルを追加の検出ソースとして使用する。

---

## 注意事項

- `generate` は既存の境界テストファイルを上書きしない（新規ファイルのみ作成）
- 既存テストに追加する場合は、ファイル末尾にテストケースを追記
- DB テスト（Type C）はテスト用DBが必要 — 環境がない場合はスキップして報告
- WASM テスト（Type B）はビルド済み WASM が必要 — なければ先にビルドを試行
