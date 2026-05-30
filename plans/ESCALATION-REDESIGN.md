# エスカレーション削減リデザイン

> 作成: 2026-05-10 / 対象: claude-pipeline (8 skill 構造) / 起点: Phase 6 dogfooding 中の課題提起

## 背景・目的

skill 実行中、技術判定（妥当性・批評・リスク評価など）をユーザーに尋ねるとフローが中断する。ユーザーの知識量で Claude/agent に勝つことは現実的に少なく、user 中断はむしろ品質を下げる場面がある。

**目的**: skill → user のエスカレーションのうち「技術判定」を専門役 agent に委譲し、user 判定は「スコープ・優先度・好み・業務判断」に絞る。

**方針**:
- technical-judgment → agent 委譲（自動化）
- intent-judgment → user 必須（変更しない）
- 委譲 agent の判断は decision log として残し、誤判断の事後検証を可能にする

---

## 1. 棚卸し結果（直近2ヶ月のエスカレーションパターン）

### 1.1 サマリ

調査対象: 2026-03-10 以降の transcript 約 2736 件のうち、戦略サンプリング 100〜300 件 + 各 SKILL.md の escalation 設計箇所。

抽出したパターンを以下 3 種に分類。

### 1.2 technical-judgment（agent 委譲候補）— 4 種

| # | パターン | 発生 skill | 頻度 | 例 |
|---|---------|----------|------|---|
| T1 | Constant/Type name drift | spec-audit | 高 | `CONNECT_TIMEOUT_MS = 3000` vs `5000`、`TransactionId` vs `transaction_id` |
| T2 | API contract type mismatch | boundary-test | 中 | `userId` vs `user_id`、response shape の frontend ↔ backend 不一致 |
| T3 | Security/robustness 定型修正 | robust-review → safe-fix | 高 | SQL parameter 化、`unwrap` → `?` operator |
| T4 | Test failure 回帰判定 | safe-fix | 中 | この test failure は fix 関連か pre-existing か |

### 1.3 intent-judgment（user 必須）— 5 種

| # | パターン | 発生 skill | 例 |
|---|---------|----------|---|
| I1 | 設計の根本選択（どちらの仕様が正か） | design-phase, spec-audit | snake_case 統一の業務理由 |
| I2 | Design-change loop 二度目（要件漏れ） | impl-orchestrator | spec 修正→実装→再 review で同じ issue |
| I3 | Component Mapping 未定義 | impl-orchestrator | `src/auth/` か `src/features/auth/` か |
| I4 | 自動修正が test を壊す場合の判断 | safe-fix | revert すべきか別解か |
| I5 | Boundary test の design-level disagreement | boundary-test | frontend/backend どちらに合わせるか（リリース日依存） |

### 1.4 ambiguous — 2 種

- A1: Escalation Overrides の適用判定（プロジェクト固有ルール既知/不明）
- A2: Project-Specific Checks（CLAUDE.md カスタムルール）の解釈

### 1.5 skill 別の Tier 1 escalation 頻度傾向

| skill | Tier 1 率 | 主因 |
|-------|----------|------|
| spec-audit | **15〜20%** | naming rule / API contract conflict |
| impl-orchestrator | **10〜15%** | Stage 3 review の spec-level mismatch |
| boundary-test | 10〜15% | type mismatch が design disagreement の兆候 |
| design-phase | 5〜10% | domain knowledge contradiction |
| robust-review | 5% 以下 | ほぼ自動修正可 |
| safe-fix | 5% 以下 | 修正が test を壊す場合のみ |

→ **spec-audit と impl-orchestrator が最大の改善ターゲット**

---

## 2. 調査結果（2026-05 時点の体系パターン）

### 2.1 Anthropic 公式パターン

