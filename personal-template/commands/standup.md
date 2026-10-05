---
description: "Draft a short standup or status update from all .work progress logs. Usage: /standup [days back, default 1]"
agent: planner
---

Draft a standup update. Days to look back: **$ARGUMENTS** (use 1 if empty; on a Monday, use 3).

Do not change any files.

## Step 1: Gather

- List every folder in `.work/` except `_onboard`.
- For each, read `repos.md`, the checkboxes in `tasks.md`, the `review.md` verdict if any, and the `progress.md` entries dated within the look-back window.
- Skip folders with no entries in the window unless they are blocked.

## Step 2: Write

Reply with exactly this format. One line per item. No other text.

```
Yesterday:
- <id> <short name>: <what got done, plain words>
Today:
- <id> <short name>: <next step from the pipeline>
Blockers:
- <id>: <what is blocked and on whom>, or "None"
```

Rules:
- Use plain language a non-engineer could follow. No file names, no command names.
- Say "waiting on my review" when the next step is approving a spec, plan, or bug.
- A blocker is anything logged as blocked, failed 3 times, or a review with Blockers.
