---
description: "Implement ONE task from tasks.md with TDD, verify, and commit. Run in a fresh session. Usage: /do-task <id> <n>"
agent: implementer
---

Do task **$2** of work item **$1**. Do only this task.

## Step 1: Find the work folder and check the gate

- Find the folder in `.work/` that starts with `$1-`.
- Read `repos.md` to get the lane.
  - Lane `feature`: `plan.md` must contain `Status: APPROVED`.
  - Lane `bug`: `bug.md` must contain `Status: APPROVED`.
  - If the gate file is not approved, stop and tell the engineer.

## Step 2: Read the task

- Read `tasks.md` and find `Task $2`.
- If it is already checked `[x]`, stop and tell the engineer.
- If an earlier task is not checked, tell the engineer which one and ask whether to continue anyway. Wait.
- Read `<repo>/AGENTS.md` for the task's repo.
- Read the acceptance criteria the task covers in `spec.md` (or `bug.md`), and the matching repo section of `plan.md` (feature lane only).
- Read the last 2 entries of `progress.md`.

## Step 3: Check the repo

- Run `git -C <repo> branch --show-current`. It must match the branch in `repos.md`. If not, stop and tell the engineer.
- Run `git -C <repo> status --porcelain`. If there are changes to files this task does not list, stop and ask.

## Step 4: Do the work

- Read the "Pattern to follow" file and copy its style.
- **.NET code: strict TDD.**
  1. Write or update the test.
  2. Run the verify command. It must FAIL for the expected reason. Save the output.
  3. Write the smallest code change that makes it pass.
  4. Run the verify command. It must PASS. Save the output.
- **Angular or Playwright code:** write the code and tests in any order, then run the verify command. It must PASS.
- Change only the files the task lists. If another file must change, stop and ask.
- If the verify command fails 3 times in a row, stop. Go to Step 6 and log it as blocked.

## Step 5: Lint

- If the repo `AGENTS.md` has a lint or format check command for this project, run it. Fix any problems in the files you changed.

## Step 6: Record

- In `tasks.md`, change `## [ ] Task $2` to `## [x] Task $2`. Only if it passed.
- Add a `progress.md` entry using the template format. Paste the real last lines of the verify output. For .NET, include both the failing and the passing run. If blocked, write what you tried and what failed.

## Step 7: Commit

- Stage only the files you changed: `git -C <repo> add <file> <file>`.
- Commit with a short plain summary: `git -C <repo> commit -m "<short summary>"`. No work item number, no prefix.

## Step 8: Hand off

Tell the engineer, in 3 lines or fewer:
- What changed.
- Verify result.
- Next: "Start a new session, then run `/do-task $1 <next number>`." If this was the last task, say "Run `/review $1`."
