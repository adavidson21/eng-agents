---
description: "Export approved milestones as work items: an ADO import file (default), ADO items, or local items. Usage: /backlog scope-<name> [csv|ado|local]"
agent: milestone-architect
---

Export the backlog in **.work/$1/** (the `.work/` part is optional). Mode: **$2** (empty means `csv`). Do not change any code.

## Step 1: Find the folder and check the gate

- The folder is `.work/$1/`, or `$1` itself if it already starts with `.work/`. If `$1` is empty or the folder does not exist, list the `.work/scope-*` folders and stop.
- The mode is `csv`, `ado`, or `local`. If it is anything else, stop and reply: `Usage: /backlog scope-<name> [csv|ado|local]`.
- Read `milestones.md`. If it does not contain `Status: APPROVED`, stop. Tell the engineer to review it and run `/approve $1 milestones` first.

## Step 2: Ask where the items go (csv and ado only)

Skip this step for `local`.

- Ask in one message: "Which area path and iteration path? Leave either empty to use the project default. Story type: `User Story` (Recommended for the Agile process; use `Product Backlog Item` for Scrum)."
- Wait. Use their answers as `<area>`, `<iteration>`, and `<story type>`. An empty answer means leave that argument out.

## Step 3: Export

Run the command for the mode. Add `-AreaPath "<area>"`, `-IterationPath "<iteration>"`, and `-StoryType "<story type>"` only when they have a value.

**csv:**

```
{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/ado/Export-Backlog.ps1" -Folder ".work/$1" -Csv
```

**ado:** first a dry run, which calls nothing:

```
{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/ado/Export-Backlog.ps1" -Folder ".work/$1" -Push -DryRun
```

- Show the engineer the connection, project, and item list it printed, and ask: "Create these items in ADO? (Recommended: yes if the connection and project are right.)" Wait. If no, stop.
- If the work item lives in another ADO connection, ask which one and add `-From "<connection>"` to both commands.
- Then run the same command without `-DryRun`.

**local:**

```
{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/ado/Export-Backlog.ps1" -Folder ".work/$1" -Local
```

If the command fails, show the error in one line. For `ado`, offer `/backlog $1 csv` instead. Items already created are recorded in `published.md`, so running the same command again skips them.

## Step 4: Log and hand off

- Add a `progress.md` entry for `/backlog` with the last lines of the output.
- **csv:** "The import file is `.work/$1/backlog.csv`. In ADO, open Boards > Work Items, choose Import Work Items, and upload it. After the import, start with the first story: `/start <its id> feature`." If the `Epic:` line names an existing epic (`#<id>`), add: "The features import without a parent. Link them to epic #<id> in ADO after the import."
- **ado** and **local:** show the table from `.work/$1/published.md` and say: "Start with the first story: `/start <id of Story 1.1> feature`. Work top to bottom."
