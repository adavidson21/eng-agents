---
description: "Pause a work item: record where it stands so anyone can pick it up later. Usage: /pause <id> [reason]"
agent: planner
---

Pause work item **$1**. Reason: **$ARGUMENTS** (everything after the id; may be empty).

Do not change any code. The only files you write are `paused.md` and `progress.md` in the work folder.

## Step 1: Find the work folder

- Find the folder in `.work/` that starts with `$1-`. If none, stop and say so.
- If `paused.md` exists and contains `Status: PAUSED`, stop. Tell the engineer it is already paused and suggest `/resume $1`.

## Step 2: Read where it stands

- Read `repos.md` (lane, repos, branches).
- Read the `Status:` line of `spec.md`, `plan.md`, and `bug.md` (whichever exist).
- Read the checkboxes in `tasks.md` (if it exists) and the verdict in `review.md` (if it exists).
- Read the last 3 entries of `progress.md`.
- Work out the phase and the next command using the next-command rules in `/status`.

## Step 3: Check each repo

For each repo in `repos.md`:

1. Run `git -C <repo> branch --show-current`.
2. Run `git -C <repo> status --porcelain`.
3. Run `git -C <repo> log -1 --oneline`.
4. If there are uncommitted changes, run `git -C <repo> diff --stat` to see what changed.

## Step 4: Handle uncommitted changes

Skip this step if every repo is clean.

For each repo with uncommitted changes, show the engineer the changed files and ask **one question**:

- **A. Commit as work in progress** (recommended if you might use this repo for other work before resuming). You will run `git -C <repo> add -- <each changed file>` then `git -C <repo> commit -m "WIP $1: <task title>"`.
- **B. Leave uncommitted** (only if nobody will use this repo before resuming).

Wait for the answer and do what they choose. Never stash, discard, reset, or restore changes.

## Step 5: Write paused.md

- Start from `{{ENG_HOME}}/templates/paused.md`. Write it to the work folder as `paused.md`, replacing any old copy.
- "Work in progress": if a task was half done, describe from the diff and the task text what is done and what is left. Name files. Otherwise write "None".
- "Waiting on": open questions from `spec.md` or `bug.md`, and anything the progress notes say is blocked.
- "To resume": the exact next command from Step 2.

## Step 6: Log it

Append an entry to `progress.md` for `/pause`: the reason, the state of each repo, and `Next: /resume $1`.

## Step 7: Tell the engineer

Reply with:
- One line: where it stands (phase, tasks done, task in progress).
- The state of each repo. Say which repos are now safe to use for other work.
- "To pick this up later: `/resume $1`."
