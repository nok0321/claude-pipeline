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
- `Fix:` is always required and must be concrete enough that
  `safe-fix --mode=robust` can act on it without further interpretation.
