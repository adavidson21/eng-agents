---
description: "Approve a work item's spec, plan, or bug analysis so the next phase can start. Usage: /approve <id> [spec|plan|bug]"
agent: planner
---

Approve a gate file for work item **$1**. File named by the engineer, if any: **$2**

Running this command is the engineer's approval. It is the only command that may change a `Status:` line to `APPROVED`. Change only that one line.

## Step 1: Find the work folder

- List `.work/` and find the folder that starts with `$1-`. If there is none, or more than one, stop and say so.
- If `paused.md` contains `Status: PAUSED`, stop and tell the engineer to run `/resume $1` first.
- For a TSD, tell the engineer to use `/publish tsd-<name>` instead and stop.

## Step 2: Pick the file

- If the engineer named `spec`, `plan`, or `bug`, use `spec.md`, `plan.md`, or `bug.md`.
- Otherwise use the first match:

| Condition | File |
|---|---|
| `spec.md` exists and says `Status: DRAFT` | `spec.md` |
| `plan.md` exists and says `Status: DRAFT` | `plan.md` |
| `bug.md` exists and says `Status: DRAFT` | `bug.md` |

- If the file does not exist, or there is no match, reply with the Status line of each of `spec.md`, `plan.md`, and `bug.md` that exists, and stop.
- If the file already says `Status: APPROVED`, say so, give the next command from Step 5, and stop.
- To approve `plan.md`, `spec.md` must already say `Status: APPROVED`. If not, stop and suggest `/approve $1 spec`.

## Step 3: Check open questions

- Read the file's "Open questions" section, if it has one.
- If it lists anything that is not marked `accepted risk`, show those lines and ask: "These questions are still open. Approve anyway and mark them as accepted risk? (Recommended: no. Answer them in the file, or re-run the command that wrote it.)" Wait.
  - If no, stop.
  - If yes, add ` (accepted risk)` to the end of each of those lines.

## Step 4: Approve

- Change the line `Status: DRAFT` to `Status: APPROVED`. Apart from the marks added in Step 3, change nothing else in the file.
- Read the file again and confirm the line now says `Status: APPROVED`.

## Step 5: Log and hand off

- Add a `progress.md` entry for `/approve` that names the file.
- Tell the engineer the file is approved and the next command:

| Approved | Next |
|---|---|
| `spec.md` | `/plan $1` |
| `plan.md` | `/tasks $1` |
| `bug.md` | Start a new session, then `/do-task $1 1` |
