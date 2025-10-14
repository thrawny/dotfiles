## Your task

Research the codebase to answer a user's question and produce a self‑contained research document. Read any referenced files fully, search the codebase, and synthesize concrete, referenced findings.

**Parameters**:
- `$ARGUMENTS` - The research question or area of interest (if not provided, ask for it)

1. Inputs
   - If `$ARGUMENTS` is provided, use it as the research question.
   - Otherwise, ask for the research question or area of interest.
   - If files are mentioned, read them completely before proceeding.

2. Decompose the question
   - Identify components, patterns, and code paths likely involved.
   - Make a short internal checklist of areas to examine.

3. Investigate directly
   - Use targeted searches (e.g., ripgrep) to find relevant files, definitions, and usages.
   - Open and read the most relevant files fully to understand behavior.
   - Prefer live code over stale docs; use `docs/` as supplementary history if present.

4. Synthesize findings
   - Connect evidence across modules and layers.
   - Include concrete file paths and line numbers for each key point.
   - Keep local file references (no GitHub permalinks required).

5. Write the research doc
   - Path: `docs/research/YYYY-MM-DD_HH-MM-SS_topic.md` (use a descriptive topic slug).
   - Use the template below; fill all metadata fields with real values.

```markdown
---
date: [ISO8601 with timezone]
researcher: [Your name/handle]
git_commit: [Current commit hash]
branch: [Current branch]
repository: [Repo name]
topic: "[User's Question/Topic]"
tags: [research, codebase, relevant-component-names]
status: complete
last_updated: [YYYY-MM-DD]
last_updated_by: [Your name/handle]
---

# Research: [User's Question/Topic]

**Date**: [ISO8601]
**Researcher**: [Name]
**Git Commit**: [Hash]
**Branch**: [Branch]
**Repository**: [Name]

## Research Question
[Original user query]

## Summary
[High-level findings answering the question]

## Detailed Findings
### [Component/Area 1]
- Finding with reference: `path/to/file.ext:123-140` — [what it does]
- Connections to other components

### [Component/Area 2]
- ...

## Code References
- `path/to/file.py:123` — [description]
- `another/file.ts:45-67` — [description]

## Architecture Insights
[Patterns, conventions, and design decisions discovered]

## Historical Context (optional)
[Relevant insights from docs/ or external KB if configured]

## Related Research
[Links to other docs in docs/research/]

## Open Questions
[Any areas that need further investigation]
```

6. Present and iterate
   - Share a concise summary and the created file path.
   - Append follow‑ups to the same document; update frontmatter `last_updated`, `last_updated_by`, and add a “Follow‑up Research [timestamp]” section.

Notes
- Always read mentioned files fully before searching more broadly.
- Keep references local to the repository paths.
