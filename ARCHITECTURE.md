# Architecture

このリポジトリの設計原則と、各スキル間の関係を定義する。
「何ができるか」は各 `SKILL.md` の `description` を見れば分かる。本文書は **「なぜそう設計したか」** を扱う。

将来スキル群を見直す際、本文書の各原則が **依然として妥当か** を判断材料に使う。

---

## 1. 設計目標

| # | 目標 | 帰結 |
|---|------|------|
| G1 | バグの後追いループを構造的に排除 | 役割別エージェントによるクロスレビュー、機械的検証ゲートを判断より先に通す |
| G2 | ユーザー介入を「設計判断」と「エスカレーション応答」の2点に集約 | エスカレーションフレームワークの集中管理、Tier 1/2/3 分類 |
| G3 | プロジェクト固有情報のハードコード排除 | CLAUDE.md の構造化セクションから動的取得 |
| G4 | コンテキスト爆発の回避 | フェーズ境界の checkpoint、Agent 委譲によるサブセッション分離 |
| G5 | コスト効率と品質の両立 | モデル配分（実装=sonnet / レビュー=opus / オーケストレーター=opus） |

---

## 2. レイヤ構成

スキルは責務によって 4 層に分類される。

```
[Layer 1: メタオーケストレーター]
  dev-pipeline           ─── 全フェーズ統合、サブスキルへ Agent 委譲のみ

[Layer 2: フェーズオーケストレーター]
  design-phase           ─── 設計フェーズ専任
  impl-orchestrator      ─── 実装フェーズ専任（6 ステージループ）

[Layer 3: 専門領域スキル（検査・修正）]
  spec-check / spec-fix / spec-audit   ─── 仕様整合性
  robust-review / robust-fix           ─── 堅牢性・セキュリティ
  boundary-test                        ─── 境界契約
  code-review                          ─── 軽量PR向け統合レビュー
  fix-with-verify                      ─── 単発バグ修正の安全パイプライン
  quick-test                           ─── 差分ベース高速テスト

[Layer 4: 横断ユーティリティ]
  escalation             ─── Finding 分類フレームワーク（全層から参照）
  pipeline-state         ─── パイプライン状態管理
  checkpoint             ─── セッション継続管理
```

**原則**: 上位層は下位層を呼ぶ。逆方向の呼び出しは禁止（循環依存防止）。
Layer 4 はどこからでも参照可能。

---

## 3. スキル呼び出しモデル

### 3.1 直接呼び出し不可、Agent 委譲のみ

スキルは Markdown 指示書であり、別スキルを直接 `invoke` する仕組みは存在しない。
よって **オーケストレーター層は `Agent` ツール経由でサブエージェントを生成し、対象スキルの実行を委ねる**。

```
dev-pipeline
  └─ Agent(prompt: "/design-phase を実行...")
  └─ Agent(prompt: "/impl-orchestrator <component> を実行...")
  └─ Agent(prompt: "/spec-fix all --loop 3 を実行...")
```

### 3.2 委譲の利点

| 観点 | 効果 |
|------|------|
| コンテキスト分離 | 各サブセッションの作業詳細はメインに戻ってこない（サマリーのみ） |
| 並列実行 | 単一メッセージ内で複数 Agent を起動可能（impl-orchestrator Stage 4 で security/robustness/spec の並列レビュー） |
| 保守性 | dev-pipeline がフェーズロジックを内包せず、サブスキル更新が即反映される |

### 3.3 反パターン: ロジック内包

旧 `dev-pipeline` (削除前 360 行) は各フェーズのロジックを直接埋め込んでいた。
これは **サブスキル更新が dev-pipeline に反映されない / コンテキストが肥大化する** 二重の問題を生む。
現行（249 行）は委譲のみ。フェーズ追加・順序変更時のみ本ファイルを編集する。

---

## 4. モデル配分

| 役割 | モデル | 根拠 |
|------|--------|------|
| メタ・フェーズオーケストレーター | opus | 判断・分岐制御の精度が全体品質を左右 |
| 実装エージェント | sonnet | コード生成量が多く、コスト効率重視。品質は後段ゲート + opus レビューで担保 |
| レビューエージェント（security / robustness / spec） | opus | 見落としコストが大きく、判断力が品質に直結。入力中心・出力少量のためコスト許容範囲 |
| ユーティリティ系スキル（checkpoint, escalation, pipeline-state, quick-test, fix-with-verify） | 親モデル継承（明示なし） | 軽量タスク、呼び出し元のモデルで十分 |

