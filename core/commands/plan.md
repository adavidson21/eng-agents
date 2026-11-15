---
description: "Write or redo plan.md for a work item. /spec already drafts it; use this to redo a plan, or for items started before the single gate. Usage: /plan <id> [auto]"
agent: planner
---

Write the implementation plan for work item **$1**. Mode: **$2**

If the mode above is `auto`, nobody is watching. Ask nothing. If Step 4 finds a repo that is not in `repos.md`, do not add it: plan only the listed repos, write the missing repo under "Risks" as an open question, and say so in the `progress.md` entry.

## Step 1: Find the work folder and check the gate

- Find the folder in `.work/` that starts with `$1-`.
- Read `spec.md`. If there is none, stop and suggest `/spec $1`. A draft spec is fine: the spec and the plan are approved together.
- If `plan.md` exists and says `Status: APPROVED`, stop and suggest `/tasks $1`.

## Step 2: Read

- Read `spec.md`, `repos.md`, and the latest entries in `progress.md`.
- Read the repo guide (`<repo>/AGENTS.local.md` if it exists, otherwise `<repo>/AGENTS.md`) for every repo in `repos.md`, including its architecture rules and "Patterns to follow" table, and the stack files its `Stack:` line names (Testing rules in `AGENTS.md`).
- If a repo `AGENTS.md` points to an architecture doc, read it.

## Step 3: Investigate the code

- For each acceptance criterion, find where the change belongs. Follow the architecture layers in the repo `AGENTS.md`.
- For each repo, find one existing file that does something similar. This is the "pattern to follow".
- List every file to create or change. Use real paths you have seen.

## Step 4: Check the repo list

- If the plan needs a repo that is not in `repos.md`, stop and ask the engineer. If they agree, add it to `repos.md` and create its branch the same way `/start` does (Step 7 of `/start`).

## Step 5: Write plan.md

- Start from `{{ENG_HOME}}/templates/plan.md`. Write it to the work folder as `plan.md`.
- Keep `Status: DRAFT`. Never set it to APPROVED.
- List repos in the same order as `repos.md`.
- In the test plan, every acceptance criterion must have at least one test, of the kind the repo's stack files ask for.
- Keep the plan short. If a section has nothing to say, write "None".

## Step 6: Log and hand off

- Stamp the draft as your last change to `plan.md`: run exactly `{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/work/Set-DraftHash.ps1" -Path "<work folder>/plan.md"`. It adds a `Draft-hash:` line so `/approve` can tell whether the engineer edited the draft. If you change the file again, run it again.
- Add a `progress.md` entry for `/plan` with a `- Stats: questions=<n> assumptions=<n>` line (how many questions you asked the engineer, and how many assumptions you wrote instead).
- Tell the engineer: "Review `plan.md`. Then run `/tasks $1` to redo the tasks if the plan changed them, and `/approve $1` when the spec, plan and tasks are right."
