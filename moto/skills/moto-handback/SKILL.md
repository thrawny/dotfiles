---
name: moto-handback
description: Hand a held moto worker back to the driver with a summary of what you and the user settled.
disable-model-invocation: true
---

# Handback

The user runs this to give a session to the driver: a held moto worker they took over (a grill, say), or a session they started by hand. The driver never saw your conversation with the user, so your summary is all it knows of it.

1. **Write the summary.** Draw it from the conversation since the user took over, in a few sentences:
   - the decision you and the user reached;
   - what you do next;
   - the flow, if the user named one: ship (open the PR) or verify (commit on the branch, push nothing, and report how to check the change);
   - anything the user asked the driver to do.

   Leave out a point the conversation gave nothing for. If the decision or your next step is unclear, ask the user first. Done when the driver could act on the summary without reading your pane.

2. **Report.** Run `moto report handback "<summary>"`. This ends the hold, so the driver's watch covers you again.

3. **Carry on.** If the summary says to wait, end the turn. Otherwise start the next step now, and report to the driver as your brief says, or as `moto report` told you if you have no brief, once the turn ends with the work finished, a question or a blocker.
