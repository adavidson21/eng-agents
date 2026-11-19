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

Other `.work` folders are described by the commands that write them: `scope-<name>/` (`/scope`, `/slice`, `/backlog`), `pr-<id>/` (`/pr-review`), `triage-`, `shape-` and `refine-` folders, `_retro/` (`/retro --since`) and `runway.md` (`/shutdown`). `.work/observations.md` holds what agents noticed out of scope (core rule 5); only `Add-Observation.ps1` writes it.

**Where the work happens.** A repo row in `repos.md` may have a **Path** (a git worktree, `.worktrees/<work folder>/<repo>`), made by `/start` when the repo folder was busy. When it has one, every git, build, test and file command for that repo runs in its Path, not in the repo folder: wherever a command says `git -C <repo>` or a file in `<repo>`, use the Path. Read the repo guide from the repo folder (`AGENTS.local.md` is not committed, so the worktree may not have it). A worktree shares the repo's branches, so the branch exists in both. A shared repo that other repos use by relative path is still read from its main folder. Empty or no Path column: the repo folder. `.work/dashboard.html` and `.work/_dashboard/` belong to the static dashboard and to Loom: never edit them and never read them for pipeline state.

**Gates.** A file with `Status: APPROVED` was approved by the engineer. The feature lane has one gate: `/spec` drafts `spec.md`, `plan.md` and `tasks.md`, and one `/approve` approves `spec.md` and `plan.md` together. The engineer approves by running `/approve <id>` (specs, plans, bug analyses, quick plans), `/approve scope-<name>` (stories, milestones) or `/publish <folder>` (finished documents such as a TSD), or by editing the line. Only those two commands may change a Status line to `APPROVED`, and only when the engineer runs them. In every other command, you never do. The one exception is review by exception for the quick lane: `/approve <id> quick auto`, which Workshop's autopilot runs only when its Quick change hands-off setting is on, approves `quick.md` only when it is clean and otherwise leaves it for the engineer. A gate file also has a `Draft-hash:` line under `Status:`, written by `Set-DraftHash.ps1` when a command finishes the draft; never write or change that line yourself.

**Paused items.** If `paused.md` contains `Status: PAUSED`, the item is on hold. Do not run any other pipeline command on it except `/status` and `/resume`. Tell the engineer to run `/resume <id>` first.

Templates for these files are in `{{ENG_HOME}}/templates/`. Always start a new file from its template.

## Conventions

| Item | Value |
|---|---|
| Base branch | `main` |
| Feature branch | `dev/feature/<id>-<short-name>` |
| Bug branch | `dev/bug/<id>-<short-name>` |
| Quick lane branch | `dev/feature/<id>-<short-name>` (a quick item is a small feature) |
| `<short-name>` | Same as the `.work` folder name after `<id>-` |
| Commit message | A short summary in plain words. No prefix, no work item number. Example: `Add retry to export job` |
| Task size cap | A task changes at most **3 files** |

