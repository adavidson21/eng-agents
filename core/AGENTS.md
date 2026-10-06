## How this file works

This file has sections in order: Core, then Personal, then Company. If two sections disagree, **the later section wins**.

## Who you are working with

You are working with an engineer who uses a step-by-step pipeline. Each step is a slash command. Each command tells you exactly what to read, what to do, and what to write. Follow the command's steps in order. Do not skip ahead to a later step or a later command.

## Core rules

1. **Do one thing at a time.** Finish the current step before starting the next.
2. **Files are the memory.** Pipeline state lives in `.work/<id>-<name>/`. Read the files the command names before acting. Never rely on what you remember from earlier in the conversation.
3. **Ask when unsure.** If something is unclear, missing, or contradicts a file, stop and ask ONE question. Offer your recommended answer.
4. **Prove it.** Never say something works without running the command that proves it and showing the output.
5. **Stay in scope.** Only change what the current task says. If you find something else that needs fixing, write it down in `progress.md` under "Notes" and keep going.
6. **Stop after 3 failed attempts.** If the same command fails 3 times, stop. Write what you tried in `progress.md` and ask the engineer for help.
7. **Never guess paths, commands, or names.** Look them up in the repo's `AGENTS.md` or in the code.

## Workspace layout

- You are started from the **workspace root**. It is not a git repo.
- Each repo is a folder directly inside the workspace root.
- The `AGENTS.md` in the workspace root is the **repo map**. It says what each repo does and how the repos depend on each other. It is loaded automatically.
- **Before you touch any repo, read `<repo>/AGENTS.md`.** It is not loaded automatically. If it does not exist, stop and tell the engineer to run `/onboard-repo <repo>` first.
- If a repo map or repo `AGENTS.md` contains `TODO(you)`, warn the engineer that it is incomplete, then continue carefully.
- Shared repos are used by other repos through **relative paths** (for example `../shared-repo/...`). A change in a shared repo affects every repo that references it. Change shared repos first.

## Pipeline files

Each work item has a folder `.work/<id>-<name>/`. Find it by listing `.work/` and matching the folder that starts with `<id>-`. If there is no match or more than one, stop and ask.

| File | Purpose |
|---|---|
| `workitem.md` | The work item text. Source of the requirement. |
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

**Gates.** A file with `Status: APPROVED` was approved by the engineer. Only the engineer changes a Status line to `APPROVED`. You never do.

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
- Never run `git push`, `git reset --hard`, `git clean`, or any database update or migration command against a real database.
- Never print, read, or write secrets, tokens, connection strings, or `.env` files.

## Testing rules

All tests must run locally with **no database, no real backend, and no shared environment**.

| Code | Framework | Rule |
|---|---|---|
| .NET | xUnit | **Strict TDD.** 1) Write the test. 2) Run it and confirm it FAILS for the expected reason. 3) Write the code. 4) Run it and confirm it PASSES. Mock dependencies. Do not use a real database. |
| Angular | The repo's existing unit test runner | Tests are required. Order is flexible. Run headless, single run (no watch mode). |
| Playwright | Playwright | Tests are required. Order is flexible. Mock every API call with `page.route`. Never call a real environment. Use the repo's existing mock helpers if the repo `AGENTS.md` lists any. |

A task is **not done** until its verify command passes and the output is recorded in `progress.md`.
