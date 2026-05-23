# Output format

Detail for SKILL.md "Output format". Rendered after the two-axis sweep
finishes.

```
╔══════════════════════════════════════╗
║  Robustness review                   ║
║  Target: <target>                    ║
╚══════════════════════════════════════╝

■ Summary
  Critical: <n>
  High:     <n>
  Medium:   <n>
  Low:      <n>

═══ Axis 1: Security ═══

[SEC-1] Critical | Injection
  File: <file:line>
  Issue: <description>
  Attack: <attack scenario>
  Fix: <concrete patch>

═══ Axis 2: Robustness ═══

[ROB-1] Critical | Panic source
  File: <file:line>
  Issue: <description>
  Impact: <failure scenario>
  Fix: <concrete patch>

═══ Project-specific constraints ═══

[PRJ-1] High | <constraint name>
  File: <file:line>
  Issue: <description>
  Rule: <CLAUDE.md reference>
  Fix: <concrete patch>
```

When no findings exist, report "all checks clean".

### Output rules

- Severity values must use the four-level scale (Critical / High /
  Medium / Low) — no other vocabulary, per Phase 1 Action A3.
- `Attack:` is required for Critical and High security findings; omit
  it for Medium / Low security findings.
- `Impact:` is required for Critical and High robustness findings.
- `Fix:` is always required and must be concrete enough that the
  orchestrator's inline robust remediation can act on it without further
  interpretation.

### Schema-compliant JSON emission

After the human-readable report, emit a single fenced code block tagged
`json` containing every finding as an array conforming to
[../../impl-orchestrator/references/finding.schema.json](../../impl-orchestrator/references/finding.schema.json).
Security findings use `finding_id` prefix `SEC-` and populate `attack`
(Critical / High only). Robustness findings use prefix `ROB-` and
populate `impact` (Critical / High only). Project-specific findings
emitted with prefix `SEC-` or `ROB-` per their nearest axis. This block
is the input contract for impl-orchestrator's inline robust remediation
(see [robust-fix.md](../../impl-orchestrator/references/robust-fix.md)).