**モデルバージョン**: 本リポジトリは Opus 4.7 (`claude-opus-4-7`) で統一。
モデル更新時は `grep -r "claude-opus-4-N"` で全 SKILL.md と PLAN.md を一括更新する。

---

## 5. エスカレーション集約

### 5.1 集中管理の理由

各スキル個別に「ユーザー確認が必要か」を判定すると、判断基準が分散して一貫性が失われる。
`escalation` スキルが **Tier 1（必ずユーザー確認）/ Tier 2（自律対応＋事後報告）/ Tier 3（自律対応・報告不要）** の3段階を定義し、全層から参照される。

### 5.2 自律判断に頼らない設計

エージェントが確信を持って間違える場合、エスカレーションが発火しない。
よって **機械的検証ゲート（build / type / test / 境界契約テスト）を判断より先に通す**。
レビューは「ゲートを通過した上での追加チェック」と位置付ける（impl-orchestrator Stage 3 が Stage 4 より先）。

### 5.3 プロジェクト固有オーバーライド

CLAUDE.md の `## Escalation Overrides` で promote/demote を上書き可能。
集中フレームワークの汎用性とプロジェクト固有要件の両立。

---

## 6. CLAUDE.md 駆動の動的設定

スキル本体には **プロジェクト固有のパス・チェック項目を一切ハードコードしない**。
代わりに対象プロジェクトの `CLAUDE.md` から構造化セクションを動的読み取りする。

| セクション | 用途 | 読み取り側スキル |
|-----------|------|-----------------|
| `## Component Mapping` | コンポーネント↔仕様書↔実装ディレクトリの対応 | impl-orchestrator, spec-check, robust-review, boundary-test |
| `## Critical Constraints` | 制約事項（データ形式順序、アーキテクチャ制約等） | impl-orchestrator, robust-review, boundary-test |
| `## Project-Specific Checks` | プロジェクト固有の追加チェック項目 | robust-review, spec-check |
| `## Commands` | build/test/lint コマンド | impl-orchestrator, boundary-test, robust-fix |
| `## Escalation Overrides` | エスカレーション基準のオーバーライド | escalation |
| `## Boundary Definitions` | プロジェクト固有の境界定義 | boundary-test |

**情報不在時の挙動**: graceful degradation。エラーにせず、汎用チェック・自動推定で続行する。

---

## 7. 状態管理レイヤ

セッションを跨いだ状態保持には 3 つのレイヤが存在し、明確に役割分担する。

| 仕組み | スコープ | 内容 | 担当スキル |
|--------|---------|------|-----------|
| `PIPELINE-STATE.md` | パイプライン全体（複数セッション） | フェーズ・成果物・エスカレーションキュー | pipeline-state |
| `CHECKPOINT.md` | 単一タスクのセッション継続 | タスク進捗・git 状態・申し送り | checkpoint |
| `memory/` | 会話横断の汎用記憶 | ユーザー preferences、フィードバック、project facts | (auto memory) |

### 役割分離の原則

