# Architecture

このリポジトリの設計原則と、各スキル間の関係を定義する。
「何ができるか」は各 `SKILL.md` の `description` を見れば分かる。本文書は **「なぜそう設計したか」** を扱う。

将来スキル群を見直す際、本文書の各原則が **依然として妥当か** を判断材料に使う。

> **注 (Phase 2 / 2026-04-29)**: 旧 `escalation` skill と旧 `pipeline-state` skill は本ドキュメントの **§A 補章 (Escalation framework)** と **§B 補章 (Pipeline state file)** に吸収。各 skill は本ドキュメントを参照する形に変更された。
>
> **注 (Phase 5 完了 / 2026-04-29)**: 新 8 skill の trigger rate を再測定し 7/8 個別 M1 PASS、7-skill 平均 +36.3% (詳細: [evals/POST-DIFF.md](evals/POST-DIFF.md))。`safe-fix` のみ 0.000 で routing 構造由来 (Opus 4.7 が "fix" 動詞 query を Bash/Edit 直接呼びへ流す)。
>
> **注 (Phase 6 Sub-V 確定 / 2026-05-23)**: `safe-fix` skill を Option A で廃止し、conformance/robust 修正ロジックを `impl-orchestrator` Stage 3 へ inline 化。**現在 7 skill 構造**。`finding.schema.json` は `skills/impl-orchestrator/references/` に移動。Escalation 削減のため `technical-arbiter` / `regression-judge` subagent と Stop hook drift gate を追加 ([plans/ESCALATION-REDESIGN.md](plans/ESCALATION-REDESIGN.md) 参照)。

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

スキルは責務によって 3 層に分類される (Phase 2 再編で旧 Layer 1 メタオーケストレーターを廃止し、旧 Layer 4 の escalation/pipeline-state を補章へ吸収)。

```
[Layer 1: フェーズオーケストレーター]
  design-phase           ─── 設計フェーズ専任
  impl-orchestrator      ─── 実装フェーズ専任 (4 ステージループ + inline 修正)、エントリーポイント兼任

[Layer 2: 専門領域スキル (検査)]
  spec-audit             ─── 仕様↔仕様 / 仕様↔実装 の二モード監査
  robust-review          ─── 堅牢性・セキュリティの深層レビュー
  code-review            ─── 軽量 PR 向け統合レビュー
  boundary-test          ─── 境界契約テスト

[Layer 3: ユーティリティ]
  checkpoint             ─── セッション継続管理

[Layer 4: Technical-judgment subagents (agents/)]
  technical-arbiter      ─── 命名/型/定数 drift の canonical 判定 (read-only)
  regression-judge       ─── test failure の fix-related / pre-existing 判定
```

修正フローは Phase 6 Sub-V Option A で `safe-fix` skill を廃止し、`impl-orchestrator` Stage 3 へ inline 化 ([skills/impl-orchestrator/references/conformance-fix.md](skills/impl-orchestrator/references/conformance-fix.md), [robust-fix.md](skills/impl-orchestrator/references/robust-fix.md))。

**原則**: 上位層は下位層を呼ぶ。逆方向の呼び出しは禁止 (循環依存防止)。

**フレームワーク**: Tier 1/2/3 のエスカレーション基準は **§A 補章**、`PIPELINE-STATE.md` のフォーマットと運用は **§B 補章** で定義し、全 skill から本ドキュメントを参照する。

---

## 3. スキル呼び出しモデル

### 3.1 直接呼び出し不可、Agent 委譲のみ

スキルは Markdown 指示書であり、別スキルを直接 `invoke` する仕組みは存在しない。
よって **オーケストレーター層は `Agent` ツール経由でサブエージェントを生成し、対象スキルの実行を委ねる**。

```
impl-orchestrator
  └─ Agent(prompt: "/spec-audit <component> --mode=conformance を実行...")
  └─ Agent(prompt: "/robust-review <files> を実行...")
  └─ (Stage 3 で findings を inline 修正、conformance-fix.md / robust-fix.md に従う)
  └─ Agent(prompt: "<technical-arbiter prompt> ...")  // Diverged conformance findings 経由
  └─ Agent(prompt: "<regression-judge prompt> ...")   // 曖昧な test failure attribution 経由
```

### 3.2 委譲の利点

