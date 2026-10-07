# Bug: <id> <title>

Status: DRAFT

<!-- The engineer confirms the root cause and tasks with /approve <id>, or by changing the line above to "Status: APPROVED". No other command changes it. -->

## Symptom

- Expected: <what should happen>
- Actual: <what happens>
- Repro steps:
  1. <step>
  2. <step>

## Code path

1. `<entry point file and method>`
2. `<next file and method>`
3. `<where the wrong behavior happens>`

## Root cause

<Explanation.> **Confidence:** <High | Medium | Low>

Evidence:
- <Confirmed: file:line or command output>
- <Suspected: what you think and why>

## Fix approach

<1 to 3 sentences. The smallest change that fixes the root cause.>

## Tasks

The full tasks are written in `tasks.md`. Maximum 3 tasks. Task 1 is always a test that FAILS because of the bug.

1. <title>
2. <title>

## Risks

- <What else could this fix affect? Which callers share this code?>
