---
name: quick-test
description: git diffから変更ファイルを検出し、関連テストのみを高速実行する。全テスト実行より大幅に短時間で完了。
allowed-tools: Bash, Grep, Glob
---

# 変更関連テスト高速実行

## Step 1: 変更ファイルを検出
```bash
git diff --name-only HEAD
```

## Step 2: プロジェクト種別と対応テストを特定

### Rust (Cargo.toml)
変更ファイルのパスからクレート名を自動検出:
```bash
# crates/<name>/... → cargo test -p <name>
# src/... → cargo test (ルートクレート)
```

クレート依存も考慮: コアクレートの変更時は依存クレートのテストも実行。

### Node.js / TypeScript (package.json)
```bash
# テストランナーを自動検出
npm test              # package.json の test スクリプト
npx vitest run        # Vitest
npx jest              # Jest
npx svelte-check      # Svelte 型チェック
npx vue-tsc --noEmit  # Vue 型チェック
npx tsc --noEmit      # TypeScript 型チェック
```

### Python (pyproject.toml / setup.py)
```bash
pytest <変更ファイルに対応するテストファイル>
# tests/test_<module>.py or <module>/tests/test_*.py
```

### Go (go.mod)
```bash
go test ./<変更パッケージ>/...
```

## Step 3: 特定されたテストのみ実行

**最速オプション（特定テスト関数のみ）:**
- Rust: `cargo test -p <crate> <test_name>`
- Python: `pytest tests/test_module.py::test_function`
- Go: `go test -run TestName ./pkg/...`
- Node: `npx vitest run src/module.test.ts`

## Step 4: 結果サマリー表示
- 全テスト通過: 完了報告
- 失敗テストあり: テスト名・失敗理由・修正提案を表示
- コアモジュール修正時は依存モジュールのテストも確認を推奨
