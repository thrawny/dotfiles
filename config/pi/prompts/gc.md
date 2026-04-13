
---
description: Create a git commit; default to agent-made changes, or use `all` to commit everything
---

Create one git commit.

Arguments:
- Default behavior: commit only the changes related to the work you have been doing in this session
- If `$1` is `all`, commit all current changes in the repository
- Otherwise, treat `$@` as additional instructions that further constrain what should be committed, for example: `/gc only file x`

Requirements:
- Decide what information you need before committing
- Stage only the changes that match the selected mode and any additional instructions
- Write a clear commit message based on the changes being committed
- Use only the tools needed to complete the commit
- Keep the response minimal
