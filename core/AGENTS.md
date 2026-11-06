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
- **Write:** when you confirm a product fact that is missing from the note or contradicts it, and it would help the next person working on this product, change the note with:
  `{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/notes/Set-ProductNote.ps1" -Product "<product name>" -Line "<the fact>" -Source "<PR, work item or file>" [-Section <section>] [-Replace "<text of the wrong line>"]`
  - One fact per call, one short line, only facts you saw in code, a work item, a PR or from the engineer. Never guesses, plans, to-dos or session notes.
  - If a line already covers the subject, replace that line (`-Replace`) instead of adding a second. When a line is wrong, replace it; never keep both.
  - Default section is `Remembered`. Use `Business rules`, `Gotchas`, `People` or `Decisions` when the fact clearly belongs there.
  - Never edit product notes with any other tool: the script keeps the earlier version in Notes' history and marks the note "Changed by Tandem" for the engineer to review.
  - If the script says the note is over budget, propose a tidy to the engineer instead of adding more.
  - List every product note change in your reply: the note, the section, and the line before and after.
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
| `progress.md` | Append-only log. Add an entry after every command. Never delete entries. |
| `review.md` | Review findings and verdict. |
| `pr.md` | PR title and description. |
| `bug.md` | Bug lane analysis. Has a `Status:` line. |
| `findings.md` | Spike results. |
| `paused.md` | Where a paused item stands and how to pick it up. Has a `Status:` line (`PAUSED` or `RESUMED`). |

Work that is not defined yet is scoped first, in `.work/scope-<name>/`, before it becomes work items:

| File | Purpose |
|---|---|
| `epics.md` | The epic (a product version), its MVP features, and what waits. Written by `/scope`. |
| `stories.md` | User stories with Gherkin acceptance criteria. Has a `Status:` line; approving it approves `epics.md` too. |
| `milestones.md` | Features and stories in build order, each story mapped to real files. Has a `Status:` line. Written by `/slice`. |
| `backlog.csv`, `published.md` | Written by `/backlog`: the ADO import file, or the ADO or local ids that were created. |

A first-pass review of someone else's pull request lives in `.work/pr-<id>/` (written by `/pr-review`). It is not pipeline state and has no gates:

| File | Purpose |
|---|---|
| `context.md` | The PR: repo folder, branches, source commit, the exact `git` commands to read it, changed files, description, linked work items. Written by `Get-PullRequest.ps1`. |
| `threads.md` | Comments already on the PR. |
| `review.md` | Draft comments for the engineer to post. Has a `Reviewed commit:` line. Older reviews move to `history/`. |

`.work/runway.md` is the end-of-day note written by `/shutdown`. It is not pipeline state; read the files above for that.

`.work/dashboard.html` is written by `/dashboard static`, and `.work/_dashboard/` belongs to Dispatch (Workshop's opencode connector). Never edit them and never read them for pipeline state; read the files above instead.

**Gates.** A file with `Status: APPROVED` was approved by the engineer. The engineer approves by running `/approve <id>` (specs, plans, bug analyses), `/approve scope-<name>` (stories, milestones) or `/publish <folder>` (finished documents such as a TSD), or by editing the line. Only those two commands may change a Status line to `APPROVED`, and only when the engineer runs them. In every other command, you never do.

**Paused items.** If `paused.md` contains `Status: PAUSED`, the item is on hold. Do not run any other pipeline command on it except `/status` and `/resume`. Tell the engineer to run `/resume <id>` first.

Templates for these files are in `{{ENG_HOME}}/templates/`. Always start a new file from its template.

## Conventions

| Item | Value |
|---|---|
| Base branch | `main` |
| Feature branch | `dev/feature/<id>-<short-name>` |
| Bug branch | `dev/bug/<id>-<short-name>` |
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

| Code | Framework | Rule |
|---|---|---|
| .NET | xUnit | **Strict TDD.** 1) Write the test. 2) Run it and confirm it FAILS for the expected reason. 3) Write the code. 4) Run it and confirm it PASSES. Mock dependencies. Do not use a real database. |
| Angular | The repo's existing unit test runner | Tests are required. Order is flexible. Run headless, single run (no watch mode). |
| Playwright | Playwright | Tests are required. Order is flexible. Mock every API call with `page.route`. Never call a real environment. Use the repo's existing mock helpers if the repo `AGENTS.md` lists any. |

A task is **not done** until its verify command passes and the output is recorded in `progress.md`.
