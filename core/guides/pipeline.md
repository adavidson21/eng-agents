# Pipeline files, gates and conventions

Read by every command that reads or writes `.work/` (the Pipeline commands section of `AGENTS.md` points here). Chat, hub, people prep and PR review do not read it.

## Pipeline files

Each work item has a folder `.work/<id>-<name>/`. Find it by listing `.work/` and matching the folder that starts with `<id>-`. If there is no match or more than one, stop and ask.

| File | Purpose |
|---|---|
| `workitem.md` | The work item text. Source of the requirement. |
| `brief.md` | A short context brief for the engineer, written by `/start --brief`. A help to read, not pipeline state. |
| `repos.md` | Lane, repos involved, branch per repo, order. |
| `spec.md` | What to build. Has a `Status:` line. |
| `plan.md` | How to build it. Has a `Status:` line. |
| `tasks.md` | Numbered tasks with checkboxes and verify commands. |
| `progress.md` | Append-only log. Add an entry after every command. Never delete entries. When a command asks for a `- Stats:` line, write it exactly as asked (`key=value` pairs); `/stats` reads it. |
| `baseline.md` | Unit test results per repo right after `/start` made the branches, before any change. `/do-task` uses it to tell old test failures from new ones. |
| `review.md` | Review findings (each with a category) and verdict. Earlier rounds are copied to `history/review-<date>-<n>.md` first. |
| `retro.md` | Lessons from the item and proposed `/memory` rules, written by `/retro`. Not pipeline state. |
| `pr.md` | PR title and description. |
| `bug.md` | Bug lane analysis. Has a `Status:` line. |
| `quick.md` | Quick lane: one combined spec and plan for small work (tasks stay in `tasks.md`). Has a `Status:` line. |
| `first-look.md` | A spike's fast first answer (question mode) or first read of a log (log mode), written before the deep work. Loom shows it on the card. |
| `findings.md` | Spike results, with `### For business`, `### For engineering` and `### For leadership` blocks. `brief.html` next to it is the shareable export (`Export-Brief.ps1`); never edit it, re-export instead. |
| `paused.md` | Where a paused item stands and how to pick it up. Has a `Status:` line (`PAUSED` or `RESUMED`). |
| `tests/` | Regression suite results, `results-<name>.json` (`before` at `/start`, `after` at `/review` and `/pr`), written only by `Test-Suite.ps1`. |
| `ui/` | UI check screenshots and `results-<name>.json`, written only by `Test-Ui.ps1` (`before` at `/start`, `after` at `/review`). |

Other `.work` folders are described by the commands that write them: `scope-<name>/` (`/scope`, `/slice`, `/backlog`), `pr-<id>/` (`/pr-review`), `triage-`, `shape-` and `refine-` folders, `_retro/` (`/retro --since`) and `runway.md` (`/shutdown`). `.work/observations.md` holds what agents noticed out of scope (core rule 5); only `Add-Observation.ps1` writes it. `.work/gaps.md` holds knowledge an agent was missing (core rule 3); only `Add-Gap.ps1` and `Close-Gap.ps1` write it. `.work/factory.json` holds the factory settings below; Workshop writes it, never edit it.

**Where the work happens.** A repo row in `repos.md` may have a **Path** (a git worktree, `.worktrees/<work folder>/<repo>`), made by `/start` when the repo folder was busy. When it has one, every git, build, test and file command for that repo runs in its Path, not in the repo folder: wherever a command says `git -C <repo>` or a file in `<repo>`, use the Path. Read the repo guide from the repo folder (`AGENTS.local.md` is not committed, so the worktree may not have it). A worktree shares the repo's branches, so the branch exists in both. A shared repo that other repos use by relative path is still read from its main folder. Empty or no Path column: the repo folder. `.work/dashboard.html` and `.work/_dashboard/` belong to the static dashboard and to Loom: never edit them and never read them for pipeline state.

**Gates.** A file with `Status: APPROVED` was approved by the engineer. The feature lane has one gate: `/spec` drafts `spec.md`, `plan.md` and `tasks.md`, and one `/approve` approves `spec.md` and `plan.md` together. The engineer approves by running `/approve <id>` (specs, plans, bug analyses, quick plans), `/approve scope-<name>` (stories, milestones) or `/publish <folder>` (finished documents such as a TSD), or by editing the line. Only those two commands may change a Status line to `APPROVED`, and only when the engineer runs them. In every other command, you never do. The one exception is review by exception for the quick lane: `/approve <id> quick auto`, which Workshop's autopilot runs only when its Quick change hands-off setting is on, approves `quick.md` only when it is clean and otherwise leaves it for the engineer. After the plan gate, a build runs on its own up to the PR text (tasks, review, fix tasks, UI checks, `pr.md`); the engineer's second and last gate is publishing the PR from Workshop. A gate file also has a `Draft-hash:` line under `Status:`, written by `Set-DraftHash.ps1` when a command finishes the draft; never write or change that line yourself.

**Paused items.** If `paused.md` contains `Status: PAUSED`, the item is on hold. Do not run any other pipeline command on it except `/status` and `/resume`. Tell the engineer to run `/resume <id>` first.

Templates for these files are in `{{ENG_HOME}}/templates/`. Always start a new file from its template.

## Factory settings

Workshop's Settings, Factory writes `.work/factory.json`. Read it once per command with `Get-Content .work/factory.json`. A missing file, a missing key or a value out of range means the default:

| Key | Default | Means |
|---|---|---|
| `taskFileCap` | 6 | A task changes at most this many files. Test files do not count. |
| `quickTasks` | 3 | The quick lane allows at most this many tasks. |
| `retries` | 3 | Core rule 6: tries at the same step before you stop. |
| `autoFix` | `should-fix` | `/review auto` turns Blockers into fix tasks, and with `should-fix` also Should fix findings. `blockers`: Blockers only. Nits are never fix tasks. |
| `reviewRounds` | 2 | How many reviews autopilot runs before a not-READY review waits for the engineer. Rounds after the first read only what changed since the last review. |
| `uiChecks` | true | Run UI checks (`Test-Ui.ps1`) when a change touches UI files and the repo guide has a UI checks table. |
| `regression` | true | Run the repo's whole regression suite (`Test-Suite.ps1`) at `/start` (before), `/review` and `/pr`, when the repo guide has a Regression tests table. |
| `worktrees` | `always` | `/start` puts every repo of a build in its own worktree. `busy`: only when the repo folder is busy. |

## Catch up with the base

`/review` and `/pr` bring each repo's branch up to date first, so the PR merges cleanly. For each repo in `repos.md` (in its Path when it has one) whose Base starts with `origin/`:

1. `git -C <repo> fetch origin <base without origin/>`. If it fails (offline, no access), write `rebase=skipped` and go on.
2. `git -C <repo> rebase <base>`. If it ends cleanly, go on (write `rebase=clean`, or `rebase=none` when nothing new was on the base).
3. If it stops on a conflict: list the conflicting files with `git -C <repo> diff --name-only --diff-filter=U`, then `git -C <repo> rebase --abort` so the branch is as it was. Write `rebase=conflict`. `/review` turns it into a `Blocker` finding (category `conflict`, location the files); its fix task is "Rebase on `<base>` and resolve the conflicts in <files>", verify the repo's All unit tests command.

Never force anything, never push, never resolve a conflict outside a fix task.

## Who links to ADO

A work item is **linked** to an ADO work item when `workitem.md` has a `- ADO item: <number>` line, or when its id is a number and `workitem.md` has no `- ADO item: unlinked` line. Otherwise it is **local** (id `L<n>`, or a number that was unlinked). Only a linked item gets `AB#<number>` in commits and PR text (the number from the `ADO item:` line, else the id); a local item gets its id. Never post to, update or read ADO for a local item. Linking and unlinking happen in Workshop; never write the `ADO item:` line yourself.

## Stories from an approved breakdown

`/backlog scope-<name> local` makes one local item per story (Core 4.10.0). Its `workitem.md` says where it came from, so Workshop can build the epic hands-off, in order:

| Line | Meaning |
|---|---|
| `- Epic: scope-<name>` | The scope folder (the epic) it came from |
| `- Story: <n.m>` | Its number in `milestones.md` |
| `- Depends on: <local ids, or none>` | Items it waits for: Workshop builds it after their PR text is ready |
| `- Repos:`, `- Areas:` | The repos and folders the approved breakdown says it changes |
| `- Breakdown: approved <date>` | The engineer approved the breakdown, so the story's plan needs them only when it drifts from it |

Autopilot runs `/start <id> feature auto`, `/spec <id> auto`, then `/approve <id> spec auto`, which approves the plan only when `scripts/work/Test-StoryDrift.ps1` prints `CLEAN`: no task over the file cap, no new dependency, no migration, no auth or security code, nothing outside the story's areas and repos. Any drift holds the plan for the engineer. Every story still stops at Publish.

## Where a build is (step.md)

`/do-task` and `/review` record the station a build is at in `step.md` with `scripts/work/Set-Step.ps1` (Core 4.12.0): one line, `- Step: <build | test | ui | review | fix> | <ISO time>`, replaced each time. Workshop's Loom puts the item at that station on its floor. Never write it by hand; nothing else reads it.

## Onboarding a product

`/onboard-product <product>` (Core 4.10.0) gets a product ready for its first build without asking anything: it drafts missing repo guides, drafts the product note, logs what it could not find as gaps (Teach), and creates a trial run, a local Quick change with `- Trial: <product>` that adds one test. It records each step in `.work/_onboarding/<product>.md` with `scripts/work/Set-Onboarding.ps1` (`- Scan:`, `- Trial:`, `- Live:`). Workshop's Loom shows the steps; the product is live when its trial run reaches Ready to publish.

## Backfilled regression tests

`/cover <product> [area]` (Core 4.11.0) makes one local Quick change per UI repo, with `- Coverage: <product>` in `workitem.md`, that adds end-to-end tests for what pages do today and changes no product code. Workshop builds it hands-off like a trial run; you publish its PR. From then on every build runs those tests (`Test-Suite.ps1`).

## Conventions

| Item | Value |
|---|---|
| Base branch | `main` |
| Feature branch | `dev/feature/<id>-<short-name>` |
| Bug branch | `dev/bug/<id>-<short-name>` |
| Quick lane branch | `dev/feature/<id>-<short-name>` (a quick item is a small feature) |
| `<short-name>` | Same as the `.work` folder name after `<id>-` |
| Commit message | A short summary in plain words. No prefix, no work item number. Example: `Add retry to export job` |
| Task size cap | A task changes at most `taskFileCap` files (Factory settings, default **6**); test files do not count |

