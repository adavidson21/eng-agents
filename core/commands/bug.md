---
description: "Fast lane: reproduce and root-cause a bug, write bug.md and up to 3 tasks. Usage: /bug <id>"
agent: investigator
---

Investigate bug **$1**.

## Step 1: Find the work folder

- Find the folder in `.work/` that starts with `$1-`. If there is none, stop and suggest `/start $1 bug`.
- Read `workitem.md`, `repos.md`, and `progress.md`.
- Read the repo guide (`<repo>/AGENTS.local.md` if it exists, otherwise `<repo>/AGENTS.md`) for every repo in `repos.md`.
- If `bug.md` exists and says `Status: APPROVED`, stop and suggest `/do-task $1 1`.

## Step 2: Restate the bug

- Write down expected behavior, actual behavior, and repro steps from `workitem.md`.
- If any of these is missing or unclear, ask the engineer ONE question at a time. Ask at most 3 questions.

## Step 3: Trace the code path

- Start at the entry point (API endpoint, handler, or UI component) and follow the code step by step to where the wrong behavior happens.
- Write down each step with the file and method.
- Use `git -C <repo> log` or `git -C <repo> blame` on the suspect lines if a recent change might have caused it.

## Step 4: Find the root cause

- State the root cause and label your evidence Confirmed or Suspected.
- Give a confidence level: High, Medium, or Low.
- **If confidence is Low, stop here.** Write what you found to `bug.md` with the Tasks section empty, and tell the engineer to run `/spike $1` instead.

## Step 5: Write bug.md

- Start from `{{ENG_HOME}}/templates/bug.md`. Write it to the work folder as `bug.md`. Keep `Status: DRAFT`.

## Step 6: Write tasks.md

- Start from `{{ENG_HOME}}/templates/tasks.md`. Write it to the work folder as `tasks.md`.
- **At most 3 tasks.** If the fix needs more, stop and tell the engineer this should move to the feature lane (`/spec $1`).
- **Task 1 is always a test that reproduces the bug.** Its "Done when" line is: "the new test FAILS, showing the bug." Combine it with the fix in one task only if the test and fix are each in a single file.
- The next task fixes the bug. Its "Done when" is: "the test from Task 1 now passes and no other tests fail."
- Use verify commands from the repo `AGENTS.md`.

## Step 7: Log and hand off

- Add a `progress.md` entry for `/bug`.
- Tell the engineer the root cause in one sentence and the confidence level, then: "Review `bug.md` and `tasks.md`. If correct, run `/approve $1` (or change `bug.md` to `Status: APPROVED` yourself), start a new session, and run `/do-task $1 1`."
