---
description: "Pipeline health across every work item: time to PR, gate edits, review rounds, rework. Usage: /stats [--since yyyy-MM-dd]"
agent: planner
---

Show pipeline stats. Arguments: **$ARGUMENTS**

Do not change any files. This command only reads `.work`.

## Step 1: Run the script

- If the arguments contain `--since <date>`, the date must be `yyyy-MM-dd`. If it is not, reply `Usage: /stats [--since yyyy-MM-dd]` and stop.
- With no date, run exactly:

```
{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/stats/Get-PipelineStats.ps1" -WorkRoot ".work"
```

- With a date, add `-Since <date>` to the end.
- If it fails, show the error in one line and stop.

## Step 2: Reply

- Print the script's output as it is.
- Then add at most 3 observations, one line each. Every observation names the number it comes from. Only point out what the numbers show, for example:
  - A gate approved as written 80% of the time or more, across 5 or more approvals: "Plans were approved as written 9 of 10 times. Consider the quick lane for items like these."
  - Items needing 2 or more reviews 30% of the time or more: "Review found problems late on 4 of 9 items. Look at Review findings by category."
  - Full-suite failures caught in `/do-task`: "Tasks broke other tests 3 times; the checks caught them before review."
  - Questions far above assumptions on spec or plan: the agents may be asking what they could assume.
- If there are fewer than 5 work items, say the numbers are too few to read much into yet, and skip the observations.
- Do not recommend changes the numbers do not support. Never guess at missing data (`n/a`).
