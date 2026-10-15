---
description: "Open the work dashboard: every item in .work, where it stands, and what to run next. Starts the live dashboard if it is not running. Usage: /dashboard, or /dashboard static for a one-off page"
agent: planner
---

Open the work dashboard.

Do not change any files yourself. The scripts below write the only files (`.work/dashboard.html` and `.work/_dashboard/`).

If `$ARGUMENTS` is `static`, skip to Step 2.

## Step 1: Open the live dashboard

Run exactly this command from the workspace root:

```
{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/dashboard/Start-LiveDashboard.ps1" -Detach
```

- It returns within about 30 seconds. It starts the live dashboard in its own minimized window (or just opens it if it is already running) and opens it in the browser. This is not a long-running process for you to manage: the command itself ends.
- If it succeeds, reply with its first output line and "It runs in its own minimized window; close that window to stop it." Then stop.
- If it fails because `.work` does not exist, tell the engineer there is no work yet and suggest `/start <id> <feature|bug>`. Stop.
- If it fails for any other reason (for example, Node is missing), show the error in one line, say "Building the static page instead.", and go on to Step 2.

## Step 2: Build the static page

Run exactly this command from the workspace root:

```
{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/dashboard/New-Dashboard.ps1" -WorkRoot ".work"
```

- It reads `.work/` and the git state of each repo in the workspace, writes `.work/dashboard.html`, and opens it in the browser.
- If it fails because `.work` does not exist, tell the engineer there is no work yet and suggest `/start <id> <feature|bug>`. Stop.
- If it fails for any other reason, show the error in one line and stop.

Reply with, and nothing else:
- The first line of the script output (the item and repo counts).
- The file path (the last line of the output).
