# Stage 3 remediation: Robust / Security findings

Detail for SKILL.md Stage 3-5 dispatch when the finding `finding_id`
starts with `SEC-` or `ROB-` (output of `robust-review`). Inline
replacement of the retired `safe-fix --mode=robust` flow.

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
2. **Skip and report when confidence is low** rather than emit unsafe edits.
3. When a fix would require a design decision, surface it as a Tier 1
   escalation candidate (see ARCHITECTURE.md §A).

The bias toward skipping is intentional: a hardening fix that breaks
unrelated tests is worse than the original Critical — better to leave a
"needs human review" entry than to ship a regression.

---

## Per-edit verification and revert policy

1. **One finding / one file at a time.** No batched edits — the gate
   must attribute failures to a specific patch.
2. Run the Stage 2 verification gate after each edit
   ([gate-commands.md](gate-commands.md)).
3. Failure attribution:
   - **Failure caused by this patch** → revert via
     `git checkout HEAD -- <file>` and skip with a report entry.
   - **Pre-existing failure** (unrelated to the patch) → keep the patch,
     report the pre-existing error separately.
   - When attribution is ambiguous, call the `regression-judge` subagent
     before escalating. See [subagent-calls.md](subagent-calls.md) (Stage 3-6 dispatch) for
     the input/output contract.
4. **Three consecutive failures on the same finding** → skip and surface
   as Tier 1 escalation. Continued blind retries indicate the approach
   itself is wrong.
