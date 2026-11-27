## How this file works

This file has sections in order: Core, then Personal, then Company. If two sections disagree, **the later section wins**.

## Who you are working with

You are working with an engineer who uses a step-by-step pipeline. Each step is a slash command. Each command tells you exactly what to read, what to do, and what to write. Follow the command's steps in order. Do not skip ahead to a later step or a later command.

## Core rules

1. **Do one thing at a time.** Finish the current step before starting the next.
2. **Files are the memory.** Pipeline state lives in `.work/<id>-<name>/`. Read the files the command names before acting. Never rely on what you remember from earlier in the conversation.
3. **Ask only what changes the outcome.** Before asking, check the files, the code and the work folder's earlier decisions; never ask what they already answer or what was already decided. Ask only when a wrong guess would change what gets built or would be hard to undo. Otherwise take your recommended answer, write it under "Assumptions" (or the file's Decisions table) and keep going. When you do ask: ONE question at a time, 2 to 4 options, your recommendation first. A command asks at most 3 questions in total unless it sets a lower limit. When you hit the limit, stop asking and list the rest as assumptions the engineer can change at review. **Missing knowledge** (a business rule, a term, which repo or process applies) that the files, code and `Get-Knowledge.ps1` do not answer: log it instead of asking, `{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/work/Add-Gap.ps1" -WorkRoot ".work" -Kind <fact|term|repo|process> -Product "<product, or ->" -Source "<work item id or command>" -Question "<one line>" -Assumed "<what you did instead, or ->"`. With a safe assumption, keep going; the engineer answers it once in Workshop (Teach) and it is never asked again. With no safe assumption (`-Assumed -`), stop the step after logging it. Agents that may not run scripts ask instead.
4. **Prove it.** Never say something works without running the command that proves it and showing the output.
5. **Stay in scope.** Only change what the current task says. If you find something else worth doing later (a bug, debt, missing docs or tests, an idea), log it and keep going, asking nothing: `{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/work/Add-Observation.ps1" -WorkRoot ".work" -Kind <bug|debt|docs|tests|idea> -Repo "<repo folder, or ->" -Source "<work item id or command>" -Text "<one line: what and where>"`. At most 3 per command, only things you saw, never guesses. It prints the id (`O<n>`); add `Noticed: O<n>` to the `progress.md` entry's Notes when there is one. Workshop's Builds shows them in its Inbox. Agents that may not run scripts write it under Notes instead.
6. **Stop after the retry limit.** If the same step fails `retries` times (Factory settings in the pipeline guide, default 3), even when you change the fix between tries, stop. Write what you tried and the last error in `progress.md`, then ask the engineer for help (in `auto` mode, stop without asking: autopilot gives the step one fresh session with your notes before it waits).
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

The engineer saves rules with `/memory`. Follow them like any other rule. One repo's rules are in the `## Remembered` section of its repo guide; rules for every repo are in `{{ENG_CONFIG}}/memory.md` (loaded in every session); product and team facts are in Notes (see Product notes). A repo's `## Remembered` rule wins over a global one.

If the engineer says "remember this", "from now on", or "always do X here", suggest `/memory <rule>` (one repo), `/memory -global <rule>` (every repo) or `/product-notes add <product> <fact>` (a product fact; the split rule under Product notes decides which). Do not write memory files yourself unless running `/memory` (or `/retro` saving the rules the engineer ticked).

## Product notes

Workshop keeps what the code cannot tell you in one place each: products, the glossary and owners in Workshop's Settings, and per product a **product note** in Workshop's Notes app (business rules, gotchas, who else to ask, why decisions were made), plus one **team handbook** (sprints, work item states, pull requests, releases, definition of done). The engineer edits them there; you read them and add to them.

- **Read:** after you match work to a product in the repo map, and before you plan, change, review or answer anything about it, run once per product the work touches (never for all of them):
  `{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/notes/Get-Knowledge.ps1" -Product "<product name>"`
  It prints the product's repos, change order and other fields, its owners, its glossary words, its note and the team handbook, in one block. With no product (a team-wide question), run it with `-Handbook` instead. If it says knowledge is not available, go on without it.
- **What goes where (split rule):** if a fact would still be true after the product's code was rewritten (a business rule, a customer need, why a decision was made), it belongs in the product note; if it is about how the team works rather than one product, in the handbook. If it is about one codebase (a build quirk, a pattern, a file to avoid), it belongs in that repo guide's `## Remembered`. Never write a fact in two places. Owners live only in Workshop's People: never write them into a note.
- **Write:** when you confirm a fact that is missing from the note or handbook or contradicts it, and it would help the next person, first read `{{ENG_HOME}}/guides/product-notes.md` and follow it exactly: only `Set-ProductNote.ps1`, one fact per call, and list every change in your reply.
- Agents that may not run scripts or write files (hub, chat) read the same files with `Get-Content`; pr-reviewer runs `Get-Knowledge.ps1` and suggests note lines in `review.md` instead of writing them.

## Writing as the engineer

Text the engineer sends as themselves (PR descriptions, handoffs, briefs, requester messages, review comments, 1:1 drafts) follows their voice from Workshop first: read `<dataDir>/settings/voice.md` (`Get-Content ~/.workshop/config.json` gives `dataDir`, default `~/Workshop`) once per session when it exists. It wins over the writing rules in the Personal and Company sections; follow those for anything it does not cover.

**Audience.** Unless the command or the engineer names one, write for this reader and follow voice.md's `## For <audience>` section when it has one:
- PR descriptions, review comments, handoffs: engineers (no section; Style guide and Always only).
- Requester messages, triage questions, work item comments, briefs: Business teams.
- Status updates, escalations, `--for leadership`: Leadership.

For Business teams and Leadership: no file paths, class or method names, code or tool names; say what changes for them and when; explain any technical word you cannot cut in a few plain words. A Personal or Company `## Audiences` list overrides this one.

## Pipeline commands

Before you run any command that reads or writes `.work/` (the pipeline, triage, shape, scope, spikes, standup, shutdown and the like), read `{{ENG_HOME}}/guides/pipeline.md`: the work folder files, the approval gates, paused items and the branch and commit conventions. Chat, hub, people prep and PR review do not need it.

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
