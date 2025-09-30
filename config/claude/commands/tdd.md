---
argument-hint: task/feature/bug description
description: Test-Driven Development workflow - write failing test first, then implement
---

## Your task

Implement the requested feature/fix using Test-Driven Development (TDD) methodology. Follow the Red-Green-Refactor cycle:

1. **Understand the requirement**:

   - Parse the task/feature/bug description provided as argument
   - Identify what needs to be tested
   - Determine the appropriate test file location and naming convention
   - Consider edge cases and success/failure scenarios
   - Decide whether to add a new test or extend an existing test (prefer new tests for different behaviors/scenarios)
   - **STOP and confirm approach with user before proceeding**

2. **RED: Write a failing test**:

   - Create or locate the appropriate test file
   - Write a focused test that describes the desired behavior
   - Ensure the test is runnable and currently fails
   - Use descriptive test names that explain the expected behavior
   - Run the test suite to confirm it fails with the expected error
   - Summarize the test failure back to the user (what failed and why)
   - **STOP and wait for user feedback before proceeding**

3. **GREEN: Implement minimal code to pass**:

   - After user confirms the failing test is correct, implement the simplest solution
   - Focus only on making the test pass, nothing more
   - Avoid over-engineering or adding unnecessary features
   - **If you realize the test needs changes, STOP immediately**:
     - Explain why the test was incorrect
     - Ask user permission to return to RED phase to fix the test
     - Never modify tests during implementation to make them pass
   - Run the test suite to confirm the test now passes
   - Ensure no existing tests were broken
   - **STOP and wait for user feedback before proceeding**

4. **REFACTOR: Improve the code (if needed)**:

   - After user confirms the implementation is correct, review the code
   - Ask if refactoring is desired
   - If yes, improve code quality while keeping tests green:
     - Remove duplication
     - Improve naming and structure
     - Enhance readability
     - Optimize if necessary
   - Run tests after each refactoring step
   - **STOP and wait for user feedback**

5. **Iterate if needed**:
   - If the feature requires multiple test cases, repeat the cycle
   - Add one test case at a time
   - Always wait for user confirmation between steps
   - Consider additional edge cases or scenarios

## Important guidelines

- **Never write implementation code before the test**
- **Always run tests and show output before moving to next step**
- **Wait for explicit user approval before progressing through each phase**
- Use the project's existing test framework and conventions
- Keep tests isolated and independent
- Test behavior, not implementation details
- Write clear, descriptive test names
- Follow AAA pattern: Arrange, Act, Assert (or Given-When-Then)
- Commit after each successful Red-Green-Refactor cycle if user requests
