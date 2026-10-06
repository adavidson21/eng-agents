---
description: "Start a work item: fetch it, create its .work folder, pick repos, create branches. Usage: /start <id> <feature|bug>"
agent: planner
---

Start work item **$1** in lane **$2**.

Follow these steps in order. Do not skip any step.

## Step 1: Check the arguments

- `$1` must be a number. `$2` must be `feature` or `bug`.
- If either is wrong, stop and reply: `Usage: /start <id> <feature|bug>`.

## Step 2: Check for existing work

- List the `.work/` folder. If `.work/` does not exist, that is fine: Step 3 creates it.
- If a folder starting with `$1-` already exists, stop. Tell the engineer it exists and suggest `/status $1`.

## Step 3: Get the work item

Run exactly this command:

```
{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/ado/Get-WorkItem.ps1" -Id $1 -WorkRoot ".work"
```

- If it succeeds, the last line of output is the new folder path. Remember it.
- If it fails, show the engineer the error in one line, then ask: "Paste the work item title." When they answer, run:

```
{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/ado/Get-WorkItem.ps1" -Id $1 -WorkRoot ".work" -Title "<the title they pasted>"
```

  This creates the folder with an empty `workitem.md`. Ask the engineer to paste the description, acceptance criteria, and repro steps into that file and reply "done". Wait.

## Step 4: Read the work item

- Read `workitem.md` in the new folder.
- If the type is Bug but `$2` is `feature` (or the other way around), ask the engineer which lane is correct. Use their answer as the lane.

## Step 5: Choose repos

- Read the repo map (the workspace root `AGENTS.md`).
- Decide which repos this work item needs. Shared repos go first.
- Show the engineer a short list: repo folder and one-line reason for each. Ask: "Is this the right list?" Wait for the answer and apply any changes.

## Step 6: Write repos.md

- Copy `{{ENG_HOME}}/templates/repos.md` into the work folder as `repos.md` and fill it in.
- Lane is the lane from Step 4.
- Branch name is `dev/<lane>/<folder name without the .work/ part>`. For example, folder `.work/12345-export-retry` in lane `feature` gives `dev/feature/12345-export-retry`.

## Step 7: Create branches

For each repo in `repos.md`, in order:

1. Run `git -C <repo> status --porcelain`. If there is any output, the repo has uncommitted changes. Skip this repo and tell the engineer.
2. Run `git -C <repo> fetch origin main`.
3. Run `git -C <repo> checkout -b <branch> origin/main`.
4. If the repo is shared and is already on another `dev/` branch with work in progress, do not switch it. Tell the engineer and suggest a git worktree instead.

## Step 8: Start the log

- Copy `{{ENG_HOME}}/templates/progress.md` into the work folder as `progress.md`. Fill in the header and add the first entry for `/start`.

## Step 9: Tell the engineer what is next

Reply with:
- The folder path.
- The repos and branches created, and any that were skipped.
- The next command: `/spec $1` for a feature, or `/bug $1` for a bug.
