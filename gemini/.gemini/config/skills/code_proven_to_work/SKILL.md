---
name: Code Proven to Work 
description: Ensures all code changes are proven to work through mandatory manual and automated testing before completion, inspired by "Code Proven to Work".
---
# Code Proven to Work
Every code change must be proven to work. You must not deliver code without verifying it functions correctly. There are two mandatory steps to proving a piece of code works: Manual Testing and Automated Testing. Neither is optional.
## Prerequisites: API Keys and Required Input
If any API keys, credentials, or other user input are needed to implement or test the changes, you must ask the user to provide this information **before starting the work** or as soon as you realize the need.

## 1. Manual Testing First
Before finalizing any code, you must manually verify it does what it is supposed to do.
*   **Browser End-to-End Testing (Mandatory)**: Before returning a completed task to the user, you must test it end-to-end in the browser using the browser subagent. You **must** ensure you capture a **screen recording** of the test session (using the `RecordingName` parameter).
*   **Executing Code**: If possible (e.g., CLI tools, scripts, backend endpoints), run the relevant code yourself in the terminal. Verify the output matches the expected desired state. Produce proof by returning terminal output or logs.
*   **Collaborative Manual Testing**: If a change involves complex networking, mobile apps, or state you cannot easily test yourself, you must pause and ask the user to manually test it. Provide the exact sequence of commands or steps they need to perform, and wait for their confirmation before proceeding.
*   **Edge Cases**: Once the happy path is verified, you must actively consider test edge cases to verify resilience.
## 2. Automated Testing
You must bundle every code change (fix or feature) with an automated test that proves the change works.
*   **Regression Proof**: The automated test must be written in a way that it would fail if your implementation change is reverted.
*   **Test Patterns**: Use the existing test patterns in the project (where applicable). The process for the test should mirror the manual testing: get the system into an initial known state, exercise the change, and assert the system behaved correctly.
*   Do not skip manual testing just because you think the automated test has you covered. Both are required!
## Enforcement Protocol
When implementing any code change, follow these steps:
1. **Plan Testing**: Briefly outline how you will manually test the change and what automated test you will write. Share this with the user if the approach is ambiguous.
2. **Implement & Manually Test**: Write the code and execute the manual test (or specifically ask the user to test and wait for confirmation).
3. **Write Automated Test**: Implement the automated test to codify the proof. Ensure the test fails when the change is not present, and passes when it is.
4. **Deliver**: Only consider the task "done" once both manual testing and automated tests are confirmed.