- **PIPELINE-STATE.md**: 構造化（フェーズ、コンポーネント表）。dev-pipeline 管理下。手動編集も可だがフォーマット維持必須。
- **CHECKPOINT.md**: 自由記述。長期タスクの "今どこ？" の即答用。`/clear` `/compact` 前に必ず保存。
- **memory/**: スキル実行履歴ではなく **collaboration preferences**。個別タスクの状態は入れない。

---

## 8. 検証ゲート優先設計

### 8.1 ゲートの順序

```
[1] ビルド/コンパイル        ← 機械的・必須
[2] 型チェック / Lint        ← 機械的・必須
[3] テストスイート           ← 機械的・必須
[4] 境界契約テスト           ← 機械的・必須（境界がある場合）
─────────── ↑↑↑ 全パス必須 ↑↑↑ ───────────
[5] 並列レビュー（opus×3）   ← 判断あり、Finding 出力
[6] 指摘解決 + 検証ゲート再実行
```

### 8.2 設計意図

- 機械的ゲートは **判断ミスの余地がない**。先に通すことで "判断系で見つけられなかったバグ" を物理的に防ぐ
- レビューは **追加の安全網** であり、ゲートの代替ではない
- 自律修正後は必ずゲートを再通過させ、修正が新たな破壊を生まないことを保証

### 8.3 リトライ上限

| 対象 | 上限 | 超過時 |
|------|------|--------|
| 検証ゲート修正試行 | 3 回 | エスカレーション |
| Finding 修正→ゲート再通過の周回 | 3 回 | 残存 Finding を報告 |
| 設計変更（Stage 4 → Stage 2 への逆流） | 1 回 | エスカレーション |

無限ループ防止と、「アプローチ自体の見直しが必要」のシグナル化を兼ねる。

---

## 9. Hook の責務

`hooks/` は Claude Code Hook スクリプト。スキルではなく **実行環境の安全網** として動作する。

| Hook | イベント | 役割 | 設計原則 |
|------|---------|------|---------|
| `pre-bash-safety.sh` | PreToolUse(Bash) | 破壊的コマンドのブロック（`rm -rf /`, `git push --force main`, `DROP DATABASE` 等） | exit 2 で物理ブロック、白リスト方式ではなく黒リスト |
| `post-edit-lint.sh` | PostToolUse(Write/Edit) | 編集ファイルの言語別 lint/型チェック | silent on success / error-only output（context window 汚染防止） |
| `stop-verify.sh` | Stop | タスク完了時の言語別検証ゲート | 無限ループ防止フラグ、git diff から変更言語を自動検出 |
| `session-start.sh` | SessionStart | プロジェクト種別・ツールチェーンの自動検出表示 | 1 行サマリー、最小 PATH 環境への対応 |

**スキルとの役割分離**: Hook は **常時無条件発火**、スキルは **明示的呼び出し**。
両者は重複可能（impl-orchestrator Stage 3 と stop-verify.sh は同じことを別契機でやる）が、これは **多層防御** として意図的。

---

## 10. スキル責務マトリクス

似た名前のスキルが多いため、選択指針を一覧化する。

| やりたいこと | 使うスキル | 補足 |
|-------------|-----------|------|
| 新機能をゼロから自律開発 | `dev-pipeline` | 計画→設計→実装→テスト→報告の全自動化 |
| 仕様書から実装だけ自律化 | `impl-orchestrator` | 設計書がある前提 |
| 設計書をゼロから生成 | `design-phase` | 計画サマリーから |
| 単発のバグ修正 | `fix-with-verify` | revert 保証付き |
| PR 前の軽量レビュー | `code-review` | 3 段階（Critical/Warning/Info） |
| マージ前の深層レビュー | `robust-review` | 4 段階（S-Critical〜S-Low） |
| 仕様↔実装の差分検出 | `spec-check` | Missing/Diverged/Extra/Constraint |
| 仕様書同士の矛盾検出 | `spec-audit` | 型名揺れ、API 契約不一致等 |
| 仕様↔実装の自動修正 | `spec-fix` | `--loop` で旧 spec-cycle 相当 |
| 堅牢性 Finding の一括修正 | `robust-fix` | robust-review 直後に |
| 境界契約のテスト | `boundary-test` | API/WASM/DB/変換 |
| 修正後の素早い動作確認 | `quick-test` | 差分ベース |
| 長時間セッションの区切り | `checkpoint` | `/clear` 前 |
| パイプライン進捗の管理 | `pipeline-state` | dev-pipeline 内部用 |
| Finding の Tier 分類 | `escalation` | 各スキルから参照 |

---

## 11. 将来見直し時のチェックリスト

本ドキュメントの原則が依然として妥当かを判断するための問い:

- [ ] **G1〜G5 の設計目標** は今のプロジェクト要件と合致しているか
- [ ] **4 層構造**（Layer 1〜4）に新スキルが収まらないケースが出ていないか
- [ ] **Agent 委譲モデル** のオーバーヘッドが許容範囲か（Claude Code の進化で別の手段が出ていないか）
- [ ] **モデル配分** は最新モデルの性能・価格カーブで依然合理的か
- [ ] **CLAUDE.md 動的読み取り** は対象プロジェクトで実際に運用されているか（形骸化していないか）
- [ ] **PIPELINE-STATE.md / CHECKPOINT.md / memory** の役割分離が現場で守られているか
- [ ] **検証ゲート→レビュー** の順序が実際にバグの後追いループを防げているか（バグ件数の傾向で測定）
- [ ] **Hook 4 種** が依然として有効に機能しているか（誤検出で無効化されていないか）

これらの問いに「No」が増えてきたら、本リポジトリ全体の再設計を検討する時期。
