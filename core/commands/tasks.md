---
description: "Write or redo tasks.md from the plan. /spec already drafts it; use this to redo the tasks. Usage: /tasks <id> [auto]"
agent: planner
---

Write the task list for work item **$1**. Mode: **$2**

If the mode above is `auto`, nobody is watching. Ask nothing: where Step 1 says to ask, add a `progress.md` entry saying why you stopped, and stop.

## Step 1: Find the work folder and check the gate

- Find the folder in `.work/` that starts with `$1-`.
- Read `plan.md`. If there is none, stop and suggest `/spec $1`. A draft plan is fine: one `/approve` covers the spec, plan and tasks.
- If `tasks.md` exists, no task is checked and the mode is `auto` (autopilot after the one gate): `/spec` already drafted it. Keep it as it is, add a `progress.md` entry for `/tasks` that says so with a `- Stats: tasks=<number of tasks>` line, and stop.
- If `tasks.md` exists and any task is checked `[x]`, stop. Tell the engineer that work has started and ask whether to add tasks at the end instead.

## Step 2: Read

- Read `spec.md`, `plan.md`, and `repos.md`.
- Read the repo guide (`<repo>/AGENTS.local.md` if it exists, otherwise `<repo>/AGENTS.md`) for each repo, especially the Commands table, and the stack files its `Stack:` line names. Verify commands must come from that table.

## Step 3: Write the tasks

Start from `{{ENG_HOME}}/templates/tasks.md`. Write it to the work folder as `tasks.md`.

Rules for every task:
- One repo only.
- At most 3 files (or the task size cap in `AGENTS.md`, if different).
- Follow each stack file's task rules (for example, `dotnet` puts the test and the code it tests in the same task, so the implementer can do TDD).
- Exactly one verify command, copied from the repo `AGENTS.md` and narrowed to the relevant tests with a filter when possible.
- A "Done when" line that anyone could check.
- A "Pattern to follow" file from the plan.
- A "Human interface" line: the page, button, endpoint, command, or log line a person uses to see this change. Use only routes and names you have seen in the code.
- Order: shared repos first, then the order in `repos.md`. Inside a repo: domain and application code first, then infrastructure, then API, then UI, then Playwright.

## Step 4: Check coverage

- Fill in the coverage table. Every acceptance criterion must be covered by at least one task.
- If one is not covered, add a task.

## Step 5: Log and hand off

- Add a `progress.md` entry for `/tasks` with a `- Stats: tasks=<number of tasks>` line. `/stats` uses it to count tasks added later (mostly review fixes).
- Tell the engineer how many tasks there are per repo, then: "Skim `tasks.md`. If a task looks too big, split it." If `plan.md` is still a draft, add: "Run `/approve $1` when the spec, plan and tasks are right, then start a NEW session and run `/do-task $1 1`." Otherwise: "Start a NEW session and run `/do-task $1 1`."
