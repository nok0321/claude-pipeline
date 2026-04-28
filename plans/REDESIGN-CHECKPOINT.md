# Redesign Checkpoint: Phase 4 完了 → Phase 5 着手

Updated: 2026-04-29

## 現在地

- ブランチ: `redesign/heavy` (main は触らない、Phase 6 完了時に 1 回マージ)
- 計画書: [REDESIGN-PLAN.md](REDESIGN-PLAN.md)
- 完了 commits (新しい順):
  - `0e2cf8a` Phase 4 Step 2: formalize Finding schema + propagate JSON emission (Sub-P)
  - `92cd74f` Phase 4 Step 1: extend context: fork to safe-fix + boundary-test (Sub-M)
  - `fa60ed7` Phase 3 Step 6: update CHECKPOINT for Phase 4 handoff
  - `ec1b8da` Phase 3 Step 5: tweak robust-review 209 → 177 lines (Sub-K)
  - `b9b3bce` Phase 3 Step 4: split safe-fix 236 → 150 lines + finding.schema.json (Sub-I-4 + Sub-J)
  - `654c758` Phase 3 Step 3: split impl-orchestrator 299 → 200 lines (Sub-I-3)
  - `56cc653` Phase 3 Step 2: split boundary-test 331 → 196 lines (Sub-I-2)
  - `882831c` Phase 3 Step 1: split design-phase 346 → 194 lines (Sub-I-1)
  - `48b3249` Phase 2 Step 7: update CHECKPOINT for Phase 3 handoff
  - `81de55e` Phase 2 Step 6: add docs/MIGRATION.md
  - `d224ac3` Phase 2 Step 5: simplify impl-orchestrator 6→4 stages
  - `312347c` Phase 2 Step 4: demote pipeline-state/escalation to ARCHITECTURE.md §A/§B
  - `f8ae499` Phase 2 Step 3: add safe-fix skill (3 modes)
  - `fa2c275` Phase 2 Step 2: integrate spec-check into spec-audit (Mode A + B)
  - `3bace02` Phase 2 Step 1: drop 6 obsolete skills
  - `8629c9e` Phase 2 Step 0: phase 1 verification + sub-f isolation test
  - `c0192cc` checkpoint: phase 1 done
  - `6fbdff7` Phase 1: 英語化 + pushy descriptions
  - `80d9f60` Phase 0 fix: 5 skill 再測定
  - `3f9fbeb` checkpoint: phase 0 done
  - `2054bb7` Phase 0 baseline
  - `db36059` Phase 0 scaffolding
  - `4991cdf` 計画書追加

---

## Phase 4 実行結果 (2026-04-29, redesign/heavy: 2 commits)

| Sub | 内容 | 判定 | commit / 反映先 |
|-----|------|------|----------------|
| M | `context: fork` 検証 | 部分適用 | `92cd74f` (safe-fix, boundary-test) |
| N | `agent: parallel` 検証 | 見送り (R2) | この CHECKPOINT (理由記載) |
| O | `skills:` プリロード | 見送り (R2) | この CHECKPOINT (移行パス記載) |
| P | Finding schema 正式化 | 適用 | `0e2cf8a` (schema + 5 ファイル) |

### Sub-M: `context: fork` (部分適用)

