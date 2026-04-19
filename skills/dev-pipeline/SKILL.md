---
name: dev-pipeline
description: 計画→設計→実装→テスト→報告の全フェーズを統合実行するメタオーケストレーター。各フェーズはサブスキルに Agent ツール経由で委譲する。エスカレーション駆動でユーザー介入を最小化。
argument-hint: "<task-description> | resume | abort"
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, Agent
model: claude-opus-4-7
---

# 自律開発パイプライン

要件記述から、設計→実装→テスト→報告までを自律的に実行する純粋なオーケストレーター。
各フェーズの実装ロジックは保持しない — `Agent` ツールでサブスキルに委譲する。

ユーザー介入は **計画承認** と **エスカレーション応答** の2箇所のみ。

---

## フェーズ構成と委譲先

| Phase | 名称 | 委譲先 | モデル |
|-------|------|--------|--------|
| 0 | 計画（対話） | dev-pipeline 本体 | opus |
| 1 | 設計（自律） | `design-phase` スキル | opus |
| 2 | 実装（自律） | コンポーネントごとに `impl-orchestrator` | opus |
| 2.5 | 境界検証 | `boundary-test all` | opus |
| 3 | テスト（自律） | `spec-fix --loop all` + `robust-review all` | opus |
| 4 | 報告 | dev-pipeline 本体 | opus |

各フェーズ間で `pipeline-state` スキルにより `PIPELINE-STATE.md` を更新し、フェーズ境界で `checkpoint save` を実行する。

---

## エントリポイント

```
/dev-pipeline <task-description>   # 新規パイプライン開始
/dev-pipeline resume               # PIPELINE-STATE.md から再開
/dev-pipeline abort                # 進行中パイプラインを中止
```

引数なしで `PIPELINE-STATE.md` が存在する場合は `resume` 扱い。

---

## Phase 0: 計画（対話）

`<task-description>` から計画を構造化してユーザーに提示し、承認を得る。

### 0-1: 計画提示

```
╔══════════════════════════════════════╗
║  パイプライン計画                     ║
╚══════════════════════════════════════╝

■ タスク概要 / スコープ / コンポーネント分割案 / 技術アプローチ / リスク / 推定規模

→ この計画で進めてよいですか？ [y / 修正指示 / 中止]
```

### 0-2: ユーザー承認（唯一の必須ゲート）

承認 → Phase 1 へ。修正指示 → 計画を再提示。中止 → 終了。

### 0-3: 状態初期化

`pipeline-state init <task-name>` 相当を実行し計画サマリーを記録。

---

## Phase 1: 設計

`design-phase` スキルに委譲。

```
Agent(
  description: "Phase 1: Design generation",
  subagent_type: "general-purpose",
  prompt: "
    /design-phase スキルを実行してください。
    PIPELINE-STATE.md の計画サマリーから DESIGN/*.md を生成し、spec-audit による自己検証まで完了させること。

    完了後、以下を返してください:
    - 生成した DESIGN/*.md のパス一覧
    - 矛盾チェック結果（自律修正済み / Tier 1 エスカレーション項目）
    - Component Mapping の提案（CLAUDE.md 未定義の場合）
  "
)
```

エージェント完了後:
1. Tier 1 エスカレーション項目があればユーザーに提示し回答を待つ
2. 回答を反映して必要なら設計書を修正
3. `pipeline-state update design ...` で成果物リストを記録
4. `pipeline-state transition implementation`
5. `checkpoint save`

---

## Phase 2: 実装

依存順にコンポーネントを処理。各コンポーネントで `impl-orchestrator` を独立した Agent で起動する。

### 2-1: コンポーネントループ

```
for component in dependency_order:
    Agent(
      description: "Phase 2: Implement {component}",
      subagent_type: "general-purpose",
      prompt: "
        /impl-orchestrator {component} を実行してください。
        Stage 1〜6 をすべて完了させ、検証ゲート全パス + 並列レビュー（security/robustness/spec）+ 指摘解決まで自律実行すること。

        完了後、以下を返してください:
        - 検証ゲート結果 (build/type/test/boundary)
        - レビュー Finding サマリー (深刻度別カウント)
        - 自律修正済み一覧 (Tier 2)
        - Tier 1 エスカレーション項目
      "
    )
    pipeline-state update impl で結果を反映
    Tier 1 があればユーザーに提示し回答を待つ
```

