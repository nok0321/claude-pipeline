# Final report template

Detail for SKILL.md Stage 4 — the report emitted when iteration finishes
(either `open_findings == 0` or the iteration cap is hit).

```
╔══════════════════════════════════════════════════╗
║  Implementation orchestrator report               ║
║  Target: <component>                              ║
║  Iteration: <iteration> / 3                       ║
╚══════════════════════════════════════════════════╝

■ Verification gate
  Build:    <pass/fail>
  Type:     <pass/fail>
  Test:     <pass/fail> (<passed> passed, <failed> failed)
  Boundary: <pass/fail/skipped>

■ Review summary
  Security:    Critical: <n> / High: <n> / Medium: <n> / Low: <n>
  Robustness:  Critical: <n> / High: <n> / Medium: <n> / Low: <n>
  Spec:        Missing: <n> / Diverged: <n> / Extra: <n> / Constraint: <n>

■ Resolution
  Auto-fixed:  <n> (Tier 2 + Tier 3 via safe-fix)
  Escalated:   <n> (Tier 1, see below)

═══ Auto-fix log (Tier 2: post-report) ═══

[1] SEC-1 | Critical | <handler>:<line>
  Change: format!() → .bind() (SQL injection)
  Verification: test suite pass

[2] ROB-3 | High | <file>:<line>
  Change: unwrap() → ?
  Verification: test suite pass

═══ Escalation (Tier 1: user decision needed) ═══

[E-1] SPEC-2 | Missing | undocumented API needed
  Issue: <details>
  Question: <concrete question>

═══ Open findings (unresolved) ═══

(only when iteration cap was hit)

═══ Next actions ═══
  - Answer escalation items
  - Manual confirmation: <browser test, etc.>
```
