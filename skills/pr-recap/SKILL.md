---
name: pr-recap
description: Render a review-ordered recap of a PR as a local HTML page — the lede first, then a risk-ranked review path with file:line anchors. Works on any PR, whether or not this agent wrote it.
disable-model-invocation: true
---

# PR Recap

Produce a review guide for a pull request, whether or not this session wrote it. The diff is the sole source of truth — session memory may explain *why*, but every claim about *what* changed must be checkable against the diff. The source is a markdown file with typed fences; `blueprint-html` renders it and `live-html` previews it.

The recap is judged by one test: a reader who skims only headings and tables still walks away knowing the lede. (For a flat inventory of work this session built, with plan-vs-actual against a blueprint, use `recap` instead.)

## 1. Read the diff

Resolve the PR: an explicit number or URL wins; otherwise the current branch's PR (`gh pr view --json number,title,baseRefName`). Read `git diff <base>...HEAD --stat`, then the full diff — including any parts authored this session; memory of writing code is not the same as reading its diff. For large diffs, fan out subagents per area and keep the main context lean. If the diff is trivial (one file, obvious change), say so and offer an inline summary instead.

This step is complete when every file in the stat has been seen in the diff, by you or a subagent.

## 2. Find the lede

Classify each touched area: `composes` — wires existing code as-is, low risk; `extends` — changes an existing module's behavior or contract, medium; `adds` — new module, subsystem, or dependency, high. Then pick the lede: the one change with the largest blast radius if it's wrong. A migration with triggers outranks the feature it enables; a contract change outranks its call sites.

This step is complete when the lede is stated to the user in one sentence, with its anchor.

## 3. Author the source

Write `lab/<name>.review.md` — a working document in `lab/` scratch space, out of version control unless explicitly asked. Frontmatter: `title` (noun phrase), `tier` (highest classification · risk), `description` (the lede in one sentence).

Fixed section order — the lede is visually unavoidable and everything else is downstream of it; omit optional sections rather than leaving them empty:

- **Lede** — a callout: what it is, its anchor (`file:line` range), and why it is the review's center of gravity.
- **Invariant** — a `contract` fence stating what the lede enforces or changes: the conditions that must hold, and what happens when they don't. A reviewer's "but what if…" questions should be answerable from this block.
- **Review path** — one table, priority-ordered, one row per area: priority · classification — impact · anchor. A cell holds one clause; the anchor carries the detail. Every row cites the `file:line` where review of that area should start.
- **System map** *(optional)* — a `mermaid` flowchart of the lede's mechanism, not the repo topology. Palette: `classDef added fill:#1c5cab,color:#fff`, `extended fill:#ad4600,color:#fff`, `touched fill:#45443e,color:#fff`, `untouched fill:#e4e2da,color:#3a3a36` (blue/orange/graphite, no green; colorblind-safe on both themes).
- **Proof** *(optional)* — where the tests for the lede live, and the one gap a reviewer should probe.

Whole document well under ~80 lines. After significant new commits, refine and replace in place.

This step is complete when every claim traces to the diff and every review-path row carries an anchor.

## 4. Render and preview

Run `blueprint-html lab/<name>.review.md` — it writes the `.html` next to it and prints the path. Fix any warnings, then offer a preview via `live-html`.

This step is complete when the renderer runs warning-free and the page matches the current head.
