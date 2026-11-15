---
description: "Draft a short standup or status update from .work progress logs and Docket tasks. Usage: /standup [days back, default 1]"
agent: planner
---

Draft a standup update. Days to look back: **$ARGUMENTS** (use 1 if empty; on a Monday, use 3).

Do not change any files.

## Step 1: Gather

- List every folder in `.work/` except `_onboard`, `_dashboard` and `_retro`. That includes work items and the `spike-`, `shape-`, `scope-`, `triage-` and `refine-` folders.
- For each, read `repos.md`, `paused.md` if any, the checkboxes in `tasks.md`, the `review.md` verdict if any, and the `progress.md` entries dated within the look-back window. For a spike, shape, scope, triage or refine folder, its last `progress.md` entry says where it stands.
- Skip folders with no entries in the window unless they are blocked.
- **Docket tasks (read only):** `Get-Content ~/.workshop/config.json` gives `dataDir` (default `~/Workshop`). Read `<dataDir>/prioritizer/tasks.json`. From its `items`: tasks with `done` true and a `doneAt` date in the look-back window (and not `wontDo`) are done; tasks with `focusOn` set to today and not done are today's. If the file is missing, skip Docket without comment. Never write to it.

## Step 2: Write

Reply with exactly this format. One line per item. No other text.

```
Yesterday:
- <id> <short name>: <what got done, plain words>
- <Docket task title>
Today:
- <id> <short name>: <next step from the pipeline>
- <Docket task title>
Blockers:
- <id>: <what is blocked and on whom>, or "None"
```

Rules:
- Use plain language a non-engineer could follow. No file names, no command names.
- A spike, shape or scope in progress is one line: what it is about and where it stands ("waiting on answers", "brief ready").
- At most 5 Docket lines under each heading; skip a Docket task that repeats a work item line.
- Say "waiting on my review" when the next step is approving a spec, plan, or bug.
- A blocker is anything logged as blocked, failed 3 times, or a review with Blockers.
- If `paused.md` says `Status: PAUSED`, list the item under Today as "paused: <reason>" instead of a next step.
