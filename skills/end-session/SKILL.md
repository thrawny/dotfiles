---
name: end-session
description: Close a session by cleaning up background tasks and updating relevant issues.
disable-model-invocation: true
---

# End session

Keep this routine to background cleanup and issue updates. Do not change version-control state or write a handoff file.

1. Check the work agreed for this session. If any of it is unfinished, stop before taking closing actions and ask the user how to proceed. Resume according to their guidance. Remaining work on a larger issue does not by itself mean this session is unfinished.

2. Account for background tasks you started during this session. Stop those that are no longer useful. Use your judgment to retain tasks still needed after the session, and record what remains running and why. Leave tasks belonging to the user or other sessions alone. Verify that tasks you stopped have exited.

3. Identify relevant issues from the session context and the available issue tracker. If an issue is expected but you cannot confidently identify it, ask the user. If none is expected or identified, skip issue updates and report that.

4. Update identified issues with the session's progress, verification results, and any remaining work. Change status only when the evidence supports it. Mark an issue complete only when its completion criteria are met, distinguishing completed session work from completion of the whole issue. Verify that the updates succeeded.

If a closing action fails, complete the other independent actions before reporting the failure and asking the user for guidance on what remains.

Finish with a short report of background cleanup, tasks retained and why, issue updates or skips, and anything still needing attention.
