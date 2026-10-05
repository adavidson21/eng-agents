---
description: "Write plan.md from an approved spec. Usage: /plan <id>"
agent: planner
---

Write the implementation plan for work item **$1**.

## Step 1: Find the work folder and check the gate

- Find the folder in `.work/` that starts with `$1-`.
- Read `spec.md`. If it does not contain `Status: APPROVED`, stop. Tell the engineer to review and approve `spec.md` first.
- If `plan.md` exists and says `Status: APPROVED`, stop and suggest `/tasks $1`.

## Step 2: Read

- Read `spec.md`, `repos.md`, and the latest entries in `progress.md`.
- Read `<repo>/AGENTS.md` for every repo in `repos.md`, including its architecture rules and "Patterns to follow" table.
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
- In the test plan, every acceptance criterion must have at least one test. .NET tests are xUnit unit tests with mocks. UI flows use Playwright with `page.route` mocks.
- Keep the plan short. If a section has nothing to say, write "None".

## Step 6: Log and hand off

- Add a `progress.md` entry for `/plan`.
- Tell the engineer: "Review `plan.md`. When it is correct, change the line to `Status: APPROVED`, then run `/tasks $1`."