#### Subagent の役割分離
[Create custom subagents - Claude Code Docs](https://code.claude.com/docs/en/sub-agents)
- 独立したコンテキストウィンドウ、カスタムシステムプロンプト、ツール制限可
- description ベースで自動委譲、または明示呼び出し
- **判定用途への適性が高い**

#### Hooks による Judgment Gate
[Automate workflows with hooks - Claude Code Docs](https://code.claude.com/docs/en/hooks-guide)
- Command Hook（決定論的ゲート）/ Prompt Hook（軽量モデルでセマンティック判定）/ Agent Hook（深い検証）
- claude-pipeline では Stop hook + Prompt Hook で「skill 終了時の drift gate」が即実装可能

#### Building Effective AI Agents の 6 パターン
[Anthropic Research](https://www.anthropic.com/research/building-effective-agents)
- claude-pipeline に直結するのは:
  - **Orchestrator-Workers**: 中央が分解 → 専門 worker → 統合（既存構造そのもの）
  - **Evaluator-Optimizer**: 評価 → 改善 ループ（review→safe-fix サブループに対応）

### 2.2 注目すべき多 agent 設計パターン

| パターン | 概要 | claude-pipeline への適用 |
|---------|------|----------------------|
| **MAR (Multi-Agent Reflexion)** | Actor / Evaluator / Critic を分離。単一 agent の確認バイアスを回避 | impl-orchestrator 内で生成・批評・仕様確認を並列化 |
| **Agent-as-Judge with PRM** | 推論ステップごとにスコア化 | code-review のステップ検証、spec-audit の中間判定 |
| **Constitutional AI Self-Critique** | 価値原則 checklist で自動検証 | 各 skill 後の DESIGN との一貫性チェック |
| **Critic-Actor (Reflexion 系)** | Actor 実行 → Critic 独立評価 | skill 出力後の dedicated critic subagent |

### 2.3 実装事例の参照先

- **[anthropic-cookbook/patterns/agents](https://github.com/anthropics/anthropic-cookbook/tree/main/patterns/agents)**: `orchestrator_workers.ipynb`, `evaluator_optimizer.ipynb`, lead agent prompt 例
- **[How we built our multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system)**: Lead → 並列 subagent (3〜5) → 統合。並列化で最大 90% token 削減
- **[disler/claude-code-hooks-mastery](https://github.com/disler/claude-code-hooks-mastery)**: Hooks 実装例集

### 2.4 取り込まないほうが良いもの

| 項目 | 理由 |
|-----|------|
| Full Autonomous Optimization Loop | claude-pipeline は user 駆動、最適化判定は user 領域 |
| Constitutional AI 厳密適用 | 各ステップ検証コスト増、現段階では単発 spec チェックで十分 |
| Process Reward Models 自前学習 | カスタム training 必要、subagent + hooks で代替可 |

---

## 3. リデザイン提案

### 3.1 P1: `technical-arbiter` subagent

**役割**: naming/type drift 系で「正解候補を1つ提示 + 根拠」を返す judgement-only agent

**配置**: `~/.claude/agents/technical-arbiter.md`

**ツール**: Read / Glob / Grep のみ（read-only）

**呼び出し元**:
- spec-audit (Mode A/B) が drift 検出時、user に上げる前に arbiter 経由
- boundary-test が type mismatch 検出時も同様

**期待効果**:
- spec-audit の Tier 1 率 15〜20% → 5〜10%
- T1, T2 パターンを agent 内で吸収

**根拠**: Orchestrator-Workers パターン + Anthropic Cookbook `orchestrator_workers.ipynb`

### 3.2 P2: `regression-judge` subagent

**役割**: safe-fix で test failure が「fix 関連 / pre-existing」を git log/diff から判定

**入力**: 失敗テスト名、直前 diff、`git log -- <test_file>`

**期待効果**:
- T4 パターン（safe-fix の ambiguous escalation）がほぼ 0
- 人間中断頻度の低下

**根拠**: Agent-as-Judge / Critic-Actor の軽量版（PRM 学習は不要）

### 3.3 P3: Stop hook による drift gate（軽量・補助）

**役割**: skill 終了直前に「DESIGN/*.md との不一致」を 10 秒チェック → 警告のみ（user 決定はしない）

> **注 (2026-05-30)**: 本 §3.3 と下の設定例は **2026-05-10 時点の提案**。実装時に当初案から乖離した (`type:prompt`→`type:agent`、warning-only→blocking、DESIGN/*.md→SKILL.md 照合、15s→60s)。**現行の正となる記述は §5 P3 実装 + [ARCHITECTURE.md](../ARCHITECTURE.md) §11.2**。

**位置付け**: P1/P2 の前段。そもそも escalation を起こさないための早期検出

**設定例**:
```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "prompt",
            "prompt": "Compare recent edits against DESIGN/*.md. Return JSON: {\"compliant\": bool, \"gap\": string|null}",
            "model": "claude-sonnet-4-6",
            "timeout": 15000
          }
        ]
      }
    ]
  }
}
```

---

## 4. 決定事項（2026-05-10）

### 4.1 モデル選定

| 用途 | モデル | 理由 |
|-----|-------|------|
| P1 technical-arbiter | **Sonnet 4.6** | 判断品質が下流 skill に影響、呼び出し頻度は低（drift 検出時のみ） |
| P2 regression-judge | **Sonnet 4.6** | git history + diff の解析品質を優先、頻度低 |
| P3 Stop hook drift gate | **Sonnet 4.6**（dogfooding 後に Haiku 4.5 へ降格を検討） | 高頻度実行だがコスト許容範囲、判定漏れ時の影響を抑える |

**Haiku 4.5 について**: 2025-10 リリース以降アップデートなしで 7 ヶ月。narrow scope + 厳密な出力スキーマ + false-negative 許容範囲なら問題なく使えるが、初期は Sonnet 4.6 で recall 重視。Phase 6 dogfooding でコスト/レイテンシ問題が顕在化したら P3 のみ Haiku 4.5 へ降格を検討。

### 4.2 着手順序

1. **P1 PoC（最小単位）**: technical-arbiter 定義 + spec-audit Mode A の naming drift のみに繋ぎ込む
2. Phase 6 dogfooding で効果測定（spec-audit Tier 1 率の推移）
3. **P2 着手**: P1 が機能していれば regression-judge を追加
4. **P3 着手**: P1/P2 安定後、Stop hook drift gate を導入

### 4.3 触らないもの

- 5 種の intent-judgment（I1〜I5）は user 必須のまま
- 既存 8 skill の責務分担は維持
- Orchestrator-Workers / Evaluator-Optimizer の既存構造は変更なし

---

## 5. 次のステップ

### P1 実装（完了: 2026-05-10）

- [x] `agents/technical-arbiter.md` の agent 定義を作成（英語、SKILL本体ポリシーに準拠、tools: Read/Glob/Grep, model: claude-sonnet-4-6）
- [x] spec-audit Mode A の category 1/6/7 から arbiter 呼び出しを追加（`skills/spec-audit/SKILL.md` の `### Arbitration` 節）
- [x] decision log 形式の決定 — `evals/arbiter-decisions.jsonl`（append-only、1 行 1 JSON）
- [x] `~/.claude/agents/` directory junction 作成（project の `agents/` 配下を反映、追加 agent は自動連携）

### Phase 6 dogfooding での観察項目

- [ ] arbiter の confidence high/medium 判定の精度（user 最終判定との乖離率）
- [ ] deferral 比率（low confidence + non-technical 含む）
- [ ] spec-audit Tier 1 escalation 率の推移（目標: 15〜20% → 5〜10%）
- [ ] arbiter のレイテンシ実測（hook 化を検討する材料）

### P2 実装（完了: 2026-05-23）

- [x] `agents/regression-judge.md` を作成（sonnet 4.6、Read/Glob/Grep、test failure の fix-related / pre-existing / uncertain 判定）
- [x] `skills/impl-orchestrator/references/subagent-calls.md` で input/output contract を文書化
- [x] `skills/impl-orchestrator/SKILL.md` Stage 3-6 と `references/robust-fix.md` から呼び出し参照を追加
- [x] `~/.claude/agents/` directory junction 経由で自動連携

### P3 実装（完了: 2026-05-23、agent 化 `3b672fc` / スキーマ修正 `02922ae` 2026-05-30）

- [x] `.claude/settings.json` に Stop hook (drift gate) を追加。**実装時に §3.3 当初案から変更** (commit `3b672fc`): `type:prompt`→`type:agent`、照合先は DESIGN/*.md 不在のため SKILL.md frontmatter+body、sonnet 4.6、60s timeout、read-only ツール (Bash `git diff` / Read / Grep / Glob) で編集を spec と照合
- [x] **当初の「警告のみ」から blocking へ変更**: agent hook は `{"ok":true}` / `{"ok":false,"reason"}` を返し、矛盾検出時は Stop を block して reason を Claude に戻す
- [x] **スキーマ修正 (2026-05-30, commit `02922ae`)**: `3b672fc` は agent hook へ切替えつつ command-hook の `{"decision":"block"}` を残しており**実際には block していなかった**。agent hook 正の `{"ok":...}` へ修正 (公式 hooks-guide #agent-based-hooks で一次検証、[ARCHITECTURE.md](../ARCHITECTURE.md) §11.2)

---

## 参考 URL

**Anthropic 公式:**
- [Create custom subagents](https://code.claude.com/docs/en/sub-agents)
- [Automate workflows with hooks](https://code.claude.com/docs/en/hooks-guide)
- [Building Effective AI Agents](https://www.anthropic.com/research/building-effective-agents)
- [How we built our multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system)

**実装参考:**
- [anthropic-cookbook/patterns/agents](https://github.com/anthropics/anthropic-cookbook/tree/main/patterns/agents)
- [disler/claude-code-hooks-mastery](https://github.com/disler/claude-code-hooks-mastery)

**論文・パターン解説:**
- [MAR: Multi-Agent Reflexion (arXiv 2512.20845)](https://arxiv.org/html/2512.20845v1)
- [LLM as a Judge: A 2026 Guide](https://labelyourdata.com/articles/llm-as-a-judge)