### 2-2: 境界検証

全コンポーネント完了後:

```
Agent(
  description: "Phase 2.5: Boundary test",
  subagent_type: "general-purpose",
  prompt: "/boundary-test all を実行し、検出 → 生成 → 実行まで完了させてください。失敗があれば最大3回まで自律修正を試行してください。"
)
```

### 2-3: フェーズ境界

`pipeline-state transition testing` + `checkpoint save`。
コンテキストが肥大化していれば `/compact` を推奨。

---

## Phase 3: テスト

最終整合性チェックと最終堅牢性チェックを並列で実行。

```
# 並列実行（単一メッセージ内で2つの Agent 呼び出し）

Agent(
  description: "Phase 3: Spec convergence",
  subagent_type: "general-purpose",
  prompt: "/spec-fix all --loop 3 を実行してください。仕様↔実装の差分が0になるか上限到達まで反復し、残存差分があればエスカレーション候補として報告してください。"
)

Agent(
  description: "Phase 3: Robustness final review",
  subagent_type: "general-purpose",
  prompt: "/robust-review all を実行してください。Phase 2 で見落とされた S-Critical / S-High があれば /robust-fix で修正してください。修正後の検証ゲート結果も報告すること。"
)
```

両エージェント完了後、Tier 1 があればユーザーに提示。

`pipeline-state transition reporting`。

---

## Phase 4: 報告

```bash
git diff --stat
```

```
╔══════════════════════════════════════════════════╗
║  自律開発パイプライン 完了レポート                  ║
╚══════════════════════════════════════════════════╝

■ 変更概要         (ファイル数、追加/削除行数)
■ 検証ゲート結果   (全フェーズ集約)
■ レビュー Finding (Phase 2 + Phase 3 集約)
■ 対応結果         (自律修正 / エスカレーション)
■ 自律修正ログ     (Tier 2)
■ エスカレーション履歴
■ 残存リスク       (S-Medium 以下)
■ 推奨アクション   (手動確認項目)
```

集約データソース: `PIPELINE-STATE.md`、各 Phase の Agent 戻り値。

`pipeline-state` の Phase を `reporting` で確定。

---

## エスカレーションポリシー

| タイミング | 動作 |
|-----------|------|
| Phase 0 | 即時対話 |
| Phase 1〜3 | フェーズ末（または Phase 2 のコンポーネント末）に蓄積分を一括提示 → 回答待ち |

**重要**: pending エスカレーションがあっても影響を受けないコンポーネントの作業は続行する。

---

## コンテキスト管理

| フェーズ境界 | アクション |
|-------------|-----------|
| Phase 0 → 1 | — |
| Phase 1 → 2 | checkpoint save |
| Phase 2 内（コンポーネント間） | checkpoint save、必要なら `/compact` |
| Phase 2 → 3 | checkpoint save、`/compact` 推奨 |
| Phase 3 → 4 | — |

各フェーズを Agent サブセッションに委譲することで、メインオーケストレーターのコンテキストはサマリーのみ蓄積され肥大化を抑制できる。

---

## 中断と再開

### 中断
Ctrl+C やセッション終了時:
1. 直近の Agent 戻り値を `pipeline-state update` で記録
2. `checkpoint save` 実行

### 再開
`/dev-pipeline resume` または `/dev-pipeline`（引数なしで PIPELINE-STATE.md 検出時）:

```
Pipeline "<task-name>" を検出しました。
現在: Phase 2 (implementation) — backend 完了、frontend 未着手
→ 続行しますか？ [y / 最初からやり直し / 中止]
```

`y` の場合は対応する Phase ロジックから再開。

---

## 注意事項

- 本スキルは **オーケストレーション専任**。ロジックは持たない
- 各フェーズの実体は対応するサブスキル（design-phase, impl-orchestrator, boundary-test, spec-fix, robust-review）に委譲
- サブスキル直接修正で全体の挙動が変わる — 逆に dev-pipeline 側でフェーズ追加/順序変更する場合のみ本ファイルを編集
- モデル配分はサブスキルの frontmatter に従う（オーケストレーター本体は opus）
- Phase 0 のユーザー承認は省略不可（安全装置）
