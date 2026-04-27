# スキルリポジトリ重量整理計画 (Heavy Refactor)

## Context

Opus 4.7 で skill の自律発火が増えたタイミングで、既存16個の使用実績と Anthropic 公式ベストプラクティスとの差分を測定。実測値（2026-04-28 集計）では **16個中9個が直近30日0回呼び出し**、最頻出は spec-audit (26回) で全体の58%を占める一極集中。設計の頂点である `dev-pipeline` (メタオーケストレーター) は0回で、`impl-orchestrator` を直接呼ぶ運用が定着している。

本計画は、(a) Claude (実利用主体) のレビューに基づく設計原則の明文化、(b) 公式仕様への構造寄せ、(c) 評価フレームワーク導入による定量改善ループの確立、を目的とした全面再設計を行う。

---

## 1. 設計原則（実体験ベース）

過去の使用ログと Claude 自身のレビューから、効果のあった型と摩擦を生んだ型を抽出。新スキル群はこれらを満たす/避けることを必須とする。

### 1.1 採用する型（P）— やりやすかった点を制度化

| ID | 原則 | 根拠 |
|----|------|------|
| P1 | **単一ジョブ原則**: 1 skill = 1 明確なジョブ。他 skill との境界を SKIP 句に頼らずタイトルと description だけで識別できること | spec-audit が26回呼べた最大要因。「設計書間の矛盾検出」が他と被らない |
| P2 | **when_to_use は具体ドメイン語3〜5個**: "design docs", "PDF files", "session boundary" 等 | 公式 pdf skill 等の実例。short window で識別される |
| P3 | **本文中で `references/*.md` を明示**: "For X details, see references/x.md" | Progressive Disclosure を機能させる鍵。Claude の部分読み出しが可能になりトークン節約 |
| P4 | **オーケストレーターは2層で打ち止め**: メタ層を作らない | dev-pipeline → impl-orchestrator → 各skill の3層は実測で機能せず。impl-orchestrator → 各skill の2層で運用されている |
| P5 | **SKILL.md 200行以下**: 超える場合は references/ に分割 | 公式は500行/5k tokens を上限としているが、実用的には Read 1回で全把握できる範囲が望ましい |
| P6 | **frontmatter は最小限**: `name` + `description` + (任意で `when_to_use`/`license`) のみ | 公式 anthropics/skills の全実例で踏襲されている |

### 1.2 排除する型（A）— やりずらかった点を禁止

| ID | アンチパターン | 理由 |
|----|--------------|------|
| A1 | **SKIP 句の連鎖**: 1 skill に SKIP <他skill> が3個以上 | Claude のトリガー判断負荷を増やす。SKIP が多いほどトリガー精度が下がる。**新ルール: SKIP は最大1個、原則ゼロ** |
| A2 | **3層以上の間接委譲** | dev-pipeline 廃止の根拠。1段間接化のたびにコンテキストオーバーヘッドが発生 |
| A3 | **独自分類体系の乱立**: Critical/Warning/Info, S-Critical〜S-Low, Missing/Diverged/Extra/Constraint, Tier 1/2/3 が並走 | 横断統合時の認知負荷。**新ルール: severity 軸を Critical/High/Medium/Low の1本に統一**、escalation の Tier はメタ判定として残すが skill 内 finding 表記には用いない |
| A4 | **検査↔修正の暗黙契約**: 検査 skill の出力フォーマットを次の修正 skill が"察する" | 引き継ぎ精度が低下。**新ルール: 検査系 skill の Finding 出力を JSON Schema で契約化** |
| A5 | **日本語の SKILL.md 本文**: 「〜すべき」「〜推奨」の MUST/SHOULD 揺れ | 公式は二人称禁止+imperative。**新ルール: SKILL本体は英語、ARCHITECTURE/README/PLAN は日本語維持** |
| A6 | **MUST/NEVER の濫用**: 理由を書かずに rigid に縛る | 公式が明示的に黄信号としているパターン |

### 1.3 言語ポリシー

