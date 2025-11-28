# Research Codebase

You are tasked with conducting comprehensive research across the codebase to answer user questions by spawning parallel sub-agents and synthesizing their findings.

## Initial Setup:

When this command is invoked, respond with:

```
I'm ready to research the codebase. Please provide your research question or area of interest, and I'll analyze it thoroughly by exploring relevant components and connections.
```

Then wait for the user's research query.

## Steps to follow after receiving the research query:

1. **Read any directly mentioned files first:**

   - If the user mentions specific files (tickets, docs, JSON), read them fully first
   - Use the Read tool without limit/offset parameters to read entire files
   - Read these files yourself in the main context before spawning any sub-tasks
   - This ensures you have full context before decomposing the research

2. **Analyze and decompose the research question:**

   - Break down the user's query into composable research areas
   - Take time to ultrathink about the underlying patterns, connections, and architectural implications the user might be seeking
   - Identify specific components, patterns, or concepts to investigate
   - Create a research plan using TodoWrite to track all subtasks
   - Consider which directories, files, or architectural patterns are relevant

3. **Spawn parallel sub-agent tasks for comprehensive research:**

   - Create multiple Task agents to research different aspects concurrently
   - We now have specialized agents that know how to do specific research tasks:

   **For codebase research:**

   - Use the **codebase-locator** agent to find WHERE files and components live
   - Use the **codebase-analyzer** agent to understand HOW specific code works
   - Use the **codebase-pattern-finder** agent if you need examples of similar implementations

   The key is to use these agents intelligently:

   - Start with locator agents to find what exists
   - Then use analyzer agents on the most promising findings
   - Run multiple agents in parallel when they're searching for different things
   - Each agent knows its job - just tell it what you're looking for
   - Don't write detailed prompts about HOW to search - the agents already know

4. **Wait for all sub-agents to complete and synthesize findings:**

   - Wait for all sub-agent tasks to complete before proceeding
   - Compile all sub-agent results (codebase findings and any docs/ or external notes)
   - Prioritize live codebase findings as primary source of truth
   - Use docs/ or external notes as supplementary historical context
   - Connect findings across different components
   - Include specific file paths and line numbers for reference
   - Verify referenced paths are correct for this repository
   - Highlight patterns, connections, and architectural decisions
   - Answer the user's specific questions with concrete evidence

5. **Gather metadata for the research document:**

   - generate all relevant metadata
   - Filename: `docs/research/YYYY-MM-DD_HH-MM-SS_topic.md`

6. **Generate research document:**

   - Use the metadata gathered in step 5
   - Structure the document with YAML frontmatter followed by content:

     ```markdown
     ---
     date: [Current date and time with timezone in ISO format]
     researcher: [Researcher name]
     git_commit: [Current commit hash]
     branch: [Current branch name]
     repository: [Repository name]
     topic: "[User's Question/Topic]"
     tags: [research, codebase, relevant-component-names]
     status: complete
     last_updated: [Current date in YYYY-MM-DD format]
     last_updated_by: [Researcher name]
     ---

     # Research: [User's Question/Topic]

     **Date**: [Current date and time with timezone from step 5]
     **Researcher**: [Researcher name]
     **Git Commit**: [Current commit hash from step 5]
     **Branch**: [Current branch name from step 5]
     **Repository**: [Repository name]

     ## Research Question

     [Original user query]

     ## Summary

     [High-level findings answering the user's question]

     ## Detailed Findings

     ### [Component/Area 1]

     - Finding with reference ([file.ext:line](link))
     - Connection to other components
     - Implementation details

     ### [Component/Area 2]

     ...

     ## Code References

     - `path/to/file.py:123` - Description of what's there
     - `another/file.ts:45-67` - Description of the code block

     ## Architecture Insights

     [Patterns, conventions, and design decisions discovered]

     ## Historical Context (optional)

     [Relevant insights from docs/ or an external knowledge base, if configured]

     - `docs/decisions/something.md` - Historical decision about X
     - External KB link - Past exploration of Y

     ## Related Research

     [Links to other research documents in docs/research/]

     ## Open Questions

     [Any areas that need further investigation]
     ```

7. **Sync and present findings:**

   - Present a concise summary of findings to the user
   - Include key file references for easy navigation
   - Ask if they have follow-up questions or need clarification

8. **Handle follow-up questions:**
   - If the user has follow-up questions, append to the same research document
   - Update the frontmatter fields `last_updated` and `last_updated_by` to reflect the update
   - Add `last_updated_note: "Added follow-up research for [brief description]"` to frontmatter
   - Add a new section: `## Follow-up Research [timestamp]`
   - Spawn new sub-agents as needed for additional investigation
   - Continue updating the document and syncing

## Important notes:

- Always use parallel Task agents to maximize efficiency and minimize context usage
- Always run fresh codebase research - never rely solely on existing research documents
- The docs/ directory or an external notes repo can provide historical context to supplement live findings
- Focus on finding concrete file paths and line numbers for developer reference
- Research documents should be self-contained with all necessary context
- Each sub-agent prompt should be specific and focused on read-only operations
- Consider cross-component connections and architectural patterns
- Include temporal context (when the research was conducted)
- Linking to GitHub is optional; local paths are acceptable
- Keep the main agent focused on synthesis, not deep file reading
- Encourage sub-agents to find examples and usage patterns, not just definitions
- Explore relevant docs/ directories, not just research
- **File reading**: Always read mentioned files FULLY (no limit/offset) before spawning sub-tasks
- **Ordering**: Follow the numbered steps in sequence

  - Read mentioned files first before spawning sub-tasks (step 1)
  - Wait for all sub-agents to complete before synthesizing (step 4)
  - Gather metadata before writing the document (step 5 before step 6)
  - Don't write the research document with placeholder values

- **Frontmatter consistency**:
  - Always include frontmatter at the beginning of research documents
  - Keep frontmatter fields consistent across all research documents
  - Update frontmatter when adding follow-up research
  - Use snake_case for multi-word field names (e.g., `last_updated`, `git_commit`)
  - Tags should be relevant to the research topic and components studied
