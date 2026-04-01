---
name: tdd
description: Implement work through an explicit red-green-refactor loop with user approval gates. Use when the user says `/tdd`, asks for test-driven development, or wants test-first implementation with checkpoints between RED, GREEN, and REFACTOR.
---

# tdd

Drive implementation through an explicit TDD loop and pause between phases.

## Workflow

1. Gather the task requirements and any test-location or framework constraints.
2. Understand the behavior to test and decide where the test should live.
3. Stop and confirm the proposed test approach with the user before writing the test.
4. RED:
   - write a focused failing test
   - add only minimal scaffolding needed for the test to fail for the right reason
   - run the test to confirm the expected failure
   - summarize the failure
   - stop and wait for approval
5. GREEN:
   - implement the smallest code change that makes the test pass
   - if the test itself is wrong, stop and ask to return to RED
   - run the relevant tests
   - stop and wait for approval
6. REFACTOR:
   - refactor only after the user agrees
   - keep tests green throughout
   - stop and wait again when refactoring is complete
7. Repeat for additional cases one at a time.

## Guardrails

- Never write implementation before the failing test.
- Always show real test results before advancing phases.
- Test behavior, not implementation details.
- Keep tests descriptive and isolated.
