# イベント発火による前進の自動化（WS4）

> 対象: claude-pipeline / 起点: [plans/PIPELINE-V2-PLAN.md](../plans/PIPELINE-V2-PLAN.md) WS4

既存 hook 4 種は全て「守り」（破壊コマンドブロック / lint / 検証ゲート / セッション情報、[ARCHITECTURE.md](../ARCHITECTURE.md) §9）。
本書は**前進を自動化する**発火 F1〜F3 を定義する。共通の安全則: **これらは PR を生むだけで、main への merge は常にユーザーゲート**（ARCHITECTURE.md §A、`ship` の既定）。

---

## F1: Stop hook による `/ship` 提案（実装済み）

`hooks/stop-ship-suggest.sh`。Claude が応答を終えた時、**origin の既定ブランチに未反映のコミットがあり、かつ作業ツリーが clean** なら「配信可能な作業がある」と判断し `/ship` を提案する。

- **非ブロッキング**: 出力は `{"systemMessage": "..."}` のみ（exit 0）。`continue:false` を**出さない**ので Stop を阻害しない。Stop hook の出力契約上 `continue:false` は強制続行（＝ブロック）なので使わない（公式 hooks doc で確認）。これは ESCALATION-REDESIGN §11.2 の「スキーマ取り違えで実際には発火しなかった」轍を踏まないための要点。
- **発火条件を絞る理由**: dirty tree（作業途中）では提案しない＝ノイズ抑制。未 push コミットという強いシグナルだけに反応する。
- **`gh` を呼ばない**: 速度優先で git のみ。既存 open PR の判定は `/ship` 側に委ねる。
- **drift gate と非干渉**: clean tree 時のみ発火するため、`git diff` ベースの drift gate（[.claude/settings.json](../.claude/settings.json)）とは条件が重ならない。
- **配線**: `.claude/settings.json` の `Stop` に command hook として追加済み（agent 型 drift gate と同居）。

---

## F2: cron による定常検査 → 修正 PR（設計・テンプレートのみ）

`scheduled-tasks` MCP / `CronCreate` で定期実行する自律ジョブ。例:

> 毎朝 origin/main を取得 → `/spec-audit --mode=cross`（or goal 駆動なら SHARED-CONTRACT.md 照合）＋ 変更範囲の `/robust-review` → Tier 2/3 のみ自律修正 → `/ship`（PR 作成、**merge せず**）

- **安全則**: 1 実行 1 PR。同名ブランチの open PR があればスキップ（PR 量産防止）。merge しない。Tier 1 は PR 本文に列挙してユーザー判断へ。
- **未自動登録**: cron ジョブ登録は standing な自律エージェント生成のため、**ジョブごとにユーザーが明示登録**する（本書はテンプレートのみ。エージェントが勝手に cron を作らない）。
- 登録例（schedule skill 経由）:
  `/schedule "毎朝9時、main で spec-audit + robust-review、修正は /ship で PR 化（merge しない）"`

---

## F3: PR-open での自動 robust-review（設計）

新規 PR に `robust-review` を自動実行し、findings を PR コメント化（`/code-review --comment` 相当）。2 方式:

| 方式 | 長所 | 短所 |
|------|------|------|
| cron-poll（推奨初手） | 追加インフラ不要。F2 と同じ cron で「未レビュー PR」を拾う | 即時性が低い（ポーリング間隔依存） |
| GitHub Actions（native） | PR open で即時、CI 統合 | Actions 設定＋ headless 認証が必要 |

- headless 実行では MCP / 認証が無い場合がある（ARCHITECTURE 監視項目）。cron 実行ユーザーの `gh` 認証を前提に。
- review コメントは判断材料でありブロックしない（required check 化は別途）。

---

## まとめ

F1 は hook として実装済み。F2/F3 は設計・テンプレートのみで、登録はユーザー明示。
**全発火は PR までで止まり、main への merge は常にユーザー（`ship` の既定ゲート）**。
