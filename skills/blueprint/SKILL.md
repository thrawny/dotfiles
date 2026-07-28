---
name: blueprint
description: Generate a pre-implementation design artifact as shareable HTML — system architecture, program design (call-stack diff trees, file-tree diffs, type signatures), and a vertical-slice plan.
disable-model-invocation: true
---

# Blueprint

Produce a design artifact the user can review before implementation starts. Every item in it is a decision that would otherwise be made implicitly during code review — the most expensive time to change your mind. The artifact is a draft-and-argue object: the model drafts, the user argues, the artifact converges.

The source of truth is a markdown file with typed fences; the HTML is a derived view produced by `blueprint-html`. Edit the source, re-render — the tokens go into design content, the rendering is free.

## 1. Check the tier

Not every change deserves a blueprint. Estimate the tier and say it out loud:

- **Oneshot** (copy tweaks, one-off scripts, bugs with an obvious repro): recommend skipping the blueprint entirely and offer to just do the work.
- **Medium** (one subsystem, contained blast radius): a single combined document, no phasing.
- **Large** (new feature crossing layers, orchestration changes, migrations): all sections including vertical slices. Skip the product/scope framing for pure refactors.

Roughly 80% of the value arrives in the first minutes of design; size the effort to the tier.

The user may also request a section subset — "program design only" is the common one: TL;DR, the program-design fences, and Decisions, nothing else. The filetree then doubles as the scope boundary: files not listed are not touched. Anchor research (step 2) runs at full strength regardless of subset.

This step is complete when the tier (and any requested subset) is stated and the user hasn't objected.

## 2. Research the anchors

Read the real code before asserting anything about it. Classify every symbol, file, and endpoint the design will name:

- **Anchor** — exists today. Confirm it in the codebase and cite it as `file:line`.
- **Delta on an anchor** — the `-` side of a change. The current signature/path must match reality exactly; only the `+` side is a proposal.
- **Net-new** — legitimately unverifiable; mark it as new.

The failure mode of a pre-code artifact is fiction: plausible names for things that don't exist, reading as a confident review of a hallucination. Anchors are the defense. Use subagents for broad discovery so the main context stays lean.

This step is complete when every existing symbol the design touches has been confirmed against the codebase.

## 3. Draft the source

Read [ARTIFACT-FORMAT.md](ARTIFACT-FORMAT.md) and write the source file — `lab/<name>.blueprint.md` by default. Blueprints are working documents, not repo documentation: they live in `lab/` scratch space and stay out of version control unless the user explicitly asks to commit one. Draft each section the tier calls for. Hard rules, in tension order:

- **Abstract up.** Signatures and shapes; if you are writing code that could be pasted into the repo, stop and rise a level. Code blocks are reserved for schemas, type definitions, contracts, and genuinely complex algorithms — everything else is a reference like "follow the pattern in `src/api/users.ts:45`".
- **Survive decision changes.** If swapping a library or renaming a service would invalidate half the document, it contains implementation, not design.
- **Stay readable.** The comparison point is a 200-line plan read in place of 2000 lines of diff. Prefer diff-highlighted trees and short blocks over prose walls.
- **No open questions in the final artifact.** When you hit a decision you cannot resolve from the code or the request, stop and put it to the user before finalizing. The finished document records decisions, not options.

This step is complete when every section is drafted and every decision in it is resolved.

## 4. Render

Run `blueprint-html <source>` — it writes `lab/<name>.html` and prints the path. Fix any warnings it emits, then offer the user a preview via `live-html`. Publishing beyond the local file happens only on explicit request (`share-html`).

This step is complete when the renderer runs warning-free.

## 5. Argue and iterate

Present the artifact and invite disagreement section by section. Revisions go into the source file, then re-render — refine and replace, never accumulate: adding detail in one place means trimming elsewhere, and the document shrinks back under budget rather than growing.

After approval, implementation proceeds 1–3 vertical slices at a time with review between slices. Update the source in place as slices land so it stays the record of what was actually built, not a stale promise.
