---
description: Run claude-code-review-zmx and fix major review findings
---

Run `claude-code-review-zmx`; do not call `zmx` directly.

Default when no user instructions: review the current branch/PR and fix major issues/P1s.

Example:
```bash
claude-code-review-zmx --session my-session 'review HEAD~1..HEAD'
```

The script asks Claude for marked JSON, then parses markers/fenced JSON/last JSON object or array and prints parsed JSON. Treat that output as the review result; if parsing fails, it prints a fallback transcript. Fix only clear major findings unless the user asks otherwise.
