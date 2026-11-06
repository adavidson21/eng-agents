---
description: "Write a brief for the person a work item is delegated to. Posts nothing. Usage: /handoff <ADO id> <assignee name>"
agent: writer
---

Write a handoff brief for work item **$1**, for **$2**. All arguments: **$ARGUMENTS**

Follow these steps in order. Do not change any code, and never post anything to ADO.

## Step 1: Check the arguments

- `$1` must be a number (an ADO work item) or a local id (`L` and a number). The rest of the arguments is the assignee's name.
- If either is missing, stop and reply: `Usage: /handoff <ADO id> <assignee name>`.
- The folder is `.work/handoff-$1/`. If it already has a `handoff.md`, update it rather than starting over.

## Step 2: Gather what is known

- For a number, run exactly this command:

```
{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/ado/Get-WorkItem.ps1" -Id $1 -WorkRoot ".work/handoff-$1" -Parents -IncludeComments
```

  If it fails, say so in one line and stop.
- For a local id, read `workitem.md` in the `.work/$1-*` folder.
- Read `.work/triage-$1/triage.md` and any `.work/refine-*/refine.md` or `.work/scope-*/milestones.md` that names `#$1`, if they exist.
- Read the repo map, the product note (Product notes in the core rules) and the repo guide of each repo the work touches, then find the files where the work starts. Note each with its path.

## Step 3: Write handoff.md

- Start from `{{ENG_HOME}}/templates/handoff.md`. Write it to the folder as `handoff.md`.
- Copy the acceptance criteria as written. Do not invent new ones; if there are none, say so under "Questions to settle first".
- Write for a teammate who has not seen the request: plain words, real paths, no judgment about anyone.

## Step 4: Hand off

- Add a `progress.md` entry for `/handoff` (copy `{{ENG_HOME}}/templates/progress.md` first if the folder has none).
- Reply in 2 lines: where the brief is, and that nothing was posted: paste it into the work item or bring it to your 1:1 with $2.
