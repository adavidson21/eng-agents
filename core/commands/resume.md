---
description: "Resume a paused work item: restore branches and summarize where it stands. Usage: /resume <id>"
agent: planner
---

Resume work item **$1**.

Do not change any code. The only files you write are `paused.md` and `progress.md` in the work folder.

## Step 1: Find the pause

- Find the folder in `.work/` that starts with `$1-`. If none, stop and say so.
- Read `paused.md`. If it does not exist or does not contain `Status: PAUSED`, tell the engineer the item is not paused and suggest `/status $1`. Stop.

## Step 2: Restore each repo

For each repo in the Repos table of `paused.md`:

1. Run `git -C <repo> branch --list <branch>`. If the branch does not exist, stop and tell the engineer.
2. Run `git -C <repo> branch --show-current` and `git -C <repo> status --porcelain`.
3. Decide:
   - **Already on the branch:** nothing to do.
   - **On another `dev/` branch** (another work item): do not switch. Ask the engineer: "`<repo>` is on `<other branch>` for another work item. Switch it to `<branch>`, skip this repo for now, or use a git worktree?" Wait and do what they choose. If that repo has uncommitted changes, never switch it; tell the engineer to pause or commit that work first.
   - **On any other branch with no uncommitted changes:** run `git -C <repo> checkout <branch>`.
   - **On any other branch with uncommitted changes:** do not switch. Tell the engineer.
4. Run `git -C <repo> fetch origin main`, then `git -C <repo> log --oneline <branch>..origin/main`. If it prints commits, note how many: main has moved since this branch was made. Do not rebase or merge; tell the engineer.
5. If the pause recorded a WIP commit, confirm it is in `git -C <repo> log -3 --oneline`.

## Step 3: Check nothing else changed

- Re-read the `Status:` lines of `spec.md`, `plan.md`, `bug.md`, and the checkboxes in `tasks.md`.
- Work out the next command using the next-command rules in `/status` (ignoring the paused rule). If it differs from "To resume" in `paused.md`, use the new one and say why.

## Step 4: Mark it resumed

- In `paused.md`, change `Status: PAUSED` to `Status: RESUMED` and add a line under it: `Resumed: <yyyy-mm-dd hh:mm>`. Change nothing else.
- Append an entry to `progress.md` for `/resume`: the state of each repo and the next command.

## Step 5: Tell the engineer

Reply with:
- Where it stands: phase, tasks done, task in progress.
- The "Work in progress" and "Waiting on" sections from `paused.md`, in a few lines.
- The state of each repo, and any repo where main has moved.
- The next command. If it is `/do-task`, say to start a new session first.