| 部位 | 言語 | 理由 |
|------|------|------|
| SKILL.md frontmatter (name/description/when_to_use) | **英語必須** | トリガー精度に直結。公式整合 |
| SKILL.md 本文 | **英語必須** | imperative grammar、トークン効率（同一意味で日本語の40〜60%） |
| references/*.md, scripts/ | **英語推奨** | ロジック中心。公式整合 |
| ARCHITECTURE.md / README.md / plans/*.md | **日本語維持** | ユーザーが日常的に読むメタドキュメント |
| ユーザー向け最終出力 | 日本語可 | 私が出力時に翻訳して返す |

---

## 2. ターゲット構造

### Before / After

| 観点 | Before (現状) | After (再設計後) |
|------|--------------|-----------------|
| skill本数 | 16個 | **コア7-8個**（Phase 2で確定） |
| オーケストレーター層 | 3層 (dev-pipeline → impl-orchestrator → 各skill) | **2層** (impl-orchestrator → 各skill) |
| 検査と修正 | 分離・暗黙契約 | **JSON Schema 契約化、修正系は1本に統合** |
| Severity 表記 | 4種類混在 | **Critical/High/Medium/Low の1本** |
| 言語 | 日本語SKILL.md | **英語SKILL.md, 日本語メタドキュメント** |
| Progressive Disclosure | ほぼ未活用（単一SKILL.md） | **references/ scripts/ assets/ に分割** |
| skill間連携 | Agent ツール手動委譲 | `context: fork` / `agent` / `skills` プリロードを採用 |
| 評価機構 | なし | **eval framework 内蔵 (skill-creator ベース)** |

### コア構成案（Phase 2 で最終確定）

| 残す/統合/格下げ/廃止 | Skill | 備考 |
|--------------------|-------|------|
| **Keep** | spec-audit | 仕様書間矛盾検出（spec-check 機能を統合し「仕様↔実装」も担う） |
| **Keep** | impl-orchestrator | エントリーポイント兼務（dev-pipeline 廃止に伴う）、6→4ステージ簡素化 |
| **Keep** | checkpoint | セッション継続。最も軽量 |
| **Keep** | robust-review | 深層セキュリティ/堅牢性レビュー、severity軸統一 |
| **Keep** | code-review | 軽量PRレビュー、severity軸統一 |
| **Keep** | design-phase | 設計書自動生成、references/ 分割 |
| **Keep候補** | boundary-test | description 強化必須（0回の原因はトリガー不全と推定）。impl-orchestrator Stage に統合する案も Phase 2 で検討 |
| **新設 (Merge)** | safe-fix | spec-fix + robust-fix + fix-with-verify を統合。検査系 skill の JSON Finding を入力契約とする |
| **Drop** | dev-pipeline | 0回。impl-orchestrator がエントリー兼務 |
| **Drop** | quick-test | 0回。post-edit-lint hook と機能重複 |
| **Drop** | spec-check | spec-audit に統合 |
| **Drop** | spec-fix / robust-fix / fix-with-verify | safe-fix に統合 |
| **Demote** | pipeline-state | skill から外し、ARCHITECTURE.md 補章として残す |
| **Demote** | escalation | skill から外し、ARCHITECTURE.md 補章として残す。Tier 1/2/3 の判定基準は impl-orchestrator/code-review 等の本文から参照 |

最終本数: **7個（boundary-test 統合の場合）または 8個（独立維持の場合）**。

---

## 3. Phase 別スケジュール

ブランチ: `redesign/heavy` 1本。Phase毎に commit を切るが main へのマージは Phase 6 完了後。

### Phase 0: ベースライン測定 (1セッション)
**目的**: 改善の効果を定量化するための基準値取得。

- skill-creator の eval framework を `~/.claude/plugins/.../skill-creator/scripts/` から参考にコピー or import
- 16個の現行 skill それぞれに triggerable evals を作成
  - 日本語クエリ 10件 + 英語クエリ 10件（各skill）
  - 「明らかにこの skill を呼ぶべきクエリ」と「他の skill と紛らわしいクエリ」を半分ずつ
- baseline 測定 (`scripts/run_eval.py`) で trigger rate を取得
- 結果を `evals/BASELINE.json` に保存

成果物: `evals/queries/<skill>/*.txt`, `evals/BASELINE.json`

### Phase 1: 言語移行 + Description 再設計 (1〜2セッション)
**目的**: 全 skill を英語化し、トリガー精度を上げる。

- 16個全部の SKILL.md を英語化
  - frontmatter: 三人称＋pushy「Use this skill whenever...」形式
  - 本文: imperative grammar、二人称禁止
  - 「USE WHEN / SKIP」式は廃止し、公式準拠の「This skill should be used when...」に変更
- SKIP 句は最大1個、原則ゼロ (A1)
- MUST/NEVER の理由を本文に追記 (A6)
- 各 skill の severity 表記を統一 (A3)

成果物: 全 SKILL.md 英語化済み、Phase 0 と同じ evals で中間測定 (`evals/PHASE1.json`)

### Phase 2: 構造再編 (1〜2セッション)
**目的**: 16個 → 7-8個に統合・削減し、責務境界を明確化。

- **Drop**: dev-pipeline, quick-test を削除（git履歴に保持）
- **Merge spec**: spec-check の機能を spec-audit に取り込み、spec-check は削除
- **New `safe-fix`**: spec-fix + robust-fix + fix-with-verify を統合した1 skill として新設
  - 入力: 検査系 skill が出力する Finding JSON (Phase 4 で契約定義)
  - 動作: severity 別の修正パターンマッチング → 修正 → 検証ゲート → 失敗時 revert
- **Demote**: pipeline-state, escalation を skill 群から外し、ARCHITECTURE.md の補章として吸収
- **boundary-test の決定**: description 強化案 vs impl-orchestrator 統合案を比較、Phase 0 baseline の trigger rate 次第で決定
- impl-orchestrator のステージを 6 → 4 に簡素化 (P4)

成果物: `skills/` 配下が 7-8 個に整理、ARCHITECTURE.md 補章追加

### Phase 3: Progressive Disclosure 適用 (1セッション)
**目的**: SKILL.md を 200行以下にし、詳細を分離。

- 各 skill の SKILL.md を行数調査
- 200行超のものを以下に分割:
  - `references/<topic>.md`: ロジック詳細、変換ルール、エッジケース対応
  - `scripts/<name>.py` or `.sh`: 決定論的処理（ファイル列挙、検証コマンド実行など）
  - `assets/`: テンプレート、ボイラープレート
- SKILL.md 本文に「For X, see references/x.md」を明示 (P3)
- Finding 出力スキーマを `references/schemas/finding.schema.json` として定義 (A4)

成果物: 全 SKILL.md ≤ 200行、references/scripts/assets 構造完備

### Phase 4: 公式新機能の取り込み (1セッション)
**目的**: Anthropic 公式の新機能で skill 連携を効率化。

- impl-orchestrator の Stage 4 (parallel review) を `Agent` ツール委譲から `context: fork` + `agent: parallel` に置換可能か検証
- 関連 skill を `skills:` フィールドでプリロード（例: impl-orchestrator が code-review/robust-review を pre-attach）
- 互換性に問題があれば旧方式を維持（リスク回避）

成果物: frontmatter に context/agent/skills フィールド追加（適用可能なもののみ）

### Phase 5: 再測定 + 最適化ループ (1セッション)
**目的**: baseline からの改善を定量検証し、低トリガー skill を自動最適化。

- Phase 0 と同じ evals を再実行 (`evals/POST.json`)
- BASELINE と diff を可視化（`scripts/compare_evals.py`）
- trigger rate が改善目標未達の skill にだけ skill-creator の `run_loop.py` で description 自動最適化（最大5反復）
- 最適化結果を再 eval してベスト description を選定

成果物: `evals/POST.json`, `evals/DIFF.md`, 必要 skill の description 更新

### Phase 6: ドキュメント整備 + 1週間 dogfooding (0.5セッション + 1週間)
**目的**: 新構造を実運用に乗せ、残課題を回収。

- README.md: 構成図と Component Mapping を新構造で更新
- ARCHITECTURE.md: §11 のチェックリスト全項目を再評価し、現状を反映。pipeline-state/escalation の補章追記
- migration table: 旧16個 → 新7-8個の対応表を `docs/MIGRATION.md` として作成
- main にマージ
- 1週間の実運用で trigger 不全/誤発火を観察、CHECKPOINT.md に記録
- 1週間後にホットフィックス commit を 1〜2件で完結

成果物: 更新された README/ARCHITECTURE、MIGRATION.md、main マージ

---

## 4. 成功基準

Phase 5 で測定し、main マージ可否を判断する。

| ID | 基準 | 目標値 |
|----|------|-------|
| M1 | コア7-8個の trigger rate (BASELINE 比) | **+20% 以上**（個別 skill）、平均 +30% |
| M2 | skill 本数 | 16 → **7-8** |
| M3 | SKILL.md 平均行数 | 現状 → **200行以下** |
| M4 | 30日0回呼び出しの遊休 skill 数 | 9個 → **0個** |
| M5 | Finding 表記の severity 軸 | 4種類 → **1種類** (Critical/High/Medium/Low) |
| M6 | Claude (実利用) の skill 選択遅延 | 体感での改善（定性） |

---

## 5. リスクと緩和

| ID | リスク | 緩和策 |
|----|------|-------|
| R1 | safe-fix 統合スキルが複雑化し、3つの旧 skill より低品質に | references/ で variant 分割（spec/robust/general）、修正パターンを Phase 3 で明文化 |
| R2 | 英語化で Claude のトリガー精度が逆に低下する skill が出る | Phase 5 の再測定で diff 確認、悪化 skill は run_loop.py で自動最適化 |
| R3 | 既存 hooks (post-edit-lint等) との境界が再編後にずれる | Phase 6 で hooks との責務マトリクスを再確認、quick-test 廃止に伴う代替を hooks 側で吸収 |
| R4 | dev-pipeline 廃止で「全フェーズ統合エントリーポイント」を喪失 | impl-orchestrator が事前条件 (DESIGN/*.md 存在) をチェックし、不在なら design-phase を Agent 委譲する形でフォールバック |
| R5 | eval 作成コスト (16skill × 20件 = 320件) | Claude が下書き → ユーザーレビューで進める。Phase 0 完了基準を「各skill 10件以上」に緩和可能 |

---

## 6. ブランチ戦略

- 単一ブランチ `redesign/heavy` で Phase 0〜6 を実行
- main へのマージは Phase 6 完了後の **1回のみ**（ユーザー意向: まとめて見えてくる課題を拾う）
- Phase 毎に commit を切り、commit message に Phase 番号を含める（例: `phase 1: english migration of 16 skills`）
- 各 Phase 終了時に `CHECKPOINT.md` を更新（次セッション再開用）
- 不採用化したい変更があれば `git revert <commit>` で戻せる粒度を維持
- main は触らない（緊急時の hotfix を除く）

---

## 7. 計画外（次回以降）

- skill 自動評価の CI 化（GitHub Actions で PR 毎に trigger rate 計測）
- 他プロジェクトへのスキルテンプレ展開（claude-pipeline を skeleton 化）
- Cowork (マルチエージェント協調) 対応
- skill 単体配布（Anthropic skill marketplace への submit 検討）

---

## 8. 着手前チェックリスト

Phase 0 着手前に以下を満たすことを確認:

- [ ] 本計画にユーザー承認
- [ ] `redesign/heavy` ブランチ作成
- [ ] Phase 0 の eval framework コピー元 (`~/.claude/plugins/.../skill-creator/scripts/`) の存在確認
- [ ] 既存 16 skill の現状 SKILL.md 行数を計測（Phase 3 の改善基準値）
- [ ] BASELINE 測定中に並行作業が走らないようコミット禁止期間を確保（半日程度）
