---
description: "Resume a paused work item: restore branches and summarize where it stands. Usage: /resume <id>"
agent: planner
---

Resume work item **$1**.

Do not change any code. The only files you write are `paused.md` and `progress.md` in the work folder.

## Step 1: Find the pause

- Find the folder in `.work/` that starts with `$1-`. If none, stop and say so.
- Read `paused.md`. If it does not exist or does not contain `Status: PAUSED`, tell the engineer the item is not paused and suggest `/status $1`. Stop.

## Step 1b: Show the brief and the last breadcrumb

Before you touch any repo, print these for the engineer, so coming back gets the same help as starting:

- The Goal line of `brief.md`, if the work folder has one. If it does not, skip it without comment.
- The last entry of `progress.md`: its heading line and its `Next` line.

## Step 2: Restore each repo

For each repo in the Repos table of `paused.md`:

- **If its row in `repos.md` has a Path** (a worktree): run steps 1 and 2 in that Path. It is always on its own branch; do not switch anything in the repo folder.

1. Run `git -C <repo> branch --list <branch>`. If the branch does not exist, stop and tell the engineer.
2. Run `git -C <repo> branch --show-current` and `git -C <repo> status --porcelain`.
3. Decide:
   - **Already on the branch:** nothing to do.
   - **On another `dev/` branch** (another work item), **or on any branch with uncommitted changes:** never switch it. Ask nothing: run exactly `{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/work/New-Worktree.ps1" -Workspace "." -Repo "<repo>" -Folder "<work folder name>" -Branch "<branch>" -Existing`, write its last line in the repo's **Path** column in `repos.md` (add the column if the table has none), and use that Path from here on. If it fails, show the error in one line and skip this repo.
   - **On any other branch with no uncommitted changes:** run `git -C <repo> checkout <branch>`.
4. Take the repo's base from the **Base** column in `repos.md` (`origin/main` if there is no Base column, from an older item). If the base starts with `origin/`, run `git -C <repo> fetch origin`. Then run `git -C <repo> log --oneline <branch>..<base>`. If it prints commits, note how many: the base has moved since this branch was made. Do not rebase or merge; tell the engineer.
5. If the pause recorded a WIP commit, confirm it is in `git -C <repo> log -3 --oneline`.

## Step 3: Check nothing else changed

- Re-read the `Status:` lines of `spec.md`, `plan.md`, `bug.md`, `quick.md`, and the checkboxes in `tasks.md`.
- Work out the next command using the next-command rules in `/status` (ignoring the paused rule). If it differs from "To resume" in `paused.md`, use the new one and say why.

## Step 4: Mark it resumed

- In `paused.md`, change `Status: PAUSED` to `Status: RESUMED` and add a line under it: `Resumed: <yyyy-mm-dd hh:mm>`. Change nothing else.
- Append an entry to `progress.md` for `/resume`: the state of each repo and the next command.

## Step 5: Tell the engineer

Reply in 5 lines or fewer:
- Where it stands: phase, tasks done, task in progress.
- Work in progress and what it is waiting on, from `paused.md`, in one or two lines.
- Only repos that need attention (not switched, or the base moved). Say "Repos ready" if none.
- The next command. If it is `/do-task`, say to start a new session first.
