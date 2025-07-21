---
allowed-tools: Read, Write, Glob, Grep, Bash, Edit, MultiEdit, Task
argument-hint: command description including name
description: Template for creating new Claude commands - generates a complete command structure
---

## Context

- If in dotfiles repo, create command in `claude/commands/`
- If in other repo, create command in `.claude/commands/<command-name>.md`
- Use kebab-case for command names (e.g., `my-command.md`)

## Your task

Based on the description provided, create a claude code command with the following structure:

### 1. Parse the command description

- Extract the command name from the description
- Identify the main purpose and functionality
- Determine what tools will be needed
- Consider if arguments are required

### 2. Create the command file structure

Use this template structure:

```yaml
---
allowed-tools: <comma-separated list of tools>
argument-hint: <optional - describe expected arguments>
description: <brief one-line description>
---

## Context

<!-- Use ! and backticked commands to execute commands and include their output -->

## Your task

Based on the above context, [describe the main task]. Follow these guidelines:

1. **First step**: Description
   - Sub-point with details
   - Another consideration

2. **Second step**: Description
   - Handle edge cases
   - Provide clear feedback

<!-- Continue with numbered steps -->

If [condition], then [action]. Otherwise, [alternative action].
```

### 3. Tool permissions patterns

Choose appropriate tools based on command type:

**File operations:**

- `Read, Write, Edit, MultiEdit, Glob, Grep`

**Git operations:**

- `Bash(git status:*), Bash(git add:*), Bash(git commit:*), Bash(git push:*), Bash(git diff:*), Bash(git log:*), Bash(git branch:*)`

**GitHub operations:**

- `Bash(gh pr:*), Bash(gh api:*), Bash(gh repo:*)`

**General development:**

- `Bash(npm:*), Bash(yarn:*), Bash(pip:*), Bash(cargo:*), Bash(go:*)`

**System operations:**

- `Bash(ls:*), Bash(cat:*), Bash(grep:*), Bash(find:*), Bash(mkdir:*), Bash(cp:*), Bash(mv:*), Bash(rm:*)`

**Monitoring/waiting:**

- `Bash(sleep:*), Bash(curl:*), Bash(ping:*)`

**Specific command restrictions:**

- `Bash(docker run:*), Bash(kubectl:*), Bash(terraform:*)`

### 4. Context command examples

Use ! and backticked commands to execute commands and include their output.

### 5. Task guideline patterns

**Simple execution pattern:**

```markdown
1. **Analyze the current state**: Check [specific conditions]
2. **Execute the main action**: Run [specific commands]
3. **Verify the result**: Confirm [expected outcome]
4. **Provide feedback**: Report [status/results]
```

````

**Interactive workflow pattern:**

```markdown
1. **Gather information**: Analyze [context/requirements]
2. **Ask for confirmation**: If [condition], ask user to confirm [action]
3. **Execute with validation**: Run [commands] with error handling
4. **Handle edge cases**: If [error condition], then [recovery action]
```

**Monitoring loop pattern:**

```markdown
1. **Initialize monitoring**: Set up [monitoring target]
2. **Enter monitoring loop**:
   - Check [status/condition]
   - Wait for [specified time] (default: [X] seconds)
   - Display progress updates
   - Continue until [success condition]
3. **Take action when ready**: Execute [final action]
4. **Report completion**: Summarize [results/status]
```

**File processing pattern:**

```markdown
1. **Locate target files**: Find files matching [pattern/criteria]
2. **Analyze file contents**: Read and understand [file structure/content]
3. **Make targeted changes**: Apply [specific modifications]
4. **Validate changes**: Ensure [correctness/syntax]
5. **Clean up**: Remove [temporary files/backup files]
```

### 6. Argument handling

For commands that accept arguments:

```markdown
argument-hint: timeout in seconds (default: 120)
```

In the task section:

```markdown
2. **Handle arguments**:
   - Accept timeout parameter: `/command-name 300`
   - Use default value if no argument provided: 120 seconds
   - Validate argument is a positive number
```

### 7. Best practices to include

- Always provide clear feedback about what's happening
- Handle errors gracefully with helpful messages
- Use appropriate wait times for monitoring commands
- Follow existing project conventions and patterns
- Include Claude signature for git commits and PRs
- Validate inputs before executing destructive operations
- Provide guidance when manual intervention is needed

### 8. Common command types to reference

**Build/Test commands:**

- Run build processes
- Execute test suites
- Check code quality
- Deploy applications

**Git workflow commands:**

- Create smart commits
- Manage branches
- Create/update pull requests
- Clean up repositories

**Project management:**

- Initialize new projects
- Update dependencies
- Generate documentation
- Manage configurations

**Development tools:**

- Start development servers
- Watch for file changes
- Format code
- Lint and fix issues

**System administration:**

- Monitor services
- Manage processes
- Check system health
- Backup/restore data

Create a complete, working command file that follows these patterns and can be immediately used as a slash command.
````
