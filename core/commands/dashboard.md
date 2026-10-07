---
description: "Build and open the work dashboard: every item in .work, where it stands, what to run next, and which repos have work in progress. Usage: /dashboard"
agent: planner
---

Build the work dashboard.

Do not change any files yourself. The script writes the only file: `.work/dashboard.html`.

## Step 1: Run the script

Run exactly this command from the workspace root:

```
{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/dashboard/New-Dashboard.ps1" -WorkRoot ".work"
```

- It reads `.work/` and the git state of each repo in the workspace, writes `.work/dashboard.html`, and opens it in the browser.
- If it fails because `.work` does not exist, tell the engineer there is no work yet and suggest `/start <id> <feature|bug>`. Stop.
- If it fails for any other reason, show the error in one line and stop.

## Step 2: Tell the engineer

Reply with, and nothing else:
- The first line of the script output (the item and repo counts).
- The file path (the last line of the output).
- "Refresh it any time with `/dashboard`."
