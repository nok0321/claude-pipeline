---
name: safe-fix
description: Use this skill whenever the user wants to apply a verified fix or refactor — driven either by findings from `spec-audit` (conformance mode) / `robust-review` / `code-review`, OR by a free-form bug description — with a built-in safety net (build / type / test gate after each edit, automatic revert when the change breaks anything green). Trigger phrases include "fix the spec mismatches", "reconcile spec and implementation", "fix the robust-review findings", "auto-fix critical findings", "apply the unwrap fixes", "fix this bug safely", "fix and verify", "patch this without breaking anything", "remediate the security findings", or any pattern-based remediation request. Trigger even when the user does not say "safe-fix" — phrases like "fix what robust-review found", "close the gap between design and code", "make implementation match the spec", or "patch this and run the tests" qualify. For broad multi-component feature work, prefer `impl-orchestrator` instead.
argument-hint: "[finding-source | file:line | issue-description] [--mode=conformance|robust|adhoc] [--spec-wins | --impl-wins | --dry-run | --loop [N]]"
allowed-tools: Read, Write, Edit, MultiEdit, Bash, Grep, Glob
model: claude-opus-4-7
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

Findings flow in as JSON with the fields below (Phase 3 informal version
in [references/finding.schema.json](references/finding.schema.json); a
formal schema lands in Phase 4):

```json
{
  "finding_id": "SPEC-1 | AUDIT-3 | SEC-1 | ROB-3",
  "severity": "Critical | High | Medium | Low",
  "category": "Missing | Diverged | Extra | Constraint | SQL injection | unwrap | ...",
  "file": "path:line",
  "spec_ref": "DESIGN/...:N (conformance only)",
  "description": "...",
  "fix_hint": "..."
}
```

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
