---
name: skill-authoring
description: Use this skill whenever the user wants to create, modify, or harden a skill **inside this claude-pipeline repository** so that it conforms to the repo's house style and is wired into the architecture docs and eval suite. It wraps the general `skill-creator` with claude-pipeline conventions — English body / Japanese meta docs, layer placement, model-pin policy, trigger-description quality, diagram policy, and registration in ARCHITECTURE.md and the eval queue. Trigger phrases include "add a new skill to the pipeline", "create a skill for X and register it", "scaffold a claude-pipeline skill", "make this skill follow our house style", "author a new skill the right way here", or any skill-creation/editing request in this repo. Trigger even when the user does not say "skill-authoring" — "we should turn this into a skill" or "new skill for the repo" qualify. For pure description optimization or eval mechanics with no house-style/registration concern, defer to `skill-creator`.
argument-hint: "[new <name> | harden <name>]"
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, Agent
model: claude-opus-4-8
---

# Skill authoring (claude-pipeline house style)

Create or harden a skill so it is indistinguishable from the existing
seven and is registered everywhere the repo expects. The general scaffolding
is delegated to `skill-creator`; this skill owns the **house-style gate** and
the **registration**, which `skill-creator` does not do.

The full convention reference is
[references/house-style.md](references/house-style.md). This body is the
process; that file is the law.

---

## Commands

```
/skill-authoring new <name>       # scaffold a new skill, apply house style, register
/skill-authoring harden <name>    # bring an existing skill up to house style
```

---

## Flow

Linear with one optional delegation — kept as text, not a diagram, per the
diagram policy (a straight sequence does not earn a flowchart;
[references/house-style.md](references/house-style.md) §Diagrams).

```
Step 1 Scope ─→ Step 2 Scaffold (skill-creator) ─→ Step 3 House-style gate
       ─→ Step 4 Register ─→ Step 5 Eval queue ─→ Step 6 Verify symlink
```

---

## Step 1: Scope

Decide, with the user when ambiguous:

- **Layer** (1 orchestrator / 2 inspection / 3 utility / 4 judgment subagent).
  Placement rules: [references/house-style.md](references/house-style.md) §Layers.
- **Responsibility** — must not overlap an existing skill. Check the
  ARCHITECTURE.md §10 responsibility matrix first; an overlap is a redesign
  question, not a new skill.

## Step 2: Scaffold

Delegate the raw scaffold to `skill-creator` via an Agent call (skills
cannot invoke skills directly — ARCHITECTURE.md §3.1). Bring back the draft
`SKILL.md` for the house-style gate. For `harden`, skip scaffolding and read
the existing skill.

## Step 3: House-style gate

Apply every item in [references/house-style.md](references/house-style.md).
The non-negotiables:

- **Language**: `SKILL.md` and `references/*.md` that are *instructions* →
  English. Meta docs (plans, ARCHITECTURE notes) → Japanese.
- **Frontmatter**: `description` carries explicit + implicit + casual
  triggers and a "trigger even when the user does not say …" clause and a
  delimiter against the nearest sibling skill; `allowed-tools` minimal;
  `model` per the pin policy (judgment → pinned dated id; implementer →
  bare `sonnet`; utility → inherit).
- **Body size**: keep the body lean; push tables, prompts, and recipes to
  `references/`.
- **Diagrams**: branching/looping flow → Mermaid; linear → text. Never
  duplicate executable logic between a diagram and prose.

## Step 4: Register

A skill that is not registered does not exist. Update, in the same change:

1. ARCHITECTURE.md §2 layer list (place under the right layer).
2. ARCHITECTURE.md §10 responsibility matrix (one row: やりたいこと / skill / 補足).
3. README.md 構成 tree and エントリーポイント.
4. The skill count in any "N skill" headline (README, ARCHITECTURE §2/§10/§11).

## Step 5: Eval queue

Create `evals/queries/<name>.json` — ~20 entries: triggerable
(`explicit` / `implicit` / `casual`) and non-triggerable
(`near-miss-<sibling>` / `generic`), matching the existing files' schema.
**Do not run evals now** — measuring while editing contaminates results
(README; [references/house-style.md](references/house-style.md) §Eval).

## Step 6: Verify symlink truth-source

The repo is the only source of truth — never copy files into `~/.claude/`.
`~/.claude/skills` is a real directory holding a **per-skill junction**, so a
new skill needs its **own junction created** — it is NOT auto-picked-up
(without it `/<name>` is "Unknown command"):

`New-Item -ItemType Junction -Path "$HOME\.claude\skills\<name>" -Target "<repo>\skills\<name>"` (no admin needed)

Agents differ — `~/.claude/agents` is a single directory junction, so a new
agent file appears automatically. After creating the junction, confirm the
skill shows up in the skill list.

---

## Constraints

- Overlapping responsibility with an existing skill → stop and raise it as a
  design question (ARCHITECTURE.md §10), do not add a near-duplicate.
- `skill-creator` does scaffolding/optimization; this skill adds house style
  and registration. Do not reimplement `skill-creator` here (anti-pattern:
  logic embedding, ARCHITECTURE.md §3.3).
- Autonomous skill *proposal* (noticing a repeated manual pattern and
  suggesting a skill) is an event-firing concern — see the WS4 trigger, not
  this skill.
