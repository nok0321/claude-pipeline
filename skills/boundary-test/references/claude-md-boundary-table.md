# `## Boundary Definitions` table format

CLAUDE.md may declare project-specific boundaries via a
`## Boundary Definitions` section. When this table exists, the `detect`
step (Step 1-2) treats it as a detection source in addition to the
auto-detected Type A/B/C/D boundaries.

```markdown
## Boundary Definitions
| Name | Source | Consumer | Conversion rule |
|------|--------|----------|-----------------|
| <name_a> | <component_a> [<field1>,<field2>] | <component_b> [<field2>,<field1>] | swap(0,1) |
| <name_b> | <component_a> [<field1>,<field2>] | <component_c> [<field1>,<field2>] | identity |
| <name_c> | <source> (<sourceFormat>) | <consumer> (<consumerFormat>) | <converter> |
```

### Field meanings

- **Name** — short identifier used in test names and the detection report.
- **Source / Consumer** — the two sides of the boundary, each annotated
  with the field ordering or format they expose.
- **Conversion rule** — the canonical conversion from Source → Consumer.
  `identity` means no transformation expected; `swap(0,1)` means the
  first two fields are exchanged; arbitrary expressions are allowed.

### When to declare manually

Use this table when:

- The boundary is not detectable by signature/grep alone (e.g. an
  out-of-band JSON contract).
- Multiple consumers read the same source with different conventions.
- A constraint from `## Critical Constraints` needs to be made executable
  (e.g. coordinate-ordering rules that span more than two components).
