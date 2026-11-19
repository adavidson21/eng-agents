---
description: "Quick lane: one combined spec and plan (quick.md) plus tasks.md for small work, approved once. Steps up to the feature lane when the work is bigger. Usage: /quick <id> [auto]"
agent: planner
---

Write the quick plan for work item **$1**. Mode: **$2**

The quick lane is for small work: one repo (not a shared one), at most `quickTasks` tasks (Factory settings in the pipeline guide, default 3), no schema, migration or public API contract change, and acceptance criteria that are already clear. It replaces `/spec`, `/plan` and `/tasks` with one file and one approval.

If the mode above is `auto`, nobody is watching. Ask nothing: write every question you would have asked under "Assumptions", and write `questions=0` on the Stats line.

## Step 1: Find the work folder and check the lane

- Find the folder in `.work/` that starts with `$1-`. If there is none, stop and suggest `/start $1 quick`.
- Read `repos.md`. The lane must be `quick`. If it is not, stop and tell the engineer which command its lane uses next (`/status $1`).
- If `paused.md` contains `Status: PAUSED`, stop and tell the engineer to run `/resume $1` first.
- If `quick.md` exists and says `Status: APPROVED`, stop and suggest `/do-task $1 1` in a new session.
- If `quick.md` exists as a draft, read it and `tasks.md`. You are refining them, not starting over.

## Step 2: Read

- Read `workitem.md`, `repos.md`, and the latest entries of `progress.md`.
- Read the repo guide (`<repo>/AGENTS.local.md` if it exists, otherwise `<repo>/AGENTS.md`) for the repo in `repos.md`: Commands table, architecture rules, "Patterns to follow".
- Find the code related to the work item. Read at most 8 files.

## Step 3: Check it still fits

Step up to the feature lane if any of these is true:

- It needs more than `quickTasks` tasks (each task: one repo, at most `taskFileCap` files, test files not counted).
- It needs a second repo, or the repo is shared.
- It changes a database schema, a migration, or a public API contract.
- The acceptance criteria are missing or contradict each other, and a wrong guess would change what gets built.

To step up:

- In `repos.md`, change `Lane: quick` to `Lane: feature`. Change nothing else; the branch stays as it is.
- Do not write `quick.md` or `tasks.md`.
- Add a `progress.md` entry for `/quick` that says why, with a `- Stats: escalated=1` line. Put what you found (files, the pattern to follow) under "Notes" so `/spec` can use it.
- Tell the engineer in two lines: why it does not fit the quick lane, and "Run `/spec $1`." Stop.

## Step 4: Ask (at most 1 question)

- Only if a wrong guess would change what gets built. Give 2 to 4 options with your recommendation first. Everything else goes under "Assumptions".

## Step 5: Write quick.md

- Start from `{{ENG_HOME}}/templates/quick.md`. Write it to the work folder as `quick.md`.
- Keep `Status: DRAFT`. Never set it to APPROVED.
- Acceptance criteria: `AC-1`, `AC-2`, ... in Given / When / Then, each testable. In a repo whose guide has a `## Regression tests` table, a criterion a person can see or click gets an end-to-end test titled with `[AC-<n>]` (playwright stack).
- Files: real paths you have seen, and one "Pattern to follow" file. Follow core rule 8: values likely to change go in the repo's existing config or constants.
- Fill "Why this fits the quick lane" honestly. If you cannot, go back to Step 3.

## Step 6: Write tasks.md

- Start from `{{ENG_HOME}}/templates/tasks.md`. Write it to the work folder as `tasks.md`, following every rule in `/tasks` Step 3: one repo, at most `taskFileCap` files (test files not counted), for .NET the test and its code in the same task, one verify command from the repo guide's Commands table, a "Done when" line, a "Pattern to follow" file and a "Human interface" line.
- At most `quickTasks` tasks. Fill the coverage table: every acceptance criterion in `quick.md` is covered.

## Step 7: Log and hand off

- Stamp the draft as your last change to `quick.md`: run exactly `{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/work/Set-DraftHash.ps1" -Path "<work folder>/quick.md"`. If you change the file again, run it again.
- Add a `progress.md` entry for `/quick` with a `- Stats: questions=<n> assumptions=<n> tasks=<number of tasks>` line.
- Tell the engineer: "Review `quick.md` and `tasks.md`. When they are right, run `/approve $1`, then start a new session and run `/do-task $1 1`."
