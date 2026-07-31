---
name: recap
description: Render a visual recap of the current branch's diff as a local HTML page — what changed, a composes/extends/adds risk rollup, a system map, and drift against the blueprint when one exists.
disable-model-invocation: true
---

# Recap

Produce a post-implementation counterpart to the blueprint: a scannable, diff-derived summary of what the branch actually does to the system. The source of truth is a markdown file with typed fences; `blueprint-html` renders it and `live-html` previews it — the tokens go into content, the rendering is free.

The recap is informational. It supplements review; it never replaces reading the diff.

## 1. Check the tier

Trivial branches (copy tweaks, version bumps, one-file fixes with an obvious diff) don't need a recap — say so and stop unless the user insists. Everything else gets one.

This step is complete when the call (recap or skip) is stated and the user hasn't objected.

## 2. Read the diff

The diff is the source of truth, not session memory. Base is the PR base when a PR exists (`gh pr view --json baseRefName`), otherwise the merge-base with `main`. Read `git diff <base>...HEAD --stat` and the full diff for anything not authored this session. Session context may explain *why*; every claim about *what* changed must be checkable against the diff.

This step is complete when every area the recap will name has been seen in the diff.

## 3. Classify

Judge each touched area against the actual code — same discipline as blueprint anchors, no architecture map to consult:

| Classification | Meaning                                                    | Risk   |
| -------------- | ---------------------------------------------------------- | ------ |
| `composes`     | Wires existing code as-is; call sites and config only      | Low    |
| `extends`      | Changes an existing module's behavior, shape, or contract  | Medium |
| `adds`         | Introduces a new module, subsystem, or dependency          | High   |

The overall classification is the highest severity touched (`adds` > `extends` > `composes`).

## 4. Author the source

Write `lab/<name>.recap.md` — like blueprints, a working document in `lab/` scratch space, out of version control unless explicitly asked. Frontmatter carries the rollup:

```markdown
---
title: <what the branch does, as a noun phrase>
tier: extends · medium risk
description: <one sentence — the classification statement>
---
```

Fixed section order; omit optional sections rather than leaving them empty:

- **Touched** — table of area → impact (`extends — new `--check` flag`), one row per area from step 3.
- **System map** *(optional)* — a `mermaid` flowchart, only when the topology genuinely helps: touched areas plus immediate neighbors, never an exhaustive graph. Color nodes with `classDef touched fill:#1a7f37,color:#fff`, `extended fill:#9a6700,color:#fff`, `added fill:#cf222e,color:#fff`, `untouched fill:#57606a,color:#fff`.
- **Before / after** *(optional)* — contract, schema, or CLI-surface changes using the blueprint typed fences (`contract`, `signatures`, `filetree`) with `-`/`+` diff lines.
- **Plan vs actual** — only when a blueprint for this work exists in `lab/`: what shipped as planned and what drifted, as a short list with one-line reasons. When drift is recorded here, also update the blueprint source in place (per the blueprint skill) so it stays the record of what was actually built.

Scannable: tables, trees, and diagrams over prose; whole document well under ~80 lines.

This step is complete when every claim in the source traces to the diff.

## 5. Render and preview

Run `blueprint-html lab/<name>.recap.md` — it writes `lab/<name>.recap.html` and prints the path. Fix any warnings, then offer a preview via `live-html`. Re-run steps 2–5 after significant new commits — refine and replace in place, never accumulate.

This step is complete when the renderer runs warning-free and the page matches the current head.
