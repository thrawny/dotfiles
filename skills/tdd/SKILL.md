---
name: tdd
description: Drive work through a test-driven development loop with explicit RED-GREEN-REFACTOR phases. Use when the user asks for TDD, test-first development, red-green-refactor, a failing test first, integration-style boundary tests, or stepwise checkpoints between test writing, implementation, and refactoring.
---

# tdd

Use TDD as an interactive workflow: plan the next behavior, write one failing test, make it pass with minimal code, then refactor only after GREEN.

## Philosophy

- Prefer tests at **system boundaries** and through **public interfaces**.
- Test **behavior**, not implementation details.
- Avoid mocking internal collaborators; use integration-style tests where practical.
- Reserve narrow unit tests mainly for **pure algorithmic logic**.
- Work in **vertical slices**: one test -> one implementation -> repeat.
- Do **not** write all tests first and all code later.

## Workflow

1. Understand the requested feature or bug fix.
2. Identify the next observable behavior to test.
3. Choose the appropriate test location using the project's existing conventions.
4. Briefly confirm the proposed approach with the user before writing the first test.
5. RED:
   - write exactly one focused failing test
   - add only minimal scaffolding needed so the test fails for the right reason
   - the target failure must be behavioral, not a compilation, syntax, import, or missing-symbol error
   - if needed, create stubs or placeholder implementations first so the test can execute and fail on behavior
   - run the relevant test command and confirm the failure is real
   - summarize what failed and why
   - stop and wait for approval
6. GREEN:
   - implement the smallest change that makes that test pass
   - do not broaden scope or anticipate future cases
   - if the test is wrong, stop and ask permission to return to RED
   - run the relevant tests and confirm they pass
   - stop and wait for approval
7. REFACTOR:
   - refactor only after GREEN
   - keep behavior unchanged and tests green
   - run tests after each meaningful refactor step
   - stop and wait for approval
8. Repeat one behavior at a time for additional cases.

## Guardrails

- Never write implementation before the failing test.
- In RED, do not stop at a compilation, syntax, import, or missing-symbol failure unless the user explicitly wants that as the first checkpoint.
- Prefer minimal scaffolding so the failing test reaches the intended behavioral assertion.
- Always show real test output before moving phases.
- Keep tests descriptive, isolated, and resilient to internal refactors.
- Prefer adding a new test for a new behavior instead of broadening one test excessively.
- If a mocked boundary introduces assumptions, verify them later with a real-boundary or contract test.
- Ask for missing requirements instead of guessing when the expected behavior is unclear.
