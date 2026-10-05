---
name: moto-catchup
disable-model-invocation: true
description: Recap what happened since Jonas's last message, then clear open decisions one at a time
---

Catch Jonas up on this session, then help him clear the decisions waiting on him.

1. Find Jonas's last real message before this `/moto-catchup`. Worker reports, watch output, hook output and system notifications are not his messages. If there is none, because the session just started or was cleared, run `/moto-brief` instead and stop here.
2. Recap what happened after that message, using the conversation and `moto log`: what finished, what merged, what failed, what you decided, and what's still running. Give every PR as a full URL. If nothing happened, say so in one sentence.
3. List every decision still open with Jonas across the whole session, including ones raised before his last message. A decision counts as closed only when he answered it, chose, declined, or addressed it directly. A later unrelated message doesn't close it. If compaction hid part of the session, say what you can't see rather than guessing.
4. If decisions are open, present only the one with the most impact, and say the order is your pick. Give the decision, why it matters, the options, and your recommendation. After he answers, act on it, then present the next one. Continue until none remain.
