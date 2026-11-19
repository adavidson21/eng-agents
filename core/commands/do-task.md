---
description: "Implement ONE task from tasks.md with TDD, verify, and commit. Run in a fresh session. Usage: /do-task <id> <n> [auto]"
agent: implementer
---

Do task **$2** of work item **$1**. Do only this task. Mode: **$3**

If the mode above is `auto`, nobody is watching (autopilot or an eval run). Never ask and never wait. Wherever a step below says to ask or wait, stop instead: do not commit, add a blocked `progress.md` entry (Step 6) that says what you would have asked, and end.

## Step 1: Find the work folder and check the gate

- Find the folder in `.work/` that starts with `$1-`.
- Read `repos.md` to get the lane.
  - Lane `feature`: `plan.md` must contain `Status: APPROVED`.
  - Lane `bug`: `bug.md` must contain `Status: APPROVED`.
  - Lane `quick`: `quick.md` must contain `Status: APPROVED`.
  - If the gate file is not approved, stop and tell the engineer.
- If `paused.md` contains `Status: PAUSED`, stop. Tell the engineer to run `/resume $1` first.

## Step 2: Read the task

- Read `tasks.md` and find `Task $2`.
- If it is already checked `[x]`, stop and tell the engineer.
- If an earlier task is not checked, tell the engineer which one and ask whether to continue anyway. Wait.
- Read the repo guide (`<repo>/AGENTS.local.md` if it exists, otherwise `<repo>/AGENTS.md`) for the task's repo, and the stack files its `Stack:` line names. Their testing rules decide the order of tests and code in Step 4.
- Read the acceptance criteria the task covers in `spec.md` (or `bug.md`, or `quick.md` in the quick lane), and the matching repo section of `plan.md` (feature lane only; in the quick lane the files and pattern are in `quick.md`).
- Read the last 2 entries of `progress.md`.
- If `paused.md` exists and names this task as in progress, read its "Work in progress" section. Continue from there instead of starting over.

## Step 3: Check the repo

If the repo's row in `repos.md` has a **Path** (a worktree), every git, build, test and file command for it in this task runs in that Path (`{{ENG_HOME}}/guides/pipeline.md`, Where the work happens).

- Run `git -C <repo> branch --show-current`. It must match the branch in `repos.md`. If not, stop and tell the engineer.
- Run `git -C <repo> status --porcelain`. If there are changes to files this task does not list, stop and ask.

## Step 4: Do the work

- Read the "Pattern to follow" file and copy its style.
- **A stack whose testing rules say strict TDD (Core: `dotnet`):**
  1. Write or update the test.
  2. Run the verify command. It must FAIL for the expected reason. Save the output (the Red run).
  3. Write the smallest code change that makes it pass.
  4. Run the verify command. It must PASS. Save the output (the Green run).
- **Any other stack (Core: `angular`, `playwright`):** write the code and tests in the order its testing rules allow, then run the verify command. It must PASS.
- Change only the files the task lists, plus the test file for a listed code file (test files do not count toward the task size cap). If any other file must change, stop and ask.
- If the verify step fails `retries` times (Factory settings in the pipeline guide, default 3), even with a different fix each time, stop. Go to Step 6 and log it as blocked.

## Step 5: Lint

- If the repo `AGENTS.md` has a lint or format check command for this project, run it. Fix any problems in the files you changed.

## Step 5b: Check nothing else broke

The verify command only runs this task's tests. Run the whole-project check below only when this is the **last open task** in `tasks.md` for this repo, or the task's "Done when" line asks for it. Otherwise write `full=skipped` in Step 6 and go on: `/review` runs the full build and tests once for the whole item.

- From the repo guide's Commands table, run the **Build** command if there is one, then the **Pre-commit check** command if there is one, otherwise **All unit tests**. If the table has none of these, write `full=skipped` in Step 6 and go on.
- If it passes, write `full=PASS` in Step 6.
- If a test fails, read `baseline.md` in the work folder:
  - The test is one this task added and its "Done when" line says it must fail (bug lane Task 1): that is expected. Go on.
  - The test is listed there as failing before this work item: it is not yours. Write it under "Notes" and `full=PASS` (pre-existing failures noted). Go on.
  - Otherwise this task broke it. If the fix is in a file the task lists, fix it and run the check again. This counts toward the retry limit (Step 4). If the fix needs a file the task does not list, stop and ask. Do not commit.
  - If there is no `baseline.md` (an item started before Core 2.22.0, or with `--no-baseline`), ask the engineer whether the failure was there before. Wait.
- If it still fails after `retries` attempts, write `full=FAIL`, log the task as blocked in Step 6, and do not commit.

## Step 6: Record

- In `tasks.md`, change `## [ ] Task $2` to `## [x] Task $2`. Only if it passed.
- Add a `progress.md` entry using the template format. Paste the real last lines of the verify output. For .NET, paste the failing run under `Red run` and the passing run under `Green run`, and add `red=<name of the test that failed first>` to the Stats line. If it passed, include the Manual Validation Checklist (see your agent instructions), built from the task's "Human interface" line. If blocked, write what you tried and what failed, and skip the checklist. Add a `- Stats: verify=<PASS or FAIL> full=<PASS, FAIL or skipped> attempts=<runs of the verify command>` line.

## Step 7: Commit

- Only if the verify command and Step 5b passed.
- Stage only the files you changed: `git -C <repo> add <file> <file>`.
- Commit with a short plain summary: `git -C <repo> commit -m "<short summary>"`, following the commit message convention in `{{ENG_HOME}}/guides/pipeline.md` unless a Personal or Company rule in `AGENTS.md` says otherwise (for example `AB#<id>`). A rule that adds `AB#<id>` applies only to a linked item (pipeline guide, Who links to ADO); for a local item use its id instead.

## Step 8: Hand off

Tell the engineer, in 3 lines or fewer:
- What changed.
- Verify result.
- Next: "Start a new session, then run `/do-task $1 <next number>`." If this was the last task, say "Run `/review $1`."

Then, if the task passed, print the Manual Validation Checklist as your final output, in the exact format from your agent instructions.
