---
description: "Two-pass review of all changes for a work item: spec compliance, then code quality. Usage: /review <id> [auto]"
agent: reviewer
---

Review all changes for work item **$1**. Mode: **$2**

If the mode above is `auto`, autopilot is running this review and nobody is watching. Do not ask questions. Where a step below says to ask, follow its `auto` rule instead.

## Step 1: Find the work folder

- Find the folder in `.work/` that starts with `$1-`.
- Read `repos.md`, `spec.md` (or `bug.md` for the bug lane, `quick.md` for the quick lane), `plan.md` if it exists, `tasks.md`, and `progress.md`.
- If any task in `tasks.md` is not checked, list them and ask the engineer whether to review anyway. Wait.
  - `auto`: do not review. Add a `progress.md` entry that names the unchecked tasks, and stop.

## Step 1b: Catch up with the base

- Read the Factory settings in `{{ENG_HOME}}/guides/pipeline.md` (`autoFix`, `uiChecks`, `regression`, `taskFileCap`).
- Follow "Catch up with the base" in the pipeline guide for each repo. A conflict becomes a `Blocker` finding (category `conflict`) in Step 7.

## Step 2: Read the rules

Record each station for Workshop's Builds as you reach it: `{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/work/Set-Step.ps1" -Folder "<work folder>" -Step <step>`, with `test` at Step 3, `ui` at Step 3b (only when it runs) and `review` at Step 4. If the script fails, go on without it.

- Read the repo guide (`<repo>/AGENTS.local.md` if it exists, otherwise `<repo>/AGENTS.md`) for every repo in `repos.md`, and the stack files its `Stack:` line names.

## Step 3: Run the tests

This is the item's one full check before review (`/do-task` only runs each task's verify command, plus a full check on the last task).

- For each repo, run its **Build** command if its `AGENTS.md` has one, then its "All unit tests" command.
- A failing test listed as failing in `baseline.md` was failing before this work item: note it, it is not a finding. Any other failure is a `Blocker` (category `tests`).
- **Regression tests.** Only if `regression` is on (Factory settings, default on). For each repo whose guide has a `## Regression tests` table, run the whole suite exactly (in its Path when it has one), whatever the change touched:

  ```
  {{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/tests/Test-Suite.ps1" -WorkFolder "<work folder>" -Repo "<repo or its Path>" -Guide "<repo guide path>" -Name after -Base "<base>"
  ```

  Its last line is the result. `Tests: PASS ...`: record it. `Tests: FAIL ...`: read `tests/results-after.json`. Each entry in `failures` is a `Blocker`: category `regression` when its file is not in `newTests` (a test that passed before this change), else `tests`. Its fix task fixes the code, never the test, unless the spec changes that behavior on purpose. Entries in `preExisting` failed before this change: note them, not findings. Each entry in `flakyTests` is a `Nit` (category `flaky`). `Tests: SKIPPED <why>`: record the reason, not a finding.
- **UI tests** in a repo with no Regression tests table: if the guide has a Playwright tests command, run it whenever the work changed anything a person sees or clicks. Otherwise record `UI tests: none in this repo` (not a finding).
- Record each result.

## Step 3b: UI checks

Only if `uiChecks` is on (Factory settings, default on). First stop the app the build kept running for its per-task checks, so the full check starts it fresh: `{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/ui/Stop-UiApp.ps1" -WorkFolder "<work folder>"` (it prints `APP: NONE` when there is none). Then, for each repo whose guide has a `## UI checks` table, run exactly (in its Path when it has one):

```
{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/ui/Test-Ui.ps1" -WorkFolder "<work folder>" -Repo "<repo or its Path>" -Guide "<repo guide path>" -Name after -Base "<base>"
```

The script starts the app, screenshots the table's pages at two widths, checks them, compares with the `before` run from `/start` and stops the app; you never start the app yourself. Its last line is the result:

- `UI: PASS ...`: record it.
- `UI: FAIL ...`: read `ui/results-after.json`. Each line in its `problems` is a `Blocker` (category `ui`, location the page and width).
- `UI: SKIPPED <why>`: record the reason. Not a finding.
- Pages in `changed` that no task or acceptance criterion meant to change: one line under "Questions for you" each (not findings).

## Step 4: Read the diff

For a repo with a **Path** in `repos.md` (a worktree), run its tests and git commands in that Path.

- For each repo, take its base from the **Base** column in `repos.md` (`origin/main` if there is no Base column, from an older item).
- For each repo, run `git -C <repo> diff --stat <base>...HEAD`, then `git -C <repo> diff <base>...HEAD`.
- **A later round.** If `review.md` already exists and has a `Reviewed at:` line for the repo, the earlier findings that were not fix tasks stand. Read only what changed since: `git -C <repo> diff <that commit>..HEAD` (if the commit is gone after a rebase, read the full diff). Pass 1 still checks every criterion; Pass 2 checks only the changed files.
- If the diff is large, read it one file at a time with `git -C <repo> diff <base>...HEAD -- <file>`.

## Step 5: Pass 1, spec compliance

