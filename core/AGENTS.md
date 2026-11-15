## How this file works

This file has sections in order: Core, then Personal, then Company. If two sections disagree, **the later section wins**.

## Who you are working with

You are working with an engineer who uses a step-by-step pipeline. Each step is a slash command. Each command tells you exactly what to read, what to do, and what to write. Follow the command's steps in order. Do not skip ahead to a later step or a later command.

## Core rules

1. **Do one thing at a time.** Finish the current step before starting the next.
2. **Files are the memory.** Pipeline state lives in `.work/<id>-<name>/`. Read the files the command names before acting. Never rely on what you remember from earlier in the conversation.
3. **Ask only what changes the outcome.** Before asking, check the files, the code and the work folder's earlier decisions; never ask what they already answer or what was already decided. Ask only when a wrong guess would change what gets built or would be hard to undo. Otherwise take your recommended answer, write it under "Assumptions" (or the file's Decisions table) and keep going. When you do ask: ONE question at a time, 2 to 4 options, your recommendation first. A command asks at most 3 questions in total unless it sets a lower limit. When you hit the limit, stop asking and list the rest as assumptions the engineer can change at review.
4. **Prove it.** Never say something works without running the command that proves it and showing the output.
5. **Stay in scope.** Only change what the current task says. If you find something else that needs fixing, write it down in `progress.md` under "Notes" and keep going.
6. **Stop after 3 failed attempts.** If the same command fails 3 times, stop. Write what you tried in `progress.md` and ask the engineer for help.
7. **Never guess paths, commands, or names.** Look them up in the repo's `AGENTS.md` or in the code.
8. **Simple, but built to maintain.** Build or plan the smallest thing that meets the acceptance criteria and is easy to change later. Both halves matter:
   - **Do:** put values likely to change (limits, timeouts, URLs, labels, feature switches) in the repo's existing config or constants, not inline. Follow the repo's existing extension points and patterns. Keep clear seams (one job per function or module) so the next change is an edit, not a rewrite.
   - **Don't:** build speculative features, options nobody asked for, plugin systems, or new frameworks or layers for a single use. Reuse what the code already has.
   - If a bigger design seems worth it, write it in one line under "Notes" (or V2 / Icebox) and keep going with the simple version.

## Workspace layout

- You are started from the **workspace root**. It is not a git repo.
- Each repo is a folder directly inside the workspace root.
- The `AGENTS.md` in the workspace root is the **repo map**. It says what each repo does and how the repos depend on each other. It is loaded automatically.
- **Before you touch any repo, read its repo guide:** `<repo>/AGENTS.local.md` if it exists, otherwise `<repo>/AGENTS.md`. It is not loaded automatically. If neither exists, stop and tell the engineer to run `/onboard-repo <repo>` first. Everywhere these instructions say "the repo's `AGENTS.md`", they mean this repo guide.
- **Team guides.** If the repo guide has a "Team guides" table:
  - For each `link` row whose "Applies to" folder contains files you will read or change, read that file too. Committed `CLAUDE.md` files are not loaded automatically, because you start from the workspace root.
  - For each `copy` row, run `git -C <repo> log -1 --format=%h -- <file>`. If the hash is not the one in "Synced at", tell the engineer: "`<file>` changed since the repo guide copied it. Run `/onboard-repo <repo>` to refresh." Then continue.
  - If a team guide disagrees with the repo guide, follow the repo guide.
- If a repo map or repo guide contains `TODO(you)`, warn the engineer that it is incomplete, then continue carefully.
- Shared repos are used by other repos through **relative paths** (for example `../shared-repo/...`). A change in a shared repo affects every repo that references it. Change shared repos first.

## Memory

The engineer saves rules with `/memory`. Follow them like any other rule.

| Scope | Where it lives | Loaded |
|---|---|---|
| One repo | The `## Remembered` section of that repo's guide | When you read the repo guide |
| Every repo | `{{ENG_CONFIG}}/memory.md` | Automatically, in every session |
| One product | Its product note in Workshop's Notes app (see Product notes) | When you work on that product |

- A repo's `## Remembered` rule wins over a global memory rule.
- If the engineer says "remember this", "from now on", or "always do X here", suggest `/memory <rule>` (one repo), `/memory -global <rule>` (every repo) or `/memory -product <product> <fact>` (a product fact, written to the product note; see Product notes). Do not write memory files yourself unless running `/memory`.

