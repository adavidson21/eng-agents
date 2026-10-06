# Pipeline details

How each phase works, why it is shaped this way, and what to do when it goes wrong. The [README](../README.md) has the overview.

---

## Design choices for a slower, weaker model

| Choice | Why |
|---|---|
| Every command is a numbered list of steps | Weaker models follow explicit procedures far better than goals. |
| Every command re-reads files from disk | The model never has to remember anything across sessions. |
| Gates are a `Status:` line you edit | A gate is a fact on disk, not a judgment the model makes. The model is told never to change it. |
| One task per fresh session | Context stays small. Long sessions are where weaker models drift. |
| Agents have narrow permissions | A planner that cannot edit code cannot "helpfully" start coding. |
| "Stop after 3 failures" rule | Prevents long loops that burn time and make things worse. |
| Verify output must be pasted into `progress.md` | Stops "it should work now" claims without proof. |
| Templates for every artifact | Filling blanks is much more reliable than free-form writing. |

---

## Gates

| File | Created by | You approve by | Checked by |
|---|---|---|---|
| `spec.md` | `/spec` | Changing `Status: DRAFT` to `Status: APPROVED` | `/plan` |
| `plan.md` | `/plan` | Same | `/tasks`, `/do-task` (feature lane) |
| `bug.md` | `/bug` | Same | `/do-task` (bug lane) |

Before approving, it is normal to edit the file yourself. Fix a wrong acceptance criterion, delete a task, add a non-goal. The next command reads whatever is on disk.

To send a document back for rework, leave it as DRAFT, add your notes under "Open questions", and re-run the same command. It refines the existing draft instead of starting over.

---

## Phase notes

### /start

- Creates the folder name and slug deterministically in a script, so branch names are consistent.
- If ADO is unreachable, offline mode creates the folder from a title you paste, then you paste the details into `workitem.md`.
- Never switches a repo with uncommitted changes. It skips that repo and tells you.

### /spec

- Questions come one at a time with a recommended answer, so you can reply with just "A" or "yes".
- At most 6 questions. If the work item needs more, it is probably too big. Consider splitting it in ADO.

### /plan

- Each repo section names a "pattern to follow": a real existing file that does something similar. This is the single most effective way to get consistent code from a weaker model.
- The test plan maps every acceptance criterion to a test before any code exists.

### /tasks

- Tasks are capped at 3 files and one repo. If a task looks big when you skim, split it by hand before starting.
- The coverage table proves every acceptance criterion has a task.

### /do-task

- Always in a new session (`/new`). The command reads everything it needs from disk.
- .NET is strict TDD: the failing run AND the passing run are both pasted into `progress.md`. If the "failing" run passed, the test is not testing the change.
- Commits only the files it changed, with a short summary message. You approve each commit.

### /review

- Pass 1 (spec) and pass 2 (quality) are kept separate. Mixing them makes weaker models skip spec checks in favor of style comments.
- Findings only become tasks when you accept them. Then it is back to `/do-task` and another `/review`.

### /pr

- Short on purpose. Title under 70 characters, a sentence or two, up to 4 bullets, one testing line, the work item link.
- Never pushes. You push and open the PR.

---

## Lanes in practice

**Feature:** the full pipeline. Use it for anything with new behavior or more than 3 files of change.

**Bug:** skips spec, plan, and tasks phases. `/bug` writes both `bug.md` and a short `tasks.md`. Task 1 is always a test that fails because of the bug. If the root cause confidence is Low, the command stops and points you to `/spike`.

**Spike:** read-only. Use when you do not know enough to write a spec. The output (`findings.md`) is a good input to a later `/spec`.

**Docs:** `/docs` writes, `/check-docs` fact-checks in a separate session with the reviewer agent. The writer saves a sources list so the check is fast.

---

## Shared repos

- The repo map in the workspace `AGENTS.md` says which repos are shared and how others reference them (relative paths).
- `repos.md` lists shared repos first. Tasks in shared repos come first.
- When a shared repo changes, `/review` runs tests in every repo listed in `repos.md`. If you know another consumer could break, add it to `repos.md` so its tests run too.
- Need the shared repo on two branches at once? Use `git worktree add` (see README). Remember relative-path consumers still point at the main clone.

---

## Scripting the pipeline (opencode run)

The pipeline is designed for the interactive opencode window. If you script it with `opencode run "/spec 12345" ...`, two things differ (observed in testing):

- Slash commands may not be expanded. The model receives the literal text `/spec 12345` and has to find and read the command file itself.
- The interactive question tool is not available, so clarifying questions come back as plain text.

Stick to the interactive window for real work, especially with a weaker model.

## Recovering from problems

| Situation | What to do |
|---|---|
| A session went off the rails | Close it. Start a new session. Run `/status <id>` to see where things stand. Nothing is lost; state is on disk. |
| A task is marked done but is wrong | Uncheck it in `tasks.md` (`[x]` back to `[ ]`), revert the commit if needed (`git -C <repo> revert <sha>`, run by you), and re-run `/do-task`. |
| A task keeps failing | Read the blocked entry in `progress.md`. Usually the task is too big or the pattern file is wrong. Split the task or fix the plan. |
| The plan was wrong after tasks started | Edit `plan.md` and `tasks.md` by hand. Add new tasks at the end. Do not renumber finished tasks. |
| Work item scope changed | Update `workitem.md`, set `spec.md` back to DRAFT, re-run `/spec`. Then re-plan. |
| You want to abandon an item | Delete its `.work` folder and its branches. |
