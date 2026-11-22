---
description: "Turn the engineer's code review comments (Send back in Workshop) into fix tasks, answers and rules, so the build comes back as the next revision. Usage: /revise <id> [auto]"
agent: writer
---

Turn the code review comments on work item **$1** into fix tasks and answers. Mode: **$2**

Workshop runs this when the engineer clicks **Send back** in Loom's code review. If the mode above is `auto`, autopilot runs it and nobody is watching: ask nothing. Do not change any code: the fix tasks you write here are built next by `/do-task`, then `/review` and `/pr` run again.

## Step 1: Find the comments

- Find the folder in `.work/` that starts with `$1-`. Read `repos.md`, `tasks.md`, `review.md` and the gate file (`spec.md` and `plan.md`, `bug.md` or `quick.md`).
- Read the Factory settings in `{{ENG_HOME}}/guides/pipeline.md` (`taskFileCap`).
- For each folder `code-review/<repo>/` in the work folder, read `state.json`. Take every repo whose `status` is `revising`. Its comments are in `rev-<revision>.json` (the `revision` from `state.json`): `summary`, and `comments`, each with `id`, `path`, `side`, `startLine`, `endLine`, `quotedCode`, `type` (`must_fix`, `suggestion` or `question`), `body`, maybe `suggestedCode`, and maybe `rule: true`.
- If no repo is `revising`, or its `rev-<revision>-response.json` already exists, say `Nothing to revise for $1.` and stop.

## Step 2: Decide each comment

Read the code each comment points at (`<repo>/<path>`, in the repo's Path when `repos.md` has one) and decide:

| Type | Decision |
|---|---|
| `must_fix` | A fix task. Never declined. |
| `suggestion` | A fix task, unless it would break an acceptance criterion, a repo rule or a test that guards behavior. Then **declined**, with that reason in one sentence. |
| `question` | **Answered** in one or two sentences from the code, with the file and line. No task, unless the answer is "this is a bug": then it is a fix task too. |

The summary is a comment too: if it asks for a change, it gets a task; if it asks something, it gets an answer.

**Hold.** A fix needs the engineer when it would add a new package or dependency, add or change a database migration, change authentication or authorization code, or change a repo that is not in `repos.md`. Do not write a task for it. Write it under "Needs you" in Step 4.

## Step 3: Write the fix tasks

- Append one task per file group to the end of `tasks.md`, numbered after the last task, in the normal task format (`{{ENG_HOME}}/templates/tasks.md`): one repo, at most `taskFileCap` files, one verify command from the repo guide. Comments on the same file can share a task.
- Each task gets a `- From comment: <repo>/<comment id>` line per comment it covers, right under `- Repo:`. Its Steps quote what the engineer asked, and use `suggestedCode` as written when the comment has it.
- `Covers:` is the criteria the code serves, or `review` when none.
- Then move `pr.md` to `history/pr-<yyyy-mm-dd>-<n>.md` in the work folder (`<n>` = 1, 2, ... so nothing is overwritten), so `/pr` writes it again after the fixes. Leave `review.md` as it is: `/review` runs again because `tasks.md` changed.

## Step 4: Answer each comment

For each repo in Step 1, write `code-review/<repo>/rev-<revision>-response.json`: a JSON list with one entry per comment, in order:

```json
[{"commentId": "c1", "status": "fixed", "note": "Task 7: Check the total before the refund"},
 {"commentId": "c2", "status": "answered", "note": "orders/refund.ts:41 already returns early when the order is open."},
 {"commentId": "c3", "status": "declined", "note": "Keeping the guard: AC-2 needs the 404."}]
```

- A comment with a fix task: `fixed`, with `Task <n>: <title>`. Workshop shows it once the build is back at Ready, after `/review` checked the fix.
- `answered` and `declined` notes are one or two plain sentences.
- A comment on hold: `declined`, with `Needs you: <why>`.

Then write `revise.md` in the work folder:

```markdown
# Revise: <id> revision <revision>

- Status: <READY | HOLD>
- Repos: <repo> (revision <n>), ...

| Comment | Type | Decision | Note |
|---|---|---|---|
| <repo>/<id> | must_fix | Task 7 | <task title> |

## Needs you

- <comment, and why it needs the engineer, or "None">

## Rules

- <the rule, and where it was saved, or "None">
```

`Status: HOLD` when anything is under "Needs you", else `READY`. Workshop reads it: HOLD stops autopilot for the engineer.

## Step 5: Save the rules

For each comment with `rule: true`, the engineer wants it remembered for this repo, the way `/memory <repo>` remembers a rule. Do not ask: the engineer worded it in the comment.

1. Write it as one short instruction in the engineer's words (for example `Return 404, not 400, when an order is missing.`). Never save secrets or personal data.
2. The repo guide is `<repo>/AGENTS.local.md` if it exists. Otherwise `<repo>/AGENTS.md`, but only when `git -C <repo> ls-files AGENTS.md` prints nothing; if it prints `AGENTS.md`, the file is committed and belongs to the team: do not write it, and note `Not saved: <repo>/AGENTS.md is committed` under "Rules".
3. Skip it if a line in the guide's `## Remembered` section already says the same thing. Otherwise add `- <rule> (<yyyy-mm-dd>)` as the last line of that section (add the section at the end of the file if there is none). Change nothing else.
4. Log it for review in Folio: `{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/notes/Set-ProductNote.ps1" -Note tandem/changes.md -Line "<repo> repo guide, Remembered: <rule>" -Source "/revise"`. If it says notes are not available, skip it.

List each rule and where it went under "Rules".

## Step 6: Hand off

- Add a `progress.md` entry for `/revise` with `- Stats: comments=<n> tasks=<n> answered=<n> declined=<n> held=<n> rules=<n>`.
- `auto`: end your reply with `Revise: READY <n> fix tasks` or `Needs you: <the held comments, in a few words>.` and stop.
- Not `auto`: summarize in 3 lines: the tasks added, the answers, anything held. Next: "Start a new session, then `/do-task $1 <first new task>`", or "Run `/review $1`" when there are no tasks.