公式仕様 (https://code.claude.com/docs/en/skills) 確認:
- `context: fork` は SKILL.md frontmatter フィールドとして公式
- 併記される `agent` フィールドは subagent 型名 (Explore / Plan / general-purpose / `.claude/agents/<name>` のカスタム) を取り、省略時は `general-purpose`

| skill | Phase 1 | Phase 4 | 判断根拠 |
|-------|:-------:|:-------:|---------|
| robust-review | ✓ | (継続) | 純 task skill、$ARGUMENTS 駆動 |
| code-review | ✓ | (継続) | 同上 |
| spec-audit | ✓ | (継続) | 同上 |
| safe-fix | — | ✓ | $ARGUMENTS 駆動 (Findings/file:line/issue)、allowed-tools に Agent 無し、入れ子フォーク無し |
| boundary-test | — | ✓ | detect/generate/run の純 task、Agent 無し |
| design-phase | — | 見送り | allowed-tools に Agent あり、内側で sonnet sub-agent を起動するため fork-in-fork セマンティクス未文書化 |
| impl-orchestrator | — | 見送り | Stage 1-4 を跨ぐ orchestrator、main session の状態 (gate_results, findings, escalation_queue) を保持する必要 |
| checkpoint | — | 見送り | conversation history を読みに行くため fork は機能せず |

orchestrator Stage 3-2 の 3 reviewers (security/robustness/spec-compliance) の `context: fork` 化については以下 2 案を検討:

- **案 A**: 既存 robust-review skill (security+robustness を 1 軸に統合済み) と spec-audit `--mode=conformance` skill を Skill ツール経由で並列呼び出し → 3 → 2 軸並列に縮退、security/robustness の axis 分離が消える
- **案 B**: `.claude/agents/<reviewer>.md` のカスタム subagent を 3 個新設し、orchestrator から呼び出す (Sub-O 同等の構造変更)

どちらも eval 実行禁止下では検証不能、かつ単純化の効果が不明。Phase 5 で BASELINE 差分を確認後、現行「1 message × 3 Agent inline prompts」の維持/移行を再判断する。

### Sub-N: `agent: parallel` (見送り、R2)

PLAN §3.4 が想定した「Stage 3-2 を `agent: parallel` フィールド 1 行で書き換え」は公式仕様に該当機能なし:
- `agent` フィールドは単一 subagent 型名のみ受け取る (`Explore` / `Plan` / `general-purpose` / カスタム)
- `parallel` という enum 値は存在しない
- 並列化の公式パターンは「1 つのターンで複数 Agent ツール呼び出しを発行」 — orchestrator の review-prompts.md `Stage 3-2: dispatch (parallel)` で既に採用済み

結論: 既存実装は公式パターン通り。frontmatter 経由の単純化は不可。コード変更なし。

### Sub-O: `skills:` プリロード (見送り、R2、移行パス記録)

PLAN §3.4 が想定した「impl-orchestrator の frontmatter に `skills:` を追加して reviewer skill 群をプリロード」は公式仕様に該当機能なし:
- 公式 frontmatter リファレンス (https://code.claude.com/docs/en/skills#frontmatter-reference) に `skills:` フィールドは存在しない
- `skills:` は subagent 定義 (`.claude/agents/<name>.md`) 側のフィールドで、その subagent が呼ばれた際に列挙された skill を pre-attach する仕組み

公式パターンに沿った移行パス (Phase 5+ で再検討):
1. `.claude/agents/security-reviewer.md` を新設、frontmatter に `skills: [robust-review]` を持たせる
2. 同様に `robustness-reviewer.md`, `spec-reviewer.md` を作成 (spec-reviewer は `skills: [spec-audit]`)
3. orchestrator の Stage 3-2 から各 subagent を Agent ツール経由で呼び出す (3 並列パターンは維持)

採用見送りの理由:
- `.claude/agents/` は現在プロジェクト未管理 (git status `?? .claude/`)、新ファイルを版管理対象にする判断が別途必要
- Sub-M 案 B と同じ構造変更で、eval なしでは効果検証不能
- 現行「inline prompt × 3 Agent」は機能しており、緊急性なし

### Sub-P: Finding schema 正式化 (適用)

`skills/safe-fix/references/finding.schema.json` を Phase 3 informal → Phase 4 canonical に昇格 (`0e2cf8a`):

- schema 内 `description` を「informal / Phase 3 / Phase 4 で formal 化予定」→「canonical Phase 4 contract」に書き換え。`category` の自由文字列許容 (security/robustness reviewer 都合) と conformance reviewer の固定 enum 要件を併記
- `safe-fix/SKILL.md` 「Finding input contract」セクションを正式版に書き換え + 4 ステップ「Validation step」を追加 (locate → parse → field/pattern check → Tier 1 escalation on mismatch、silent filter 禁止)
- 上流 4 ファイルに schema 準拠 JSON Findings block の出力を追加:
  - `spec-audit/SKILL.md` (SPEC-/AUDIT- prefix、spec_ref 必須)
  - `robust-review/references/output-format.md` (SEC-/ROB- prefix、attack/impact は Critical-High のみ)
  - `code-review/SKILL.md` (CR- prefix)
  - `impl-orchestrator/references/review-prompts.md` (Stage 3-2 の 3 inline reviewer prompt それぞれに JSON 出力指示を末尾追加)

すべての SKILL.md は ≤200 行を維持 (M3 達成継続)。

### Phase 4 後の SKILL.md 行数

| skill | Phase 3 後 | Phase 4 後 | P5 (≤200) |
|-------|---:|---:|:---:|
| `checkpoint` | 68 | 68 | ✓ |
| `code-review` | 131 | 141 | ✓ |
| `safe-fix` | 150 | 168 | ✓ |
| `robust-review` | 177 | 177 | ✓ |
| `spec-audit` | 190 | 197 | ✓ |
| `design-phase` | 194 | 194 | ✓ |
| `boundary-test` | 196 | 197 | ✓ |
| `impl-orchestrator` | 200 | 200 | ✓ |
| **合計** | 1306 | **1342** | — |
| **平均** | 163 | **168** | — |

`+36 行` (Sub-P JSON emission 指示の追加分)。M3 「平均 200 行以下」継続達成。

---

## Phase 5 サブタスク

PLAN §3.5 の通り、再測定 + 最適化ループを実行する。

### Sub-Q: POST eval 実行

- Phase 0 で作成した `evals/queries/<skill>/*.txt` を最新の skill 構成 (drop 済み 6 skill 分は除外、merge された safe-fix は新規追加) で再構成
- `scripts/run_eval.py` を実行し `evals/POST.json` を生成
- 実行時は `WORKERS=3` 必須 (Phase 0 で 5 skill、Phase 1 で 6 skill が rate-limit artifact で 0% を記録した先例。`evals/scripts/README.md` 参照)
- skill 編集が完了した直後でないと測定汚染するため、本 commit の作業中は eval を走らせない (このサブの開始時点が最初の安全な実行点)

### Sub-R: BASELINE diff 可視化

- `scripts/compare_evals.py` で `evals/BASELINE.json` (Phase 0) との diff を `evals/DIFF.md` に出力
- skill 別 trigger rate 推移、目標 (M1: +20% 個別 / +30% 平均) との差分を表化
- M1 評価は **新 8 skill 限定** で行う (boundary-test / checkpoint / code-review / design-phase / impl-orchestrator / robust-review / safe-fix / spec-audit)。BASELINE.json は 15 skill 全部の値を含むが、Phase 2 で drop された 7 skill は比較対象から除外する
- `safe-fix` の base 値は新設 skill につき存在しないため、旧 fix-with-verify + robust-fix + spec-fix の `trigger_rate_overall` の **最大値** を proxy とする (統合先がカバーすべき責務上限という解釈)

### Sub-S: 低トリガー skill の自動最適化

- DIFF で改善目標未達の skill を特定
- skill-creator の `run_loop.py` (`~/.claude/plugins/.../skill-creator/scripts/run_loop.py`) を最大 5 反復で実行し description を自動最適化
- 各反復後に再 eval して best description を選定、commit

### Sub-T: Phase 4 で見送った構造変更の判断

Sub-M 案 A/B、Sub-O 移行パスの採否を eval 結果次第で再判断:
- BASELINE 差分が十分大きく、構造変更の効果検証不要なら現行維持
- 改善余地があり、かつ Sub-M/O の移行が低リスクと判断できれば Phase 6 で適用
- いずれも判断材料なしでは決定不能なため Sub-Q/R 完了後に着手

### 成果物

`evals/POST.json`, `evals/DIFF.md`, 必要 skill の description 更新 commit、Phase 6 計画調整。

---

## 維持事項

- ARCHITECTURE.md / README.md / plans/* / docs/MIGRATION.md / evals/ は日本語維持
- ユーザー出力は日本語可
- skills/ 編集中は eval 実行禁止 (測定汚染防止) — Phase 5 では skill 編集と eval を交互に実施するため特に注意
- main にはマージしない (Phase 6 完了まで `redesign/heavy` 1 本)
- 並列 Bash/Agent 実行を避ける (前セッションでメッセージ上限到達)
- 長時間 eval (>60min) は Monitor を 60 分ごとに再武装

## 引き継ぎメモ

- True baseline = 0.293 (`evals/BASELINE.json`)、Phase 1 trigger = 0.238 (artifact 込み)
- Phase 2 / 3 / 4 を通して eval 未実施 — Phase 5 Sub-Q がプロジェクト初の Phase 4 後測定
- ARCHITECTURE.md `§A 補章 (Escalation framework)` と `§B 補章 (Pipeline state file)` は impl-orchestrator が常時参照する核ドキュメント
- safe-fix の Finding 入力契約は `skills/safe-fix/references/finding.schema.json` (Phase 4 で formal 化、`finding_id` パターン `^(SPEC|AUDIT|SEC|ROB|CR)-[0-9]+$`、`severity` enum 4 値)
- 上流 reviewer (spec-audit / robust-review / code-review / orchestrator inline reviewer ×3) はすべて schema 準拠 JSON Findings block を末尾出力
- safe-fix は入力 JSON を 4 ステップで検証し schema 不一致なら silent filter せず Tier 1 escalation
- `context: fork` 適用済み skill: robust-review, code-review, spec-audit (Phase 1)、safe-fix, boundary-test (Phase 4)
- `context: fork` 未適用 skill とその理由: design-phase (Agent 入れ子)、impl-orchestrator (orchestrator 状態)、checkpoint (session history)
- Sub-N/O は公式仕様の不在により frontmatter 経由の単純化が不可。並列化は既存「1 メッセージ × 複数 Agent」が公式パターン
- `evals/results/{baseline-resub,smoke,smoke-direct,smoke-pushy}/` は Phase 0/1 の人手測定結果、git untracked のまま (Phase 5 で必要なら整理)
- `.claude/` も untracked。Sub-O 移行パスを採用する場合は `.claude/agents/` のうち pipeline 関連分のみ git 管理対象にするか別途検討

## メッセージ上限対策

- Phase 5 は eval が長時間化しがち。Sub-Q/R は単発実行 (Bash run_in_background + Monitor)、Sub-S は反復のため 1 反復ごとに commit
- TodoWrite 推奨 (4 Sub を順次評価するため)
- 1 Sub ごとに 1 commit を切る (Phase 2 / 3 / 4 と同様)

---

## 新規セッション開始プロンプト

```
claude-pipeline 重量整理 Phase 4 完了、Phase 5 (再測定 + 最適化ループ) 着手をお願いします。
- 作業ブランチ: redesign/heavy
- 状況: plans/REDESIGN-CHECKPOINT.md と plans/REDESIGN-PLAN.md §3.5 を最初に読んでください
- Phase 4 結果: Sub-M 部分適用 (safe-fix/boundary-test に context: fork 追加)、Sub-N/O は公式仕様非対応で見送り (R2)、Sub-P は Finding schema を formal 化し上流 5 reviewer に schema 準拠 JSON 出力を要求。
- Phase 5 のスコープ: PLAN §3.5。POST eval → BASELINE diff → 未達 skill の description 自動最適化。Phase 4 で見送った構造変更の採否は diff 結果で再判断 (Sub-T)。
- 注意: Sub-Q が初回 eval なので skill 編集後の状態を凍結してから走らせる、main にはマージしない、Bash/Agent 並列禁止
- eval は `WORKERS=3` で実行 (過去 2 回 rate-limit artifact 発生)
- M1 評価は新 8 skill 限定 + `safe-fix` は旧 3 skill (fix-with-verify / robust-fix / spec-fix) の trigger_rate 最大値を proxy とする
```
