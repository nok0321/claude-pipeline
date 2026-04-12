---
name: pipeline-state
description: パイプラインのフェーズ間状態管理。PIPELINE-STATE.mdの作成・更新・読み取り・フェーズ遷移を行う。
argument-hint: "[init <task-name>|update <section> <content>|read|transition <next-phase>]"
allowed-tools: Read, Write, Bash, Glob
---

# パイプライン状態管理

`PIPELINE-STATE.md` を通じてパイプラインのフェーズ間引き継ぎを管理する。

---

## コマンド

### /pipeline-state init \<task-name\>

プロジェクトルートに `PIPELINE-STATE.md` を新規作成する。

```markdown
# Pipeline: {task-name}
Phase: planning
Updated: {ISO 8601}

## 計画サマリー
（未記入 — 計画フェーズで記入）

## 設計成果物
（未記入 — 設計フェーズで記入）

## 実装ステータス
| コンポーネント | 実装 | 検証ゲート | レビュー |
|---------------|------|-----------|---------|
（未記入 — 実装フェーズで記入）

## エスカレーションキュー
| # | フェーズ | 分類 | 内容 | 状態 |
|---|---------|------|------|------|
（なし）

## 次フェーズへの引き継ぎ
（未記入）
```

既に `PIPELINE-STATE.md` が存在する場合は上書きせず、ユーザーに確認する。

---

### /pipeline-state update \<section\> \<content\>

指定セクションの内容を更新する。`Updated:` タイムスタンプも自動更新。

更新可能セクション:
- `plan` — 計画サマリーを記入/更新
- `design` — 設計成果物リストを追加/チェック更新
- `impl` — 実装ステータステーブルの行を追加/更新
- `escalation` — エスカレーションキューに項目を追加/状態更新
- `handoff` — 次フェーズへの引き継ぎ内容を記入

#### 実装ステータスの更新例
```
/pipeline-state update impl "<component> | done | build:pass type:pass test:pass | security:clean robustness:clean spec:clean"
```

#### エスカレーション項目の追加例
```
/pipeline-state update escalation "add | design | must-escalate | <設計判断が必要な内容>"
```

#### エスカレーション項目の状態更新例
```
/pipeline-state update escalation "resolve #1 | ユーザー承認済み、<決定した方針>で進める"
```

---

### /pipeline-state read

現在の `PIPELINE-STATE.md` の内容を読み取り、以下のサマリーを出力する:

```
Pipeline: {task-name}
Phase: {current-phase}
Updated: {timestamp}

設計成果物: {完了数}/{総数}
実装状況: {完了コンポーネント数}/{総数}
エスカレーション: {pending数} pending, {resolved数} resolved, {dismissed数} dismissed

次フェーズ引き継ぎ:
{引き継ぎ内容の要約}
```

`PIPELINE-STATE.md` が存在しない場合は「パイプライン未初期化。`/pipeline-state init <task-name>` で開始してください」と報告。

---

### /pipeline-state transition \<next-phase\>

フェーズを遷移する。以下を順次実行:

1. **現フェーズの完了チェック**
   - pending のエスカレーション項目がある場合は警告（遷移は可能だが確認を促す）
   - 実装ステータスに未完了コンポーネントがある場合は警告

2. **Phase フィールドを更新**
   - 有効な遷移: `planning` → `design` → `implementation` → `testing` → `reporting`
   - 逆方向の遷移は禁止（警告を出して中止）

3. **引き継ぎ内容の自動生成**
   - 現フェーズの成果物・未解決項目・注意事項を「次フェーズへの引き継ぎ」に記入

4. **チェックポイント連携**
   - `/checkpoint save` と同等の CHECKPOINT.md 更新を実行
   - コンテキスト使用量が大きい場合は `/compact` または `/clear` を推奨

5. **Updated タイムスタンプを更新**

---

## checkpoint との関係

| | PIPELINE-STATE.md | CHECKPOINT.md |
|---|---|---|
| スコープ | パイプライン全体（複数セッション） | 単一セッション |
| 内容 | フェーズ・成果物・エスカレーション | タスク進捗・git状態・申し送り |
| 用途 | フェーズ間の構造化引き継ぎ | セッション間の汎用引き継ぎ |
| 作成者 | pipeline-state スキル | checkpoint スキル |

両方を併用する。`transition` コマンドは CHECKPOINT.md も自動更新する。

---

## 注意事項

- `PIPELINE-STATE.md` はプロジェクトルートに1つだけ存在する（複数パイプラインの同時実行は非対応）
- git でバージョン管理される（`.gitignore` に追加しない）
- 手動編集も可能だが、構造（セクション名・テーブル形式）は維持すること
