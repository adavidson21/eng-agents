---
description: "Open Loom in Workshop: every item in .work, where it stands, and the agents working on it. Usage: /dashboard [id]"
agent: planner
---

Open the work dashboard. Argument: **$ARGUMENTS**

Do not change any files. Do not start Workshop yourself.

## Step 1: Open Loom

Loom, in Workshop, is the live view: every item, the next step, and the agents working on them, with buttons that run each step.

If `$ARGUMENTS` is empty, run exactly this command:

```
{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/dashboard/Open-Dispatch.ps1"
```

If `$ARGUMENTS` is an id (a work item number such as `41207`, a local id such as `L3`, or a `.work` folder such as `pr-512`), add `-Id <id>` so Loom opens at that item:

```
{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/dashboard/Open-Dispatch.ps1" -Id <id>
```

- It returns within a few seconds. It never starts anything.
- Exit code 0: Loom opened. Reply with every output line but the last, then the address (the last line). Stop.
- Exit code 2: Workshop is not running (or not installed). Reply with its output lines, without the address, and stop. Do not start Workshop. Without Workshop, `/status` shows where each item is.
- Any other failure: show the error in one line, suggest `/status`, and stop.
