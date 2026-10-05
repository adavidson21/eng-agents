---
description: "Show where a work item is in the pipeline, or list all items. Usage: /status [id]"
agent: planner
---

Show pipeline status. Argument: **$ARGUMENTS**

Do not change any files.

## If an id was given

1. Find the folder in `.work/` that starts with `$1-`. If none, say so and stop.
2. Read `repos.md`, the `Status:` line of `spec.md`, `plan.md`, and `bug.md` (whichever exist), the checkboxes in `tasks.md`, the verdict in `review.md`, whether `pr.md` exists, and the last entry of `progress.md`.
3. Work out the next command using the table below.
4. Reply in this format and nothing else:

```
<id> <name> | lane: <lane>
Repos: <repo (branch)>, ...
Spec: <missing | DRAFT | APPROVED>   Plan: <...>   Bug: <...>
Tasks: <done>/<total> done
Review: <none | READY | CHANGES NEEDED>   PR text: <yes/no>
Last: <date> /<command>: <one line>
Next: <exact command>
```

## If no id was given

- List every folder in `.work/` except `_onboard`.
- For each, work out the phase and next command using the table below.
- Reply with one table: folder, lane, phase, next command.

## Next-command rules

Check in this order. The first match wins.

| Condition | Next |
|---|---|
| No `repos.md` | `/start <id> <feature or bug>` |
| Lane feature, no `spec.md` | `/spec <id>` |
| `spec.md` is DRAFT | Engineer approves `spec.md` |
| Lane feature, no `plan.md` | `/plan <id>` |
| `plan.md` is DRAFT | Engineer approves `plan.md` |
| Lane bug, no `bug.md` | `/bug <id>` |
| `bug.md` is DRAFT | Engineer approves `bug.md` |
| No `tasks.md` | `/tasks <id>` |
| Unchecked task exists | `/do-task <id> <first unchecked number>` (new session) |
| No `review.md`, or tasks were added after it | `/review <id>` |
| Review is CHANGES NEEDED | Accept findings, then `/do-task` the fix tasks |
| No `pr.md` | `/pr <id>` |
| Otherwise | Push branches and open PRs |
