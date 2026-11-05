---
description: "Open Dispatch in Workshop: every item in .work, where it stands, and the agents working on it. Usage: /dashboard [id], or /dashboard static for a snapshot page without Workshop"
agent: planner
---

Open the work dashboard. Argument: **$ARGUMENTS**

Do not change any files yourself. Do not start Workshop yourself. The static page script in Step 2 writes the only file (`.work/dashboard.html`).

If `$ARGUMENTS` is `static`, skip to Step 2.

## Step 1: Open Dispatch

Dispatch, in Workshop, is the live view: every item, the next step, and the agents working on them, with buttons that run each step.

If `$ARGUMENTS` is empty, run exactly this command:

```
{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/dashboard/Open-Dispatch.ps1"
```

If `$ARGUMENTS` is an id (a work item number such as `41207`, a local id such as `L3`, or a `.work` folder such as `pr-512`), add `-Id <id>` so Dispatch opens at that item:

```
{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/dashboard/Open-Dispatch.ps1" -Id <id>
```

- It returns within a few seconds. It never starts anything.
- Exit code 0: Dispatch opened. Reply with every output line but the last, then the address (the last line). Stop.
- Exit code 2: Workshop is not running (or not installed). Reply with its output lines, without the address, and stop. Do not start Workshop and do not build the static page unless the engineer asks.
- Any other failure: show the error in one line, say "Building the static page instead.", and go on to Step 2.

## Step 2: Build the static page

Run exactly this command from the workspace root:

```
{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/dashboard/New-Dashboard.ps1" -WorkRoot ".work"
```

- It reads `.work/` and the git state of each repo in the workspace, writes `.work/dashboard.html`, and opens it in the browser. The page is a snapshot for terminal-only use, with a link to Dispatch.
- If it fails because `.work` does not exist, tell the engineer there is no work yet and suggest `/start <id> <feature|bug>`. Stop.
- If it fails for any other reason, show the error in one line and stop.

Reply with, and nothing else:
- The first line of the script output (the item and repo counts).
- The file path (the last line of the output).
