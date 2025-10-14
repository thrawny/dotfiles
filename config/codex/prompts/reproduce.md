## Your task

Create a test case that reproduces the described bug. The user may specify the test type (unit, integration, e2e) or point to similar existing tests.

**Parameters**:
- `$1` - Bug description (if not provided, ask for it)
- `$2` - Test type: unit, integration, or e2e (optional)

1. Understand the bug:
   - If `$1` is provided, use it as the bug description.
   - Otherwise, ask the user to describe the bug.
   - Identify what's broken, expected vs actual behavior, and any error messages.
2. Find test patterns:
   - If `$2` is provided, use it as the preferred test type (unit, integration, or e2e).
   - Look for existing tests in the same area.
   - If user mentions test type or points to examples, follow those patterns.
   - Identify the test framework (Jest, pytest, etc.).
3. Write the reproduction test:
   - Create a failing test that demonstrates the bug.
   - Use descriptive names like `test_should_handle_empty_input`.
   - Add a comment explaining the bug.
   - Mark as expected failure if the framework supports it.
4. Verify it fails correctly: Run the test and confirm it reproduces the reported issue.
5. Ask for help if needed: If reproducing requires app code changes, ask: "Reproducing this bug requires modifying application code. Should I proceed with minimal changes or try a different approach?"

Remember: Only create tests, don't fix the bug or modify production code.

