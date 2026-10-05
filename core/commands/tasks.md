---
description: "Break an approved plan into small tasks in tasks.md. Usage: /tasks <id>"
agent: planner
---

Write the task list for work item **$1**.

## Step 1: Find the work folder and check the gate

- Find the folder in `.work/` that starts with `$1-`.
- Read `plan.md`. If it does not contain `Status: APPROVED`, stop. Tell the engineer to approve `plan.md` first.
- If `tasks.md` exists and any task is checked `[x]`, stop. Tell the engineer that work has started and ask whether to add tasks at the end instead.

## Step 2: Read

- Read `spec.md`, `plan.md`, and `repos.md`.
- Read `<repo>/AGENTS.md` for each repo, especially the Commands table. Verify commands must come from that table.

## Step 3: Write the tasks

Start from `{{ENG_HOME}}/templates/tasks.md`. Write it to the work folder as `tasks.md`.

Rules for every task:
- One repo only.
- At most 3 files (or the task size cap in `AGENTS.md`, if different).
- For .NET, the test and the code it tests go in the same task, so the implementer can do TDD.
- Exactly one verify command, copied from the repo `AGENTS.md` and narrowed to the relevant tests with a filter when possible.
- A "Done when" line that anyone could check.
- A "Pattern to follow" file from the plan.
- Order: shared repos first, then the order in `repos.md`. Inside a repo: domain and application code first, then infrastructure, then API, then UI, then Playwright.

## Step 4: Check coverage

- Fill in the coverage table. Every acceptance criterion must be covered by at least one task.
- If one is not covered, add a task.

## Step 5: Log and hand off

- Add a `progress.md` entry for `/tasks`.
- Tell the engineer how many tasks there are per repo, then: "Skim `tasks.md`. If a task looks too big, split it. Then start a NEW session and run `/do-task $1 1`."
