# Mode B: Robust (`robust-review` findings)

Detail for SKILL.md Mode B. Replaces the retired `robust-fix` skill.

Findings stream in from `/robust-review` as `SEC-*` (security) or
`ROB-*` (robustness) entries with severity tags.

---

## Severity gate

| Severity   | Action                       |
|------------|------------------------------|
| Critical   | **Always fix**               |
| High       | **Always fix**               |
| Medium     | Skip (report only)           |
| Low        | Skip (report only)           |

Medium / Low items appear in the final report under "Report only" but
are not patched. Promote to Critical / High in CLAUDE.md
`## Escalation Overrides` if the project wants them auto-fixed.

---

## Pattern table

| Finding category               | Pattern                                | Fix                                          |
|--------------------------------|----------------------------------------|----------------------------------------------|
| SQL injection                  | `format!()` / template literal in query| `.bind()` / parameterized query              |
| XSS                            | unsanitized output                     | apply sanitizer                              |
| `unwrap()` / `expect()`        | panic source                           | `?` / `match` / `.unwrap_or()`               |
| Unchecked index                | `arr[i]`                               | `.get(i)` / explicit bound check             |
| Division by zero               | `a / b`                                | guard the denominator + error path           |
| `todo!()` / `unimplemented!()` | unimplemented marker                   | implement per design or return an error      |
| Hard-coded secret              | literal value                          | env var / config reference                   |
| `as` cast                      | implicit truncation                    | `try_into()` / `checked_*`                   |

---

## Unknown patterns (not in the table above)

For Critical / High items that don't match a known pattern:

1. Attempt the fix.
2. **Skip and report when confidence is low** rather than emit unsafe
   edits.
3. When a fix would require a design decision, surface it as a Tier 1
   escalation candidate (see ARCHITECTURE.md §A).

The bias toward skipping is intentional: a hardening fix that breaks
unrelated tests is worse than the original Critical — better to leave a
"needs human review" entry than to ship a regression. (See SKILL.md
"Common revert policy" for the matching three-strikes rule.)