## Product notes

Each product can have a **product note** in Workshop's Notes app: one Markdown file per product with what the code cannot tell you (business rules, gotchas, who to ask, why decisions were made). The engineer edits them in Notes; you read them and add to them.

- **Read:** after you match work to a product in the repo map, and before you plan, change, review or answer anything about it, run:
  `{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/notes/Get-ProductNote.ps1" -Product "<product name>"`
  Use the product's `Note:` line in the repo map if it has one (`-Note products/<slug>.md`). Read only the notes of the products the work touches, never all of them. If it says product notes are not available, or the note does not exist yet, go on without it.
- **What goes where (split rule):** if a fact would still be true after the product's code was rewritten (a business rule, a customer need, who owns what, why a decision was made), it belongs in the product note. If it is about one codebase (a build quirk, a pattern, a file to avoid), it belongs in that repo guide's `## Remembered`. Never write a fact in both.
- **Write:** when you confirm a product fact that is missing from the note or contradicts it, and it would help the next person, first read `{{ENG_HOME}}/guides/product-notes.md` and follow it exactly: only `Set-ProductNote.ps1`, one fact per call, and list every change in your reply.
- Agents that may not run scripts or write files (hub, pr-reviewer) only read product notes. pr-reviewer suggests product note lines in `review.md` instead of writing them.

## Pipeline files

Each work item has a folder `.work/<id>-<name>/`. Find it by listing `.work/` and matching the folder that starts with `<id>-`. If there is no match or more than one, stop and ask.

| File | Purpose |
|---|---|
| `workitem.md` | The work item text. Source of the requirement. |
| `brief.md` | A short context brief for the engineer, written by `/start` (not with `--cold`). A help to read, not pipeline state. |
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
| `findings.md` | Spike results, with `### For business`, `### For engineering` and `### For leadership` blocks. `brief.html` next to it is the shareable export (`Export-Brief.ps1`); never edit it, re-export instead. |
| `paused.md` | Where a paused item stands and how to pick it up. Has a `Status:` line (`PAUSED` or `RESUMED`). |

Other `.work` folders are described by the commands that write them: `scope-<name>/` (`/scope`, `/slice`, `/backlog`), `pr-<id>/` (`/pr-review`), `triage-`, `shape-` and `refine-` folders, `_retro/` (`/retro --since`) and `runway.md` (`/shutdown`). `.work/dashboard.html` and `.work/_dashboard/` belong to the static dashboard and to Dispatch: never edit them and never read them for pipeline state.

**Gates.** A file with `Status: APPROVED` was approved by the engineer. The engineer approves by running `/approve <id>` (specs, plans, bug analyses, quick plans), `/approve scope-<name>` (stories, milestones) or `/publish <folder>` (finished documents such as a TSD), or by editing the line. Only those two commands may change a Status line to `APPROVED`, and only when the engineer runs them. In every other command, you never do. A gate file also has a `Draft-hash:` line under `Status:`, written by `Set-DraftHash.ps1` when a command finishes the draft; never write or change that line yourself.

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

## Shell rules (PowerShell on Windows)

- Run **one command per call**. Do not chain commands with `&&` or `;`.
- For git, either set the working directory to the repo or use `git -C <repo> <command>`.
- Never start a long-running process yourself (for example `ng serve`, `dotnet run`, `npm start`). Tests that need a server must start it through their own config (for example Playwright `webServer`). If they do not, stop and ask.
- Run `git push` only when the engineer asks you to. Never run `git reset --hard`, `git clean`, or any database update or migration command against a real database.
- Never print, read, or write secrets, tokens, connection strings, or `.env` files.

## Testing rules

All tests must run locally with **no database, no real backend, and no shared environment**.

Each repo guide has a `Stack:` line (for example `Stack: dotnet, angular`). Before you plan, write, test or review code in a repo, read `{{ENG_HOME}}/stacks/<stack>.md` for each stack it names: its testing rules and review checklist. If the repo guide has no `Stack:` line, read every file in that folder except `README.md`, and tell the engineer once: "`<repo>`'s guide has no Stack line. Run `/onboard-repo <repo>` to add it."

A task is **not done** until its verify command passes and the output is recorded in `progress.md`.
