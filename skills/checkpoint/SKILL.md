---
name: checkpoint
description: 長期タスクのセッション継続用チェックポイント（CHECKPOINT.md）を作成・復元する。USE WHEN /clear や /compact の直前、長時間セッションの区切り、明日続きをやる時。SKIP 数分で終わるタスク、構造化されたパイプライン状態は pipeline-state を使うこと。
argument-hint: "[save|restore|status]"
allowed-tools: Read, Write, Bash, Glob
---

# セッション継続管理

## /checkpoint save
1. プロジェクトルートに `CHECKPOINT.md` を作成/更新:

```markdown
# Checkpoint: [タスク名]
Updated: [ISO 8601 タイムスタンプ]
Session: ${CLAUDE_SESSION_ID}

## 目標
[タスクの最終ゴール]

## 完了済み
- [x] [完了タスク1]（コミット: abc1234）

## 進行中
- [ ] [現在のタスク]
  - 現状: [具体的な進捗]
  - ブロッカー: [あれば記載]

## 未着手
- [ ] [残タスク]

## 重要な決定事項
- [決定]: [理由]

## 環境状態
- ブランチ: [現在のブランチ名]
- 未コミット変更: [あり/なし]
- ビルド状態: [成功 / エラーあり — 内容を記載]

## 次のセッションへの申し送り
[次にやるべきことの具体的な指示]
```

2. 未コミット変更がある場合は WIP コミット作成を提案
3. `git log --oneline -5` の出力を含める

## /checkpoint restore
1. `CHECKPOINT.md` の存在確認（なければ「前回チェックポイントなし」と報告）
2. 内容を読み込みコンテキストに注入
3. git ログとの整合性確認
4. プロジェクトのビルドツールでコンパイル/型チェック状態を確認
5. 「次のセッションへの申し送り」に従って作業を再開

## /checkpoint status
1. `CHECKPOINT.md` の最終更新日時を表示
2. 現在の git 状態との差分を報告
3. 「完了済み」「進行中」「未着手」の件数をサマリー表示
