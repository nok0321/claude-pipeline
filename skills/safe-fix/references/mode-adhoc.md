# Mode C: Adhoc (free-form bug fix)

Detail for SKILL.md Mode C. Replaces the retired `fix-with-verify` skill.

Triggered when the user supplies a free-form bug description or a
`file:line` reference and there is no upstream `spec-audit` /
`robust-review` finding feeding the run.

---

## Step 1: Record baseline

1. `git diff` to capture pending state.
2. Run the test suite (auto-detect language) to record a baseline:

| Language | Command                                         |
|----------|-------------------------------------------------|
| Rust     | `cargo test -p <crate> 2>&1 \| tail -20`        |
| Python   | `pytest <test file> 2>&1 \| tail -20`           |
| Go       | `go test ./<package>/... 2>&1 \| tail -20`      |
| Node     | `npm test 2>&1 \| tail -20`                     |

3. If tests already fail, confirm whether those failures are exactly
   the target. (Pre-existing failures unrelated to the bug must not be
   conflated with the fix's regression set.)

---

## Step 2: Impact analysis

1. Grep for call sites of the function / type under repair.
2. Treat public-API signature changes as broad-impact — surface every
   call site before editing rather than discovering them during the
   verify gate.

---

## Step 3: Apply + verify

Apply the patch one finding / one file at a time, then run the common
verification gate (see SKILL.md "Common verification gate"). On failure,
follow the common revert policy in SKILL.md.

---

## Step 4: Add regression test

When the existing suite did not cover the original bug, add a
reproducer test plus boundary cases — `0`, empty, max, `null` / `None`
/ `nil` — before declaring the run done. A fix without a regression test
will silently come back.
