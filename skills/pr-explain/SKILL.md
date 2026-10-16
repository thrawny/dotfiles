---
name: pr-explain
description: Explain a pull request to its reviewer before the review, as a page with the PR's reading order, views of the changed code at file:line, and how it fits its design docs. Use when asked to explain, walk through or prepare a reviewer for a PR, or when a review brief names pr-explain.
---

# PR explain

Write an explainer that lets a reviewer understand a pull request before they review it. The explainer **explains and never reviews**: it has no findings and no risk ranking, and it ends with questions that tell the review where to look hardest. The caller runs the review afterwards.

Inputs, from the caller:

- **The PR**: a number, URL or branch. Run from a checkout of the PR's repository.
- **The output folder.** Write `explainer.md` and `explainer.html` there. With none given, create one with `mktemp -d` and print its path.

## 1. Read the PR and size it

```bash
gh pr view <pr> --json number,title,url,body,baseRefName,headRefOid,additions,deletions,changedFiles,files,commits,reviews,comments
gh pr diff <pr>
git fetch origin <baseRefName> "pull/<number>/head"   # base and head commits, for reading files at either side
```

Pick the tier from the size and say it:

- **Trivial**: a one-line fix, a typo, a version bump. Explain it in two sentences in the terminal, tell the caller no page was written, and stop.
- **Medium**: one area of the code. One part per view in the reading order.
- **Large**: several areas. One part per theme, ordered by importance so the reader can stop early. Above about 2,000 changed lines, explain at theme level and say so. Leave lockfiles and generated code out of the reading order, and say you did.

This step is complete when the tier is stated.

## 2. Read the context

Read each source and record what it gave, for the TL;DR's "What the explainer read" list:

- **Stated intent.** The PR body and the commit messages.
- **The ticket the PR links**, from its title, branch or body. When the ticket is an epic or parent that does not describe this PR, say so and take intent from the design docs.
- **Design docs the PR changes** (ADRs, design or technical docs) are the statement of intent. Design docs nearby that the PR leaves unchanged are **background**: label them as background wherever you cite them.
- **Existing review comments and reviews** on the PR, with the commit each review was made at and the commits pushed since.
- **The code.** Every hunk, the whole function or type around it, its callers, and the tests that cover it.

This step is complete when every source above is read or recorded as absent.

## 3. Check the anchors

Every `file:line` or `file:start-end` you write is an **anchor**. Write it as a path from the repository root, and check it before writing it:

- `+` and unchanged lines against the head commit: `git show <headRefOid>:<path> | sed -n '<line>p'`.
- `-` lines against the base: `git show $(git merge-base origin/<baseRefName> <headRefOid>):<path>`.

The renderer links each anchor to the head commit, so a wrong line sends the reviewer to the wrong code. This step is complete when every anchor in the draft matches its line.

## 4. Write the explainer

Run the `unslop` skill first, then write `explainer.md`. Define each term the first time it appears.

Format: the frontmatter and typed fences of blueprint's [ARTIFACT-FORMAT.md](../blueprint/ARTIFACT-FORMAT.md). Its sections, vertical slices and "no open questions" rule belong to blueprints; this explainer uses the sections below. Frontmatter `title` is `<repo> #<number>: <short subject>`, `tier` is the tier from step 1, and `description` says in one sentence what the PR does and the short head commit it was explained at.

Pick the views that explain this PR, and leave out any that do not apply:

| What changed | Fence |
|---|---|
| A call tree or control flow | `callstack` |
| Which files changed, and what each one is for | `filetree` |
| An endpoint contract, or the rules a schema enforces | `contract` |
| Key types and functions | `signatures` |
| A data model | `d2` with `sql_table` |
| A sequence or data flow between services | `d2` with `shape: sequence_diagram` |

Prefer the diff markers (`+`, `-`, `~`) for a change to an existing shape. Show the whole target shape when most of it is new.

### Sections

1. `## TL;DR`
   - A link line: PR link, title, short head commit, base branch, `+N −M in K files`.
   - One bold sentence on whether production behaviour changes, with the evidence for it.
   - Why the change, in one sentence.
   - Special things to note: 1 to 3 bullets (migrations, compatibility, deliberate omissions, surprising decisions), or "None."
   - What the explainer read: intent (docs this PR changes), ticket, background (docs it leaves unchanged), and what is already on the PR.
2. `## The idea`: the problem and the approach in plain words, before any code. Add a `d2` diagram when the data model or flow carries the change.
3. `## Reading order`: one `###` part per view or theme, numbered. Start with the piece the rest of the PR exists to support. Each part has its view with anchors, then one or two plain sentences on why that piece exists. State the rules the code enforces in plain words.
4. `## Design fit`: how the PR matches its design docs, then how it drifts from them, and the same against background docs. With no design doc, write "No design doc found."
5. `## Where to look hardest`: numbered questions for the review, each tied to an anchor. Open the section with "Questions for the review, not findings." Include changes since the latest existing review.

### Honesty rules

- Keep "the PR says" apart from "this looks like". Attribute every claim about intent to its source.
- Write "None" in a section or list with nothing in it, rather than filling it.
- Every claim about the code survives the reader opening the anchor.
- A suspected bug becomes a question in "Where to look hardest", never a statement.

This step is complete when every section is written and every view is the one that fits.

## 5. Render

```bash
blueprint-html <folder>/explainer.md -o <folder>/explainer.html \
  --link-base https://github.com/<owner>/<repo>/blob/<headRefOid>/
```

Take `<owner>/<repo>` from the PR's URL.

Fix any warning it prints and render again. This step is complete when the renderer runs without warnings.

## 6. Report

In the terminal, give the tier, whether production behaviour changes, the path to `explainer.html`, and one line handing the PR to the caller's review. Leave the questions on the page.

---

Adapted from HumanLayer's [visual-pr](https://github.com/humanlayer/skills/tree/main/plugins/visual-pr) and Chris Graffagnino's [explain-diff](https://github.com/Chris-Graffagnino/explain-diff), both MIT.
