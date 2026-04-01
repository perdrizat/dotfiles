---
name: Red/Green TDD
description: Enforces a Test-Driven Development workflow (Red, Green, Refactor)
---
# Red/Green TDD Skill
This skill enforces a strict Test-Driven Development (TDD) workflow. When following this approach, you must adhere to the Red-Green-Refactor cycle precisely:
## 1. Red (Write a failing test)
- **Action**: Before writing *any* implementation code, write a test for the desired functionality or bug fix.
- **Verification**: Run the test suite to ensure the new test fails. 
- **Requirement**: The test must fail for the right reason (i.e., because the functionality is missing or the bug exists, not because of a syntax error in the test itself). Show the failing test output to the user.
## 2. Green (Write passing code)
- **Action**: Write the absolute *minimum* amount of implementation code necessary to make the failing test pass. Do not over-engineer, add extra features, or prematurely optimize.
- **Verification**: Run the test suite to ensure the new test—and all existing tests—pass. Show the successful test output.
## 3. Refactor (Improve the code)
- **Action**: Once the test passes, refactor the implementation (and the tests if necessary) to improve design, readability, and performance, while removing any duplication.
- **Verification**: Run the test suite again to verify that the refactoring hasn't broken anything.
## Guidelines
- **Strict Ordering**: Never write implementation code without first writing a test that fails.
- **Micro-Commits**: Treat each Red-Green-Refactor cycle as a discrete loop. Make small, incremental changes rather than large batches.
- **Communication**: When the user requests a new feature, explicitly state: "Starting the Red phase: I will write the test first." Always confirm the tests are green before moving to refactoring or the next feature.
