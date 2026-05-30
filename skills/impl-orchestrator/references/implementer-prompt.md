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

The bare `sonnet` alias (not a pinned date like the opus roles) is
**deliberate**: the implementer is cost-optimized and high-volume, and its
output is backstopped by the Stage 2 gate + Stage 3 opus review — so
auto-tracking the latest cost-effective Sonnet is preferred over pinning for
reproducibility here. (Pin where output quality can't be mechanically
verified; float where it can — see ARCHITECTURE.md §4.)

The agent's reported file list feeds into `impl_files`, which becomes
`{target_files}` for the Stage 3 reviewers
(see [review-prompts.md](review-prompts.md)).
