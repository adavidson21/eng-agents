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
- With the Tandem tools, `tandem_repo_check` (repo, item) answers both: `branchOk` and `uncommitted`.

## Step 4: Do the work

- Record the station for Workshop's Builds. The step is `fix` when this task came from `review.md` (a `/review` added it after the tasks `/spec` wrote), otherwise `build`:

```
{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/work/Set-Step.ps1" -Folder "<work folder>" -Step <build or fix>
```

- Read the "Pattern to follow" file and copy its style.
- **A stack whose testing rules say strict TDD (Core: `dotnet`):**
  1. Write or update the test.
  2. Run the verify command. It must FAIL for the expected reason. Save the output (the Red run; with the Tandem tools, `tandem_checks_run` kind `command`, save `task-$2-red`).
  3. Write the smallest code change that makes it pass.
  4. Run the verify command. It must PASS. Save the output (the Green run; save `task-$2-green`).
- **Any other stack (Core: `angular`, `playwright`):** write the code and tests in the order its testing rules allow, then run the verify command. It must PASS.
- Change only the files the task lists, plus the test file for a listed code file (test files do not count toward the task size cap). If any other file must change, stop and ask.
- If the verify step fails `retries` times (Factory settings in the pipeline guide, default 3), even with a different fix each time, stop. Go to Step 6 and log it as blocked.

## Step 5: Lint

- If the repo `AGENTS.md` has a lint or format check command for this project, run it. Fix any problems in the files you changed.

## Step 5b: Check nothing else broke

The verify command only runs this task's tests. Run the whole-project check below only when this is the **last open task** in `tasks.md` for this repo, or the task's "Done when" line asks for it. Otherwise write `full=skipped` in Step 6 and go on: `/review` runs the full build and tests once for the whole item.

- First record the station: run `Set-Step.ps1` (Step 4's command) with `-Step test`. If the script fails, go on without it.
- From the repo guide's Commands table, run the **Build** command if there is one, then the **Pre-commit check** command if there is one, otherwise **All unit tests**. If the table has none of these, write `full=skipped` in Step 6 and go on.
- If it passes, write `full=PASS` in Step 6.
- With the Tandem tools, run this as `tandem_checks_run` (kind `build`, then `precommit`, with the item): its `baseline.preExisting` and `baseline.new` sort failures for the rules below.
- If a test fails, read `baseline.md` in the work folder:
  - The test is one this task added and its "Done when" line says it must fail (bug lane Task 1): that is expected. Go on.
  - The test is listed there as failing before this work item: it is not yours. Write it under "Notes" and `full=PASS` (pre-existing failures noted). Go on.
  - Otherwise this task broke it. If the fix is in a file the task lists, fix it and run the check again. This counts toward the retry limit (Step 4). If the fix needs a file the task does not list, stop and ask. Do not commit.
  - If there is no `baseline.md` (an item started before Core 2.22.0, or with `--no-baseline`), ask the engineer whether the failure was there before. Wait.
- If it still fails after `retries` attempts, write `full=FAIL`, log the task as blocked in Step 6, and do not commit.

## Step 5c: Check the UI

Only when `uiCheckPerTask` is on (Factory settings, default on), the task's repo guide has a `## UI checks` table, and this task changed something a person sees. Skip it otherwise and write `ui=skipped` in Step 6.

1. Record the station: `Set-Step.ps1` (Step 4's command) with `-Step ui`. If the script fails, go on without it.
2. Make sure the build's app is running (it starts once and stays up for the whole build; you never start it yourself), in the repo's Path when it has one:

```
{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/ui/Start-UiApp.ps1" -WorkFolder "<work folder>" -Repo "<repo or its Path>" -Guide "<repo guide path>"
```

   `APP: SKIPPED <why>`: write `ui=skipped` and go on to Step 6. Not a failure.
3. Check this task's pages. `<pages>` is the path or paths in the task's "Human interface" line (for example `/orders/12`), comma separated, or leave `-Pages` out to check the table's Pages:

```
{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/ui/Test-Ui.ps1" -WorkFolder "<work folder>" -Repo "<repo or its Path>" -Guide "<repo guide path>" -Name task-$2 -Quick -Pages "<pages>" -Uncommitted
```

4. Read the result (its last line):
   - `UI: SKIPPED <why>`: write `ui=skipped`. Not a failure.
   - `UI: FAIL ...`: each line in `ui/results-task-$2.json`'s `problems` (a console error, a failed request, a page that does not load, more accessibility problems than before) is a failed verify. Fix it in the task's files and run steps 3 and 4 again. This counts toward the retry limit (Step 4).
   - `UI: PASS ...`: read the page as text, `ui/task-$2/aria-<page>-1280.txt` for each page (the page's headings, buttons, fields, links and text, as a person or screen reader meets them). For each acceptance criterion this task covers that a person can see, check the page shows it, and write `found` or `not found` with the line that proves it under Notes in Step 6. A `not found` is a failed verify: fix it and check again (retry limit as above). When `modelSeesImages` is on (Factory settings), also look at the screenshot, `ui/task-$2/<page>-1280.png`.
5. Write `ui=PASS` or `ui=FAIL` in Step 6.

## Step 6: Record

- In `tasks.md`, change `## [ ] Task $2` to `## [x] Task $2`. Only if it passed. With the Tandem tools: `tandem_work_task_done`, then `tandem_work_progress_add` with the saved logs, for the two bullets.
- Add a `progress.md` entry using the template format. Paste the real last lines of the verify output. For .NET, paste the failing run under `Red run` and the passing run under `Green run`, and add `red=<name of the test that failed first>` to the Stats line. If it passed, include the Manual Validation Checklist (see your agent instructions), built from the task's "Human interface" line. If blocked, write what you tried and what failed, and skip the checklist. Add a `- Stats: verify=<PASS or FAIL> full=<PASS, FAIL or skipped> ui=<PASS, FAIL or skipped> attempts=<runs of the verify command>` line.

## Step 7: Commit

- Only if the verify command, Step 5b and Step 5c passed.
- With the Tandem tools, `tandem_repo_commit` (repo, item, files, message) does the two lines below in one step.
- Stage only the files you changed: `git -C <repo> add <file> <file>`.
- Commit with a short plain summary: `git -C <repo> commit -m "<short summary>"`, following the commit message convention in `{{ENG_HOME}}/guides/pipeline.md` unless a Personal or Company rule in `AGENTS.md` says otherwise (for example `AB#<id>`). A rule that adds `AB#<id>` applies only to a linked item (pipeline guide, Who links to ADO); for a local item use its id instead.

## Step 8: Hand off

Tell the engineer, in 3 lines or fewer:
- What changed.
- Verify result.
- Next: "Start a new session, then run `/do-task $1 <next number>`." If this was the last task, say "Run `/review $1`."

Then, if the task passed, print the Manual Validation Checklist as your final output, in the exact format from your agent instructions.
