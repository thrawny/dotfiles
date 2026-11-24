Adapted from Jane Street's socratic-tutor skill,
https://github.com/janestreet/agent_skills/tree/469868f4489cbdbe178c775a0af05bb6bef63689/socratic-tutor

Changes from upstream:

- The skill is invoked by the user only, so the intent guard is gone.
- Progress is kept in `tutor/<slug>.md` in the working directory, where the
  slug is the topic in kebab-case, and resumed from there. The file records
  whether the course is complete and the checks passed toward each level.
  Run with no topic, the tutor offers the saved courses. Spaced review favours
  the subskills tested longest ago. "save state" writes the file and shows
  its contents, which "resume from:" accepts in another session.
- The progress file is rewritten after every check and records misconceptions
  without the correct answer, since the user sees each write. A broad topic
  is finished only when every branch reaches the target, and a failed review
  reopens a finished course.
- In Claude Code the tutor asks the user to turn off prompt suggestions,
  which can leak answers (janestreet/agent_skills#16).
- The devil's-advocate challenge runs at most once per answer.
- A few prohibitions are reworded as the behaviour to follow.

The MIT License

Copyright (c) 2026 Jane Street Group, LLC <opensource-contacts@janestreet.com>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
