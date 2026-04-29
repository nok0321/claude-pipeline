---
name: safe-fix
description: Use this skill whenever the user has a batch of remediation items (severity-tagged findings, design-vs-implementation drifts, or pattern-based fixes across many files) and wants them processed in a controlled loop — one edit at a time, with a verification gate (build / type / test) running between every edit and an automatic revert when the gate goes red, optionally iterating until the diff converges. Trigger phrases include "auto-fix the critical findings batch", "remediate the unwrap and injection patterns from the audit", "reconcile the design and implementation in a loop", "apply the spec-vs-code fixes until the diff hits zero", "patch all the high-severity findings with verification between each", "loop the conformance fixes until convergence", "apply the standard pattern fixes from the audit", or any multi-item remediation request that wants a verification step and a revert net between edits. Trigger even when the user does not say "safe-fix" — phrases like "auto-apply all the unwrap and SQL injection fixes from review", "close the gap between design and code in batch", "loop until the audit diff is empty", or "patch the 12 findings and revert any that break tests" qualify.
argument-hint: "[finding-source | file:line | issue-description] [--mode=conformance|robust|adhoc] [--spec-wins | --impl-wins | --dry-run | --loop [N]]"
allowed-tools: Read, Write, Edit, MultiEdit, Bash, Grep, Glob
model: claude-opus-4-7
context: fork
---

# safe-fix: finding-driven remediation with verification gate

Replaces the retired `spec-fix`, `robust-fix`, and `fix-with-verify`
skills. Drives a single fix → verify → revert-on-failure loop with
three input modes, a unified verification gate, and a unified revert
policy.

Detail references:
- [mode-conformance.md](references/mode-conformance.md) — Mode A direction tables, per-finding actions, `--loop`
- [mode-robust.md](references/mode-robust.md) — Mode B severity gate and pattern table
- [mode-adhoc.md](references/mode-adhoc.md) — Mode C four-step procedure
- [output-format.md](references/output-format.md) — final report block
- [finding.schema.json](references/finding.schema.json) — formal Finding contract

---

## Input modes

The mode is auto-detected from the source of findings, or forced by
`--mode=`:

| Mode          | When                                                                            | Replaces        |
|---------------|---------------------------------------------------------------------------------|-----------------|
| `conformance` | Findings from `spec-audit` Mode B (Missing / Diverged / Extra / Constraint)     | spec-fix        |
| `robust`      | Findings from `robust-review` (SEC-* / ROB-*, severity-tagged)                  | robust-fix      |
| `adhoc`       | Free-form bug description or `file:line`, no upstream finding                   | fix-with-verify |

Per-mode procedure lives in `references/mode-<mode>.md`.

---

## Finding input contract

Findings flow in as a JSON array conforming to
[references/finding.schema.json](references/finding.schema.json) (the
canonical Phase 4 contract). Each entry has the fields below:

```json
{
  "finding_id": "SPEC-1 | AUDIT-3 | SEC-1 | ROB-3 | CR-1",
  "severity": "Critical | High | Medium | Low",
  "category": "Missing | Diverged | Extra | Constraint | SQL injection | unwrap | ...",
  "file": "path:line",
  "spec_ref": "DESIGN/...:N (conformance only)",
  "description": "...",
  "fix_hint": "..."
}
```

### Validation step (run before any edits)

1. Locate the JSON Findings block in the upstream output (a single fenced
   code block tagged `json` after the human-readable report).
2. Parse it; reject input that is not a JSON array of objects.
3. For each entry, verify against
   [references/finding.schema.json](references/finding.schema.json):
   - `finding_id`, `severity`, `category`, `file`, `description` are
     required; reject the whole batch if any entry omits them.
   - `severity` must be one of `Critical | High | Medium | Low`.
   - `finding_id` must match `^(SPEC|AUDIT|SEC|ROB|CR)-[0-9]+$`.
   - `file` must match `^[^:]+:[0-9]+$`.
   - `spec_ref` must match `^.+\.md:[0-9]+$` when present.
4. On schema mismatch, emit a Tier 1 escalation describing which entries
   failed and which fields were invalid. Do not silently filter — the
   upstream reviewer is broken or the JSON block was hand-edited.

---

## Mode A: Conformance

Drive `spec-audit --mode=conformance` findings (Missing / Diverged /
Extra / Constraint). Apply the fix-direction heuristic, dispatch
per-finding actions, and (with `--loop`) iterate until convergence.

For the direction tables, per-finding action table, and loop pseudocode,
see [references/mode-conformance.md](references/mode-conformance.md).

Force flags:
- `--spec-wins` — every patch goes to the implementation side.
- `--impl-wins` — every patch goes to the spec side.

---

## Mode B: Robust

Drive `robust-review` findings (SEC-* / ROB-*). Critical and High items
are auto-fixed via the pattern table; Medium and Low items are reported
only.

For the severity gate, the pattern table, and the unknown-pattern
fallback, see [references/mode-robust.md](references/mode-robust.md).

---

## Mode C: Adhoc

Drive a free-form bug description or `file:line` with no upstream
finding. Four steps: baseline → impact analysis → apply + verify →
regression test.

For the per-language baseline commands and the regression-test boundary
checklist, see [references/mode-adhoc.md](references/mode-adhoc.md).

---

## Common verification gate (all modes)

After each individual edit, run in order. Stop on the first failure.

| Gate  | Detection                          | Command                                                  |
|-------|------------------------------------|----------------------------------------------------------|
| Build | Cargo.toml / package.json / go.mod | `cargo check` / `npm run build` / `go build ./...`       |
| Type  | same                               | `cargo clippy` / `npx tsc --noEmit` / `go vet`           |
| Test  | same                               | `cargo test` / `npm test` / `go test ./...`              |

When CLAUDE.md `## Commands` exists, those commands take precedence.

---

## Common revert policy (all modes)

1. **One finding / one file at a time.** No batched edits — the gate
   must attribute failures to a specific patch.
2. Run the gate after each edit.
3. Failure attribution:
   - **Failure caused by this patch** → revert via
     `git checkout HEAD -- <file>` and skip with a report entry.
   - **Pre-existing failure** (unrelated to the patch) → keep the patch,
     report the pre-existing error separately.
4. **Three consecutive failures on the same finding** → skip and surface
   as Tier 1 escalation. Continued blind retries indicate the approach
   itself is wrong.
5. A hardening fix that breaks an unrelated test is worse than the
   original Critical — better to mark "needs human review" than leave
   the tree red.

---

## Output format

The final report block (Fixed / Skipped / Report-only sections,
verification line, mode header) is templated in
[references/output-format.md](references/output-format.md).

---

## Pipeline integration

- **From `impl-orchestrator` Stage 3** — findings stream from
  `spec-audit --mode=conformance` and `robust-review` with severity
  tags. safe-fix auto-dispatches Mode A for SPEC-* / AUDIT-* and Mode B
  for SEC-* / ROB-*. Verification results flow back into `gate_results`.
  Skipped findings hand off to escalation classification.
- **Standalone after `spec-audit --mode=conformance`** — Mode A;
  recommend `--loop` when iteration is acceptable.
- **Standalone after `robust-review`** — Mode B; default Critical + High
  auto-fix.
- **Standalone bug fix** — Mode C; baseline → impact analysis → fix →
  verify → regression test.
