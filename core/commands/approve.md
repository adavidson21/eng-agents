---
description: "Approve a work item's spec, plan, or bug analysis, a scope's stories or milestones, or a refined story, so the next phase can start. Usage: /approve <id> [spec|plan|bug|quick], /approve <id> quick auto, /approve <id> spec auto (a story from an approved breakdown), /approve scope-<name> [stories|milestones], or /approve refine-<name>"
agent: planner
---

Approve a gate file for work item **$1**. File named by the engineer, if any: **$2**

Running this command is the engineer's approval. It is the only command that may change a `Status:` line to `APPROVED`. Change only that one line.

Mode: **$3**

## Auto mode (review by exception: the quick lane, and stories from an approved breakdown)

If the mode above is `auto`, Workshop's autopilot is running this and nobody is watching. It only runs it when the engineer turned on hands-off Quick changes, or for a story whose breakdown the engineer approved. Ask nothing. Do these steps instead of Steps 2 to 6:

1. `$2` must be `quick` with `quick` as the lane in `repos.md`, or `spec` for a story from an approved breakdown (`workitem.md` has a `- Breakdown: approved` line). Otherwise do not approve: say `Needs you: auto approval is only for the quick lane and stories from an approved breakdown.` and stop. For `spec`, follow **Story auto approval** below instead of steps 2 to 4.
2. Read `quick.md` and `tasks.md`. Approve only if **all** of these hold:
   - `quick.md` says `Status: DRAFT`.
   - `Test-DraftHash.ps1` (Step 3's command) prints `unchanged`: the draft is as the agent wrote it.
   - "Open questions" is empty, or holds only placeholder text.
   - "Assumptions" has at most 3 lines.
   - `tasks.md` has at most `quickTasks` tasks (Factory settings in the pipeline guide, default 3), and its coverage table covers every acceptance criterion.
   - "Why this fits the quick lane" is filled in.
3. **Clean:** change `Status: DRAFT` to `Status: APPROVED` in `quick.md` (nothing else), read it back to confirm, add a `progress.md` entry for `/approve` with `- Stats: gate=auto file=quick`, and say `Approved automatically: quick.md is clean.` Write no product notes (Step 5b): assumptions are not the engineer's answers.
4. **Not clean:** change nothing in `quick.md`. Add a `progress.md` entry for `/approve` that names every check that failed, with `- Stats: gate=held file=quick`, and end your reply with one line: `Needs you: <the failed checks, in a few words>.` The engineer reviews it and runs `/approve $1` themselves.

### Story auto approval (`/approve <id> spec auto`, Core 4.10.0)

The engineer approved the epic's breakdown (`milestones.md`), so a story's plan needs them only when it drifts from what they approved.

1. Run exactly this command, with the work folder:

   ```
   {{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/work/Test-StoryDrift.ps1" -Folder "<work folder>"
   ```

   It prints a `drift: <reason>` line for each place the plan leaves the breakdown (over the task file cap, a new dependency, a migration, auth or security code, files outside the story's areas or repos), then `CLEAN` or `DRIFT`.
2. Approve only if **all** of these hold:
   - The script printed `CLEAN`.
   - `spec.md` and `plan.md` say `Status: DRAFT`, and `tasks.md` exists.
   - `Test-DraftHash.ps1` (Step 3's command) prints `unchanged` for both.
   - "Open questions" in `spec.md` is empty, or holds only placeholder text.
   - `tasks.md`'s coverage table covers every acceptance criterion.
3. **Clean:** change `Status: DRAFT` to `Status: APPROVED` in `spec.md` and in `plan.md` (nothing else), read both back to confirm, add one `progress.md` entry for `/approve` with `- Stats: gate=auto file=spec` and `- Breakdown: clean`, and say `Approved automatically: the plan stays inside the approved breakdown.` Write no product notes (Step 5b).
4. **Drift, or another check failed:** change nothing. Add a `progress.md` entry for `/approve` that copies every `drift:` line and names every other failed check, with `- Stats: gate=held file=spec`, and end your reply with one line: `Needs you: <the drift or failed checks, in a few words>.` The engineer reviews it in Workshop and approves it themselves.

## Step 1: Find the work folder

- If `$1` starts with `scope-`, the folder is `.work/$1/`. If it does not exist, list the `.work/scope-*` folders and stop. Otherwise go to Step 2.
- If `$1` starts with `refine-`, the folder is `.work/$1/` and the file is `refine.md`. If either does not exist, list the `.work/refine-*` folders and stop. Otherwise go to Step 2.
- List `.work/` and find the folder that starts with `$1-`. If there is none, or more than one, stop and say so.
- If `paused.md` contains `Status: PAUSED`, stop and tell the engineer to run `/resume $1` first.
- For a TSD, tell the engineer to use `/publish tsd-<name>` instead and stop.

## Step 2: Pick the file

- If the engineer named `spec`, `plan`, `bug`, `quick`, `stories`, or `milestones`, use that file (`spec.md`, `plan.md`, `bug.md`, `quick.md`, `stories.md`, or `milestones.md`).
- For a `refine-` folder, use `refine.md`.
- For a `scope-` folder, use the first match: `stories.md` if it says `Status: DRAFT`, otherwise `milestones.md` if it says `Status: DRAFT`. If neither, reply with the Status line of each that exists, and stop. Approving `stories.md` approves `epics.md` with it.
- For a work item, use the first match:

| Condition | File |
|---|---|
| `spec.md` exists and says `Status: DRAFT` | `spec.md` |
| `plan.md` exists and says `Status: DRAFT` | `plan.md` |
| `bug.md` exists and says `Status: DRAFT` | `bug.md` |
| `quick.md` exists and says `Status: DRAFT` | `quick.md` |

- If the file does not exist, or there is no match, reply with the Status line of each of `spec.md`, `plan.md`, `bug.md`, and `quick.md` that exists, and stop.
- If the file already says `Status: APPROVED`, say so, give the next command from Step 6, and stop.
- **The feature lane has one gate.** When the file is `spec.md` and `plan.md` exists as a draft, approve both: every step below runs for `spec.md`, then for `plan.md`. If `tasks.md` is missing, say so and stop: suggest `/tasks $1` first.
- To approve `plan.md` on its own, `spec.md` must already say `Status: APPROVED`. If not, approve `spec.md` with it (above).
- To approve `milestones.md`, `stories.md` must already say `Status: APPROVED`. If not, stop and suggest `/approve $1 stories`.

## Step 2b: Show what is being approved

Before anything changes, show the engineer three lines, from the file (and `plan.md` and `tasks.md` when they are approved with it):

```
Approving: <file(s)> for <id> <title>
Covers: <number of acceptance criteria>, <number of tasks if tasks.md exists>, <number of assumptions>
Watch: <the riskiest assumption or open point in one line, or "nothing open">
```

Then go on. Running `/approve` is the approval; do not ask again unless Step 4 finds open questions.

## Step 3: Check whether the draft was edited

Do this before Step 4 changes anything. Run exactly this command, with the file from Step 2:

```
{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/work/Test-DraftHash.ps1" -Path "<folder>/<file>"
```

It prints one word: `unchanged` (approved as the agent wrote it), `edited` (the engineer changed it first) or `no-hash` (an older draft). Remember it for Step 6. It never blocks approval. If the script fails, use `no-hash` and go on.

## Step 4: Check open questions

- Read the file's "Open questions" section, if it has one. For `stories.md`, also read the one in `epics.md`.
- If it lists anything that is not marked `accepted risk`, show those lines and ask: "These questions are still open. Approve anyway and mark them as accepted risk? (Recommended: no. Answer them in the file, or re-run the command that wrote it.)" Wait.
  - If no, stop.
  - If yes, add ` (accepted risk)` to the end of each of those lines, in whichever file they are in.

## Step 5: Approve

- Change the line `Status: DRAFT` to `Status: APPROVED`. Apart from the marks added in Step 4, change nothing else in the file.
- Read the file again and confirm the line now says `Status: APPROVED`.

## Step 5b: Record decisions in the product note

The engineer's answers while drafting are facts worth keeping. Only for `spec.md` (with or without `plan.md`):

- Read the "Decisions made during clarification" table in `spec.md`. Skip it if it is empty or has only the template row.
- Keep a row only if its answer would still be true after the product's code was rewritten (a business rule, a scope call, why one way was picked over another: the split rule in `AGENTS.md`, Product notes). Skip rows about one codebase or only this work item.
- If the work matches a product in the repo map, write at most 3 of them to its product note's `Decisions` section, following `{{ENG_HOME}}/guides/product-notes.md`: `-Section Decisions -Source "<id>"`, one short line each, the decision and why. Skip one the note already says.
- If there is no product, product notes are not available, or nothing qualifies, skip this step without saying so. It never blocks approval.
- Name each line you wrote in Step 6.

## Step 6: Log and hand off

- Add a `progress.md` entry for `/approve` that names the file (one entry per file when the spec and plan are approved together), with a `- Stats: gate=<the word from Step 3> file=<spec, plan, bug, quick, stories, milestones or refine>` line. `/stats` uses it to show which gates you edit and which you approve as written.
- Tell the engineer the file is approved and the next command:

| Approved | Next |
|---|---|
| `spec.md` and `plan.md` together | Start a new session, then `/do-task $1 1` (in Workshop, approving starts the build on its own) |
| `spec.md` alone (no plan yet, an older item) | `/plan $1` |
| `plan.md` alone | `/tasks $1` if there is no `tasks.md`, otherwise start a new session, then `/do-task $1 1` |
| `bug.md` | Start a new session, then `/do-task $1 1` |
| `quick.md` | Start a new session, then `/do-task $1 1` |
| `stories.md` | `/slice $1` |
| `milestones.md` | `/backlog $1` (import file), `/backlog $1 ado`, or `/backlog $1 local` |
| `refine.md` | Publish it to ADO from Loom (Workshop), or paste its Description and Acceptance criteria into a new work item. Then `/start <id> feature` or `/handoff <id> <name>`. |
