---
description: Run claude-code-review-zmx and fix major review findings
---

Run `claude-code-review-zmx`; do not call `zmx` directly.

Default when no user instructions: review the current branch's changes and fix major issues/P1s. Pass the scope explicitly — with no instructions the script defaults to just the previous commit (HEAD~1..HEAD).

Example:
```bash
claude-code-review-zmx --session my-session 'review HEAD~1..HEAD'
```

The script runs `/code-review` in an interactive Claude session, has Claude write its findings to a temp JSON file, then reads that file and prints a JSON array of findings (each: `{file, line, severity, title, detail}`). Treat that array as the review result. It exits 0 on success; on failure (no valid result file) it exits non-zero and prints a fallback transcript instead of JSON. Fix only clear major findings unless the user asks otherwise.
