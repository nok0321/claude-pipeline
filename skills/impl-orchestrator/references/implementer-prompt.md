# Implementer sub-agent prompt (Stage 2-1)

Code generation runs on a sonnet sub-agent. Implementation is
high-volume; judgment is captured downstream by the opus reviewers
(Stage 3) and the verification gate (Stage 2-3).

```
Agent(
  description: "<component> implementation",
  model: "sonnet",
  prompt: "
    You are the implementer. Build the code that satisfies the spec below.

    ## Spec
    <DESIGN/*.md content>

    ## Project constraints
    <CLAUDE.md Critical Constraints>

    ## Implementation directory
    <Component Mapping path>

    ## Rules
    - Anchor implementation on the spec's code snippets
    - Honor every NEVER rule from CLAUDE.md
    - Match existing-code patterns
    - Add tests per the spec's test requirements
    - Report back the list of files implemented
  "
)
```

The agent's reported file list feeds into `impl_files`, which becomes
`{target_files}` for the Stage 3 reviewers
(see [review-prompts.md](review-prompts.md)).