- For each acceptance criterion, mark `Met`, `Partly met`, or `Not met`. Give the test and file that prove it.
- List changes that no criterion or task asked for.
- **The engineer's comments.** For each task with a `- From comment: <repo>/<id>` line (written by `/revise` after a Send back), read that comment in `code-review/<repo>/rev-<n>.json` (the newest `rev-<n>.json` that has the id) and check the diff does what it asked. If it does not, add a `Blocker` finding (category `spec`, location the comment's file and line) that quotes the comment.
- For each checked task, find its Manual Validation Checklist in `progress.md`: in its `/do-task` entry, or in a later entry for that task. A task whose "Human interface" line is `none, covered by <test command>`, or whose criteria all have passing `[AC-<n>]` tests, needs only the line `Covered by tests: <test command>`. If it is missing or vague (no exact URL, click, value, or command), add a `Blocker` finding for that task (category `checklist`).
- **Acceptance tests.** In a repo whose guide has a `## Regression tests` table, every criterion a person can see or click needs its `[AC-<n>]` in the suite's `acceptance` list (Step 3). A missing one is a `Should fix` finding (category `tests`), so autopilot writes it.
- **TDD evidence.** For each checked task that changed .NET code, find its `Red run` and `Green run` output blocks in `progress.md` (or the failing and passing runs in entries older than Core 2.23.0). The Red run must show the named test failing on an assertion or the expected exception, not a compile error elsewhere. If the Red run is missing, or shows something other than the new test failing for the expected reason, add a `Should fix` finding (category `tdd`), unless a Personal or Company rule makes it a `Blocker`. Bug lane Task 1 (a test that must fail) counts as its own Red run.

## Step 6: Pass 2, code quality

Check every changed file against this list, the repo `AGENTS.md`, and the "Review checklist" of each stack file the repo guide names (`{{ENG_HOME}}/stacks/<stack>.md`, see Testing rules in `AGENTS.md`):

- **Architecture:** layer references follow the repo's allowed-references table. Business logic is not in controllers or components.
- **Consistency:** matches the "pattern to follow" files in naming, structure, and error handling.
- **Correctness:** null handling, edge cases, off-by-one, errors handled the way the pattern does.
- **Security:** input validated, authorization not bypassed, no secrets, no personal data in logs.
- **Tests:** test behavior, not implementation details. No skipped or commented-out tests. No real database, backend or shared environment.
- **Leftovers:** no debug logging, commented-out code, unused imports or variables, or TODO comments added. A leftover is a `Blocker`: the code goes to the PR clean.
- **Docs:** when the change alters behavior, a setting, an API or a command that the repo's docs describe (its README, `docs/`, CHANGELOG, or the docs its repo guide names), those docs are updated in the same change. Missing docs are a `Blocker` (category `docs`), so the fix is a task before the PR.
- **Overbuild:** no abstractions, interfaces, options or layers that nobody asked for and only one caller uses (core rule 8). `Should fix`.

Give every finding a category: the bold word of the checklist item it falls under, in lower case (`architecture`, `consistency`, `correctness`, `security`, `tests`, `leftovers`, `docs`, `overbuild`, or the category a stack file's item names, such as `efcore`, `angular` or `playwright`), or `spec`, `scope`, `checklist` or `tdd` for Pass 1 findings, or `regression` or `flaky` for the regression suite (Step 3). If none fits, use the closest one; do not invent new categories.

## Step 7: Write review.md

- If `review.md` already exists (an earlier review round), first copy it unchanged to `history/review-<yyyy-mm-dd>-<n>.md` in the work folder (`<n>` = 1, 2, ... so nothing is overwritten). `/retro` reads every round.
- Start from `{{ENG_HOME}}/templates/review.md`. Write it to the work folder as `review.md`. Fill `Reviewed at:` with each repo and `git -C <repo> rev-parse --short HEAD`, the UI checks section with each repo's UI line, and the Regression tests section with each repo's Tests line.
- Put every finding, from both passes, in the findings table with its category.
- Anything you are not sure is a problem goes under "Questions for you" as one line with its location, not in the findings table. Questions do not change the verdict.
- Copy every task's Manual Validation Checklist into the "Manual validation" section, in task order, so the engineer has one list to walk through.
- Verdict is `READY` only if all tests pass (baseline failures aside), every criterion is `Met`, and there are no Blockers.

## Step 8: Hand off

- Add a `progress.md` entry for `/review` with a `- Stats: blockers=<n> should_fix=<n> nits=<n> verdict=<READY or CHANGES_NEEDED>` line.
- Summarize for the engineer: verdict, number of findings by severity, and the Blockers in one line each.
- `auto`: append one fix task for each `Blocker` finding, and when `autoFix` is `should-fix` (the default) also for each `Should fix` finding, to the end of `tasks.md`, numbered after the last task, in the normal task format (one repo, at most `taskFileCap` files, one verify command from the repo `AGENTS.md`). Should fix tasks do not change the verdict: a review with only Should fix findings is still READY, and autopilot builds those tasks before the PR text. Never add tasks for `Nit` (they stay in `review.md`), or for checklist Blockers: they change no code. Name the checklist tasks and the added tasks in the `progress.md` entry. Do not ask anything, and stop.
- If there are checklist Blockers, list the tasks that need one and tell the engineer to add each checklist as a new `progress.md` entry for that task (by hand, or by asking the implementer), then run `/review $1` again. These never become fix tasks.
- Not `auto`: append one fix task for each `Blocker` finding (except checklist Blockers) to the end of `tasks.md`, numbered after the last task, in the normal task format, without asking. Then, if there are `Should fix` or `Nit` findings or Questions, list them and ask: "Which of these should also become fix tasks?" Append the ones they pick the same way. Then tell them to run `/do-task $1 <n>` for each in a new session, then `/review $1` again.
- If the verdict is READY, tell them to run `/pr $1`.