| 観点 | 効果 |
|------|------|
| コンテキスト分離 | 各サブセッションの作業詳細はメインに戻ってこない (サマリーのみ) |
| 並列実行 | 単一メッセージ内で複数 Agent を起動可能 (impl-orchestrator Stage 4 で security/robustness/spec の並列レビュー) |
| 保守性 | impl-orchestrator がフェーズロジックを内包せず、サブスキル更新が即反映される |

### 3.3 反パターン: ロジック内包

旧 `dev-pipeline` (Phase 2 で削除) は各フェーズのロジックを直接埋め込んでいた。
これは **サブスキル更新が dev-pipeline に反映されない / コンテキストが肥大化する** 二重の問題を生んだ。
現在 `impl-orchestrator` がエントリーポイント兼任となり、design-phase の事前条件 (DESIGN/*.md 存在) をチェックして、不在なら `design-phase` を Agent 委譲する形でフォールバックする (R4 緩和策)。

---

## 4. モデル配分

| 役割 | モデル | 根拠 |
|------|--------|------|
| フェーズオーケストレーター | opus | 判断・分岐制御の精度が全体品質を左右 |
| 実装エージェント | sonnet | コード生成量が多く、コスト効率重視。品質は後段ゲート + opus レビューで担保 |
| レビューエージェント (security / robustness / spec) | opus | 見落としコストが大きく、判断力が品質に直結。入力中心・出力少量のためコスト許容範囲 |
| ユーティリティ系スキル (checkpoint) | 親モデル継承 (明示なし) | 軽量タスク、呼び出し元のモデルで十分 |
| Technical-judgment subagent (technical-arbiter, regression-judge) | sonnet 4.6 | 判定品質が下流に影響、呼び出し頻度は低 (drift / ambiguous failure 検出時のみ)。Phase 6 ESCALATION-REDESIGN §4.1 |

**モデルバージョン**: 本リポジトリは Opus 4.8 (`claude-opus-4-8`) で統一。
モデル更新時は `grep -r "claude-opus-4-N"` で全 SKILL.md と PLAN.md を一括更新する。

---

## 5. エスカレーション集約

### 5.1 集中管理の理由

各スキル個別に「ユーザー確認が必要か」を判定すると、判断基準が分散して一貫性が失われる。
**§A 補章 (Escalation framework)** が **Tier 1 (必ずユーザー確認) / Tier 2 (自律対応＋事後報告) / Tier 3 (自律対応・報告不要)** の3段階を定義し、全層から参照される。

### 5.2 自律判断に頼らない設計

エージェントが確信を持って間違える場合、エスカレーションが発火しない。
よって **機械的検証ゲート (build / type / test / 境界契約テスト) を判断より先に通す**。
レビューは「ゲートを通過した上での追加チェック」と位置付ける (impl-orchestrator Stage 3 が Stage 4 より先)。

### 5.3 プロジェクト固有オーバーライド

CLAUDE.md の `## Escalation Overrides` で promote/demote を上書き可能。
集中フレームワークの汎用性とプロジェクト固有要件の両立。詳細は §A 補章。

---

## 6. CLAUDE.md 駆動の動的設定

スキル本体には **プロジェクト固有のパス・チェック項目を一切ハードコードしない**。
代わりに対象プロジェクトの `CLAUDE.md` から構造化セクションを動的読み取りする。

| セクション | 用途 | 読み取り側スキル |
|-----------|------|-----------------|
| `## Component Mapping` | コンポーネント↔仕様書↔実装ディレクトリの対応 | impl-orchestrator, spec-audit, robust-review, boundary-test |
| `## Critical Constraints` | 制約事項 (データ形式順序、アーキテクチャ制約等) | impl-orchestrator, robust-review, boundary-test, spec-audit |
| `## Project-Specific Checks` | プロジェクト固有の追加チェック項目 | robust-review, spec-audit |
| `## Commands` | build/test/lint コマンド | impl-orchestrator (Stage 2 ゲート + Stage 3 inline 修正の per-edit gate), boundary-test |
| `## Escalation Overrides` | エスカレーション基準のオーバーライド | §A 補章で定義、impl-orchestrator が参照 |
| `## Boundary Definitions` | プロジェクト固有の境界定義 | boundary-test |

**情報不在時の挙動**: graceful degradation。エラーにせず、汎用チェック・自動推定で続行する。

---

## 7. 状態管理レイヤ

セッションを跨いだ状態保持には 3 つのレイヤが存在し、明確に役割分担する。

| 仕組み | スコープ | 内容 | 担当 |
|--------|---------|------|-----------|
| `PIPELINE-STATE.md` | パイプライン全体 (複数セッション) | フェーズ・成果物・エスカレーションキュー | §B 補章で定義、impl-orchestrator が更新 |
| `CHECKPOINT.md` | 単一タスクのセッション継続 | タスク進捗・git 状態・申し送り | checkpoint skill |
| `memory/` | 会話横断の汎用記憶 | ユーザー preferences、フィードバック、project facts | (auto memory) |

### 役割分離の原則

- **PIPELINE-STATE.md**: 構造化 (フェーズ、コンポーネント表)。impl-orchestrator が管理。手動編集も可だがフォーマット維持必須。詳細は §B 補章。
- **CHECKPOINT.md**: 自由記述。長期タスクの "今どこ？" の即答用。`/clear` `/compact` 前に必ず保存。
- **memory/**: スキル実行履歴ではなく **collaboration preferences**。個別タスクの状態は入れない。

---

## 8. 検証ゲート優先設計

### 8.1 ゲートの順序

```
[1] ビルド/コンパイル        ← 機械的・必須
[2] 型チェック / Lint        ← 機械的・必須
[3] テストスイート           ← 機械的・必須
[4] 境界契約テスト           ← 機械的・必須 (境界がある場合)
─────────── ↑↑↑ 全パス必須 ↑↑↑ ───────────
[5] 並列レビュー (opus×3)   ← 判断あり、Finding 出力
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
| 設計変更 (Stage 4 → Stage 2 への逆流) | 1 回 | エスカレーション |

無限ループ防止と、「アプローチ自体の見直しが必要」のシグナル化を兼ねる。

---

## 9. Hook の責務

`hooks/` は Claude Code Hook スクリプト。スキルではなく **実行環境の安全網** として動作する。

| Hook | イベント | 役割 | 設計原則 |
|------|---------|------|---------|
| `pre-bash-safety.sh` | PreToolUse(Bash) | 破壊的コマンドのブロック (`rm -rf /`, `git push --force main`, `DROP DATABASE` 等) | exit 2 で物理ブロック、白リスト方式ではなく黒リスト |
| `post-edit-lint.sh` | PostToolUse(Write/Edit) | 編集ファイルの言語別 lint/型チェック | silent on success / error-only output (context window 汚染防止)。旧 `quick-test` skill の差分ベース確認はこちらに吸収 |
| `stop-verify.sh` | Stop | タスク完了時の言語別検証ゲート | 無限ループ防止フラグ、git diff から変更言語を自動検出 |
| `session-start.sh` | SessionStart | プロジェクト種別・ツールチェーンの自動検出表示 | 1 行サマリー、最小 PATH 環境への対応 |

**スキルとの役割分離**: Hook は **常時無条件発火**、スキルは **明示的呼び出し**。
両者は重複可能 (impl-orchestrator Stage 3 と stop-verify.sh は同じことを別契機でやる) が、これは **多層防御** として意図的。

---

## 10. スキル責務マトリクス

似た名前のスキルが多いため、選択指針を一覧化する (Phase 6 Sub-V 以降の現行構成、計 7 skill + technical-judgment subagents)。

| やりたいこと | 使うスキル | 補足 |
|-------------|-----------|------|
| 設計書から実装まで自律化 | `impl-orchestrator` | エントリーポイント兼任。DESIGN/*.md 不在時は design-phase へフォールバック |
| 設計書をゼロから生成 | `design-phase` | 計画サマリーから |
| 仕様書同士の矛盾検出 | `spec-audit` | Mode A (`--mode=cross`) — 型名揺れ、API 契約不一致等 |
| 仕様↔実装の差分検出 | `spec-audit` | Mode B (`--mode=conformance`) — Missing/Diverged/Extra/Constraint |
| マージ前の深層レビュー | `robust-review` | severity Critical/High/Medium/Low |
| PR 前の軽量レビュー | `code-review` | severity Critical/High/Medium/Low |
| 境界契約のテスト | `boundary-test` | API/WASM/DB/変換 |
| spec-audit 結果の自動修正 | `impl-orchestrator` Stage 3 inline | `skills/impl-orchestrator/references/conformance-fix.md` (Phase 6 Sub-V Option A) |
| robust-review 結果の自動修正 | `impl-orchestrator` Stage 3 inline | `skills/impl-orchestrator/references/robust-fix.md` (Phase 6 Sub-V Option A) |
| 単発のバグ修正 | Claude 直接 (Edit + Bash gate) | skill 経由なし。impl-orchestrator は DESIGN/*.md 駆動のため adhoc は対象外 |
| 命名/型 drift の canonical 判定 | `technical-arbiter` subagent | `agents/technical-arbiter.md` (Phase 6 P1) |
| Test failure の fix-related / pre-existing 判定 | `regression-judge` subagent | `agents/regression-judge.md` (Phase 6 P2) |
| 長時間セッションの区切り | `checkpoint` | `/clear` 前 |
| Finding の Tier 分類 | (本ドキュメント §A 補章) | 各 skill が参照 |
| パイプライン進捗の管理 | (本ドキュメント §B 補章) | impl-orchestrator が更新 |

旧 skill との対応表は `docs/MIGRATION.md` を参照。

---

## 11. 将来見直し時のチェックリスト

本ドキュメントの原則が依然として妥当かを判断するための問い:

- [ ] **G1〜G5 の設計目標** は今のプロジェクト要件と合致しているか
- [ ] **3 層構造** に新スキルが収まらないケースが出ていないか
- [ ] **Agent 委譲モデル** のオーバーヘッドが許容範囲か (Claude Code の進化で別の手段が出ていないか)
- [ ] **モデル配分** は最新モデルの性能・価格カーブで依然合理的か
- [ ] **CLAUDE.md 動的読み取り** は対象プロジェクトで実際に運用されているか (形骸化していないか)
- [ ] **PIPELINE-STATE.md / CHECKPOINT.md / memory** の役割分離が現場で守られているか
- [ ] **検証ゲート→レビュー** の順序が実際にバグの後追いループを防げているか (バグ件数の傾向で測定)
- [ ] **Hook 4 種** が依然として有効に機能しているか (誤検出で無効化されていないか)
- [ ] **§A / §B 補章** が SKILL に戻すべき粒度に成長していないか (補章が長くなりすぎたら skill 復活を検討)

これらの問いに「No」が増えてきたら、本リポジトリ全体の再設計を検討する時期。

### 11.1 Phase 5 完了時 (2026-04-29) 暫定評価

Phase 5 POST eval 結果と Phase 1〜4 の構造変更を踏まえた、各チェック項目の暫定状況。
Phase 6 dogfooding (1 週間) で実運用観察を加え、最終評価は dogfooding 終了時に実施。

| チェック項目 | 暫定状況 | 根拠 / 補足 |
|------------|---------|----|
| G1〜G5 の設計目標 | ✅ 合致 | 7/8 個別 M1 PASS、7-skill 平均 +36.3% trigger rate 改善が G1 (後追いループ排除) と G4 (コンテキスト爆発回避) を間接支持 |
| 3 層構造 | ✅ 維持 | 新 8 skill 全てが Layer 1/2/3 に収まる。dev-pipeline drop による旧 Layer 0 廃止以外、新規逸脱なし |
| Agent 委譲モデル | ✅ 許容範囲 | Phase 4 で `context: fork` を 5 skill に適用後もオーバーヘッド許容。Phase 5 eval (76min, 8 skill × 20 query × 3 run) は rate-limit 0 件 |
| モデル配分 | ✅ Opus 4.8 統一 | 全 skill が `claude-opus-4-8`（Phase 5 measure 時点では `claude-opus-4-7`、Opus 4.8 リリースで更新）。コスト/性能再評価は dogfooding で観察予定 |
| CLAUDE.md 動的読み取り | ⏳ dogfooding で確認 | claude-pipeline 自体は skill リポジトリのため CLAUDE.md なし。対象プロジェクト側の運用度は Phase 6 dogfooding で実例観察 |
| PIPELINE-STATE / CHECKPOINT / memory 役割分離 | ⏳ dogfooding で確認 | CHECKPOINT.md は Phase 0〜5 で機能。memory も active 利用中。PIPELINE-STATE.md は実プロジェクト稼働時に分離維持を観察 |
| 検証ゲート→レビュー の順序 | ⏳ dogfooding で確認 | impl-orchestrator Stage 2 → Stage 3 順序を Phase 4 で formalize。実バグ追いループ防止効果は dogfooding 期間中の実装で測定 |
| Hook 4 種 | ✅ 全 4 種維持 | `hooks/{pre-bash-safety,post-edit-lint,stop-verify,session-start}.sh` 全稼働中。誤検出/無効化は Phase 6 dogfooding で観察 |
| §A / §B 補章の粒度 | ✅ 維持 | §A ≈ 70 行 / §B ≈ 80 行。SKILL 復活粒度 (200 行) には至らず、補章として適切 |

**Phase 6 Sub-V 確定 (2026-05-23)**:

- **safe-fix の構造**: Phase 5 で trigger 0.000 を観測。Opus 4.7 が "fix" 動詞 query を Skill 経由ではなく Bash/Edit/Glob 直接呼びでルーティングする structural pattern が確定。description 最適化 (Sub-S 2 iter) では覆せず。Phase 6 Sub-V dogfooding (5 retroactive セッション) でも impl-orchestrator → safe-fix Skill 委譲 0 件、systemic な現象を確認。**Option A 採用**: `safe-fix` skill を廃止し、conformance/robust 修正ロジックを `impl-orchestrator` Stage 3 へ inline 化。`finding.schema.json` は `skills/impl-orchestrator/references/` に移動。Mode C (adhoc) は廃止 (Claude 直接ハンドリングへ)。詳細は [docs/MIGRATION.md](docs/MIGRATION.md) §Phase 6 Sub-V。
- **Escalation 削減**: Phase 6 観察で spec-audit / impl-orchestrator の Tier 1 率が 10〜20% と高く、technical-judgment 系は user 中断より subagent 委譲が品質も低下しないと判定。[plans/ESCALATION-REDESIGN.md](plans/ESCALATION-REDESIGN.md) P1/P2/P3 を採用 (technical-arbiter / regression-judge / Stop hook drift gate)。

---

## §A 補章: Escalation framework

Phase 2 で `escalation` skill を本ドキュメントに吸収。Finding を Tier 1/2/3 に分類する基準を全 skill から参照する。各 skill は判定結果を `PIPELINE-STATE.md` のエスカレーションキュー (§B 補章参照) に push する。

### Tier 1: must escalate (no autonomous action)

以下のいずれかに該当する場合、**ユーザー確認まで停止**。自動修正しない。

| 基準 | 理由 |
|-----------|-----|
| 外部 API / DB schema の選定・変更 | ドメイン知識・業務要件が選定を左右 |
| Auth / authz フローの設計判断 | セキュリティポリシー直結 |
| 公開インターフェースの破壊的変更 | 下流コンシューマに波及 |
| 設計ドキュメントに無い新規要件 | スコープ外判断はユーザーの領分 |
| 同一修正で 3 回連続失敗 | アプローチ自体を見直すべき |
| 検証ゲートが最大リトライ後も失敗 | 根因が skill のスコープ外の可能性 |
| ライセンス / 法的制約の変更 | 法務レビューが必要 |
| パフォーマンス特性が大きく変わる設計変更 | トレードオフはユーザーの領分 |

### Tier 2: auto-fix + post-report

以下のいずれかに該当する場合、**自律修正して事後報告**。

| 基準 | 例 |
|-----------|---------|
| 既知パターンを持つ Critical / High Finding | `unwrap()` → `?`、SQL 文字列補間 → `.bind()` |
| 軽微な仕様書間の不整合 | 型名揺れ、引数順違い、フィールド名統一 |
| テストで判明したロジックバグ | 失敗テストは実バグの兆候 |
| エッジケーステストの追加 | 境界値・空入力・NaN カバー |
| spec-audit Mode B で Missing と判定された項目 | 仕様にあって実装にない |
| Constraint 違反 | アーキテクチャルール違反、データ形式順序等 |

報告フォーマット:

```
[auto-fix] <classification> | <file:line>
  Change: <what was modified>
  Reason: <why autonomous action is appropriate>
  Verification: <gate result, e.g. tests pass>
```

### Tier 3: auto-fix (no report needed)

以下に該当する場合、**サイレント修正**。

| 基準 |
|-----------|
| Medium / Low / Info 相当の Finding |
| フォーマット修正、import 整理 |
| Doc コメントの追加・編集 |
| 既存テストの軽微な refactor (挙動変更なし) |
| Lint / clippy 警告の解消 |

### 分類手順

1. Finding を読む。
2. Tier 1 基準にマッチするか確認。マッチ → **Tier 1**。
3. Tier 3 基準にマッチするか確認。マッチ → **Tier 3**。
4. それ以外 → **Tier 2**。
5. 判断に迷う → **Tier 1** にデフォルト (fail safe)。

### Project-specific overrides (CLAUDE.md `## Escalation Overrides`)

```markdown
## Escalation Overrides
- promote: any DB-related change must escalate, even at High
- demote: documentation-only changes are always Tier 3
```

順序: overrides 読み取り → マッチするものを適用 → 残りはデフォルト基準にフォールバック。

### Escalation queue

パイプライン実行中、Tier 1 Finding は `PIPELINE-STATE.md` のエスカレーションキューに蓄積。

- 各ステージ完了時に新規アイテムを push。
- フェーズ境界でユーザーへ一括提示 (細切れにしない)。

ユーザー応答後:

- 修正を適用してキューアイテムを `resolved` にマーク。
- ユーザーが「対応不要」と言った場合は `dismissed`。

---

## §B 補章: Pipeline state file

Phase 2 で `pipeline-state` skill を本ドキュメントに吸収。`PIPELINE-STATE.md` のフォーマットと管理ルールを定義し、`impl-orchestrator` が phase 遷移時に更新する。

### File template

```markdown
# Pipeline: <task-name>
Phase: planning
Updated: <ISO 8601>

## Plan summary
(empty — fill in during planning)

## Design artifacts
(empty — fill in during design)

## Implementation status
| Component | Impl | Verification gate | Review |
|-----------|------|-------------------|--------|
(empty — fill in during implementation)

## Escalation queue
| # | Phase | Class | Content | Status |
|---|-------|-------|---------|--------|
(none)

## Hand-off to next phase
(empty)
```

### Updatable sections

| Section | Content |
|---------|---------|
| `plan` | 計画サマリーの記入・改訂 |
| `design` | 設計成果物の追加・チェックオフ |
| `impl` | 実装状況テーブルの行追加・更新 |
| `escalation` | キューへの push、または既存アイテムのステータス更新 |
| `handoff` | 次フェーズへの申し送り |

実装行の例:

```
update impl "<component> | done | build:pass type:pass test:pass | security:clean robustness:clean spec:clean"
```

エスカレーション push の例:

```
update escalation "add | design | must-escalate | <design judgement needed>"
```

エスカレーション resolve の例:

```
update escalation "resolve #1 | user approved, proceed with <decision>"
```

### Phase transitions

許可される前進: `planning → design → implementation → testing → reporting`。逆遷移は silent regression を生むため拒否する。

遷移時の処理:

1. **完了確認**: 未解決のエスカレーション項目や未完了コンポーネントを **警告** (ブロックしない)。
2. **Phase フィールド更新**。
3. **Hand-off note 自動生成**: 当フェーズの成果物・未解決項目・警告を含める。
4. **checkpoint 同期**: `CHECKPOINT.md` も新フェーズを反映するよう更新。
5. **Updated タイムスタンプ更新**。

遷移後にコンテキスト使用率が高ければ `/compact` または `/clear` を推奨。

### Constraints

- `PIPELINE-STATE.md` はプロジェクトルートに **唯一**。並走パイプラインは非サポート。
- 本ファイルは git にコミット (`.gitignore` に入れない)。
- 手動編集も可だが、セクション見出しとテーブルフォーマットは保持必須。

### Read 出力フォーマット

```
Pipeline: <task-name>
Phase: <current-phase>
Updated: <timestamp>

Design artifacts: <done>/<total>
Implementation: <done components>/<total>
Escalation: <pending> pending, <resolved> resolved, <dismissed> dismissed

Next-phase hand-off:
<short summary of the hand-off note>
```

ファイル不在時: "pipeline not initialized — run `impl-orchestrator init <task-name>`" を報告。
