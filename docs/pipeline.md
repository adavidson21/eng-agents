# Pipeline

How each phase works, why it is shaped this way, and what to do when it goes wrong. Daily commands are in the [README](../README.md).

```
/start <id> feature    fetch work item, create .work/<id>-<name>/, confirm repos, create branches
/spec <id>             questions one at a time, then spec.md        GATE: approve spec.md
/plan <id>             files per repo, pattern to follow, test plan GATE: approve plan.md
/tasks <id>            small tasks, each with a verify command      skim task sizes
/do-task <id> <n>      one task per fresh session, TDD, commit      repeat
/review <id>           pass 1 spec, pass 2 quality                  accept findings as tasks
/pr <id>               short title and description per repo
You push and open the PR. Your normal review and CI/CD take it to production.
```

## Design choices

Built for a slower model that needs explicit procedures.

| Choice | Why |
|---|---|
| Every command is a numbered list of steps | Weaker models follow procedures far better than goals. |
| Every command re-reads files from disk | Nothing has to be remembered across sessions. |
| Gates are a `Status:` line you edit | Approval is a fact on disk, not a judgment the model makes. |
| One task per fresh session | Context stays small. Long sessions are where weaker models drift. |
| Agents have narrow permissions | A planner that cannot edit code cannot start coding. |
| Stop after 3 failures | Prevents long loops that make things worse. |
| Verify output is pasted into `progress.md` | No "it should work now" without proof. |
| A template for every file | Filling blanks is more reliable than free-form writing. |

## Gates

| File | Created by | Approve by | Checked by |
|---|---|---|---|
| `spec.md` | `/spec` | Changing `Status: DRAFT` to `Status: APPROVED` | `/plan` |
| `plan.md` | `/plan` | Same | `/tasks`, `/do-task` (feature lane) |
| `bug.md` | `/bug` | Same | `/do-task` (bug lane) |

Agents never change a `Status:` line to `APPROVED`. Edit the file freely before approving; the next command reads whatever is on disk. To send a draft back, leave it as DRAFT, add notes under "Open questions", and re-run the same command. It refines the draft instead of starting over.

## Lanes

| Lane | Use when | Flow |
|---|---|---|
| Feature | New behavior, or more than 3 files of change | Full pipeline |
| Bug | A defect with a reproducible symptom | `/start` → `/bug` → approve → `/do-task` (repeat) → `/review` → `/pr` |
| Spike | You do not know enough to write a spec | `/spike` writes `findings.md`. No code changes. Good input to a later `/spec`. |
| Docs | Writing or updating documentation | `/docs` (writer) → new session → `/check-docs` (reviewer fact-checks every claim) |

Bug lane rules:

- `/bug` writes `bug.md` (symptom, code path, root cause with confidence) and a `tasks.md` with **at most 3 tasks**.
- Task 1 is always a test that fails because of the bug.
- If root-cause confidence is Low, `/bug` stops and points you to `/spike`.
- If the fix needs more than 3 tasks, it moves to the feature lane (`/spec`).

## Phase notes

**/start**
- A script creates the folder name and slug, so branch names are consistent: `dev/<lane>/<id>-<short-name>`.
- If ADO is unreachable, offline mode creates the folder from a title you paste; then you paste the details into `workitem.md`.
- Proposes repos from the repo map and asks you to confirm.
- Never switches a repo with uncommitted changes (skips it). Asks before switching a repo that is on another item's `dev/` branch.

**/spec**
- Questions come one at a time with options and a recommendation, so you can reply "A" or "yes".
- At most 6 questions. If the item needs more, consider splitting it in ADO.

**/plan**
- Each repo section names a "pattern to follow": a real file that does something similar. This is the most effective way to get consistent code from a weaker model.
- The test plan maps every acceptance criterion to a test before any code exists.

**/tasks**
- Each task touches one repo and at most 3 files (or your configured cap). Split big-looking tasks by hand before starting.
- A coverage table proves every acceptance criterion has a task.

**/do-task**
- Always in a new session. Checks the gate, the branch, and that the repo has no unrelated changes.
- .NET is strict TDD: both the failing and the passing run go in `progress.md`. If the "failing" run passed, the test does not test the change.
- Stages only the task's files and commits with a short summary. You approve the commit.

**/review**
- Runs every repo's unit tests, then reads the diff against `origin/main`.
- Pass 1 (spec) and pass 2 (quality) are separate, so spec checks are not skipped in favor of style comments.
- Verdict is `READY` only if tests pass, every criterion is `Met`, and there are no Blockers. Findings you accept are appended to `tasks.md`.

**/pr**
- Title under 70 characters, one or two sentences, up to 4 bullets, a testing line, the work item link.
- Never pushes. You push each branch and open the PR.

## Shared repos

- The repo map says which repos are shared and how others reference them (relative paths).
- `repos.md`, the plan, and tasks put shared repos first. `/review` runs tests in every repo in `repos.md`; add any other consumer that could break so its tests run too.
- Need a shared repo on two branches at once? Use a worktree instead of a second clone (see [reference](reference.md#shared-repos)).

## Pausing and resuming

`/pause <id> [reason]` when you drop an item for a while.

- Writes `paused.md`: phase, tasks done, the task in progress and what is left of it, what it is waiting on, and the next command.
- For uncommitted changes it asks one question: commit as `WIP <id>: ...` (frees the repo) or leave them. Nothing is stashed or discarded.
- While paused, agents refuse other pipeline commands on the item except `/status` and `/resume`.

`/resume <id>` switches each repo back to the item's branch (asking first if a repo is on another item's branch), warns if `main` has moved, marks `paused.md` as `RESUMED`, and gives the next command. A half-done task continues from the "Work in progress" notes. Squash WIP commits when merging if your team prefers clean history.

## Recovering from problems

| Situation | What to do |
|---|---|
| A session went off the rails | Close it, start a new one, run `/status <id>`. State is on disk. |
| A task is marked done but is wrong | Uncheck it in `tasks.md`, revert the commit yourself if needed (`git -C <repo> revert <sha>`), re-run `/do-task`. |
| A task keeps failing | Read the blocked entry in `progress.md`. Usually the task is too big or the pattern file is wrong. Split the task or fix the plan. |
| The plan was wrong after tasks started | Edit `plan.md` and `tasks.md` by hand. Add new tasks at the end; do not renumber finished ones. |
| Work item scope changed | Update `workitem.md`, set `spec.md` back to DRAFT, re-run `/spec`, then re-plan. |
| Abandon an item | Delete its `.work` folder and its branches yourself. |

## Tuning when the model struggles

| Symptom | Fix |
|---|---|
| Task fails or wanders | Split it into smaller tasks. |
| Ignores a convention | Put the rule in the repo `AGENTS.md` or the overlay. Rules said in chat do not carry over. |
| Claims done without proof | Verify output must be in `progress.md`. Re-run `/do-task` and point at the missing evidence. |
| Asks too many questions | Answer them in `spec.md` directly, then re-run the next command. |
| Plans touch the wrong repo or order | Fix the repo map. |

## Scripting with `opencode run`

Use the interactive window for real work. In testing, `opencode run "/spec 12345"` did not always expand the slash command (the model had to find the command file itself), and the question tool was unavailable, so questions came back as plain text.
