---
allowed-tools: Read, Write, Glob, Grep, Bash(mkdir:*), Bash(ls:*), Edit, MultiEdit, Bash(rg:*), Bash(mkdir:*)
argument-hint: <subfolder>/<issue-name> or just <issue-name>
description: Creates a structured issue file with description and definition of done checklist
---

## Your task

Root issue folder: docs/issues

Create a structured issue file in the docs/issues directory with an incrementing issue number and proper description and definition of done sections. Follow these guidelines:

1. **Parse the arguments**:

   - Accept subfolder/issue-name format: `/create-issue feature/user-authentication`
   - Accept simple issue name: `/create-issue user-login-bug`
   - Use kebab-case for issue filenames
   - Default to root issues directory if no subfolder specified

2. **Determine next issue number**:

   - Scan all existing issue files in issues directory and subdirectories
   - Find the highest existing issue number from filenames like `001-issue-name.md`
   - Increment by 1 for the new issue number
   - Format as 3-digit zero-padded number (001, 002, etc.)

3. **Create directory structure**:

   - Ensure `issues/` directory exists in repository root
   - Create subfolder if specified in argument
   - Handle nested directory paths properly

4. **Generate issue file**:

   - Create markdown file with format: `{number}-{issue-name}.md`
   - Include structured template with:
     - Title section with issue number
     - Description section with placeholder
     - Definition of Done section with checkboxes
     - Optional sections for acceptance criteria, notes, and related issues

5. **Validate and confirm**:
   - Check that file was created successfully
   - Display the file path and issue number assigned
   - Provide guidance on next steps for filling out the issue

If no argument is provided, prompt the user for the issue name. If the file already exists, ask for confirmation before overwriting. Use the following template structure:

```markdown
# Issue #{number}: [Issue Title]

**Status**: Not Started
**Dependencies**: None

## Overview

[Describe the issue, bug, or feature request in detail. Include context, user impact, and business value. Make it short, 5-10 lines.]

## Technical Implementation

[Describe the technical approach, architecture changes, dependencies, and implementation details. Make it short, 5-10 lines.]

## Definition of Done

[List of subtasks to tick off to complete the issue. Max 4]
```
