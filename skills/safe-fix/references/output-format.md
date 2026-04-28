# Output format

Detail for SKILL.md "Output format". The report block is rendered after
the run finishes (or after the loop terminates in Mode A `--loop`).

```
╔══════════════════════════════════════╗
║  safe-fix report                     ║
║  Mode: <conformance | robust | adhoc>║
║  Target: <component | file | issue>  ║
╚══════════════════════════════════════╝

■ Summary
  Fixed:           <n>
  Skipped:         <n> (escalation candidates)
  Report-only:     <n> (Medium / Low — robust mode)
  Verification: build:<result> type:<result> test:<result>

═══ Fixed ═══

[1] SPEC-1 | Missing → impl added (Mode A)
  Spec: DESIGN/<component>.md:<N>
  Added: <path/to/new_file> — pub fn <function_name>()
  Verification: build:pass type:pass test:pass

[2] SEC-1 | Critical | SQL injection (Mode B)
  File: <handler>:<line>
  Change: format!() → .bind()
  Verification: build:pass type:pass test:pass

═══ Skipped (manual follow-up) ═══

[S-1] SPEC-5 | Diverged | direction unclear (Mode A)
  Spec: DESIGN/<component>.md:<N> — POST /<api_path>
  Code: <handler>:<N> — PUT /<api_path>
  Question: which method is canonical, POST or PUT?

[S-2] ROB-5 | High | concurrent write protection (Mode B)
  File: <repository>:<line>
  Reason: requires a transaction-isolation-level decision
  Recommendation: Tier 1 escalation

═══ Report only (Mode B Medium / Low) ═══

[I-1] ROB-8 | Medium | empty list not handled
  File: <file>:<line>
```

### Section expectations

- **Fixed** — every entry that passed the verification gate. The
  `Verification:` line is mandatory.
- **Skipped** — entries that hit the three-strikes revert policy or
  required a design decision. Each entry must include a `Question:` or
  `Recommendation:` so a human can act.
- **Report only** — Mode B Medium / Low items. No fix attempted, but the
  finding is preserved so it can be promoted via CLAUDE.md
  `## Escalation Overrides` later.
