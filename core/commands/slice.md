---
description: "Slice approved stories into sequenced, code-mapped features and stories (milestones.md). Usage: /slice scope-<name>"
agent: milestone-architect
---

Slice the stories in **.work/$1/** (the `.work/` part is optional). Do not change any code.

## Step 1: Find the folder and check the gate

- The folder is `.work/$1/`, or `$1` itself if it already starts with `.work/`. If `$1` is empty or the folder does not exist, list the `.work/scope-*` folders and stop.
- Read `stories.md`. If it does not contain `Status: APPROVED`, stop. Tell the engineer to review it and run `/approve $1` first.
- If `milestones.md` says `Status: APPROVED`, stop and suggest `/backlog $1`.
- If `milestones.md` exists as a DRAFT, this is a refine: the engineer's edits and notes under "Open questions" are what to change. Keep everything else.

## Step 2: Read

- Read `epics.md`, `stories.md`, and the latest entries in `progress.md`.
- Read the repo map (the workspace root `AGENTS.md`), the product block named on the "Product:" line of `epics.md`, and its "Product docs" `technical-spec.md` if there is one.
- Read the repo guide (`<repo>/AGENTS.local.md` if it exists, otherwise `<repo>/AGENTS.md`) of each repo in the product, including its architecture rules and "Patterns to follow" table. If it points to an architecture doc, read it.

## Step 3: Map each story to the code

For each story, follow the architecture layers in the repo guide and find:

- The existing interfaces, classes, entities, database tables, endpoints, and UI components it touches. Search the code; use the paths in "What exists today" in `epics.md` as a start.
- Which repos it touches. Shared repos first.
- One existing file that does something similar: the pattern to follow.
- New tables, columns, or migrations it needs.
- If you need history to understand a file, run `git -C <repo> log --oneline -10 -- <path>`.

Write down real paths only. If you cannot find where a story belongs, ask ONE question.

## Step 4: Check the slices

- **Vertical slices.** For each feature, check that once its stories are done, a user can use it and someone can verify it end to end (data, backend, and UI as needed). If not, move the missing story into it, or merge it with the next feature.
- **Story size.** Each story must fit one `/start` run: at most 2 repos and about 8 tasks of at most 3 files each. Split a bigger story; keep every scenario covered. Merge stories that are too small to be worth their own pull request.
- **Foundation.** Schema changes, migrations, and shared setup become the first story of the first feature that needs them. Never a feature of their own.
- Record every split, merge, move, or rewording under "Changes from stories.md". If you changed nothing, write "None".

## Step 5: Sequence

- Order features so each one only needs features above it. Order stories inside each feature the same way.
- Renumber to match the order: features 1, 2, 3; stories `<feature>.<n>`.
- Fill "Depends on" for each story with stories above it, or "none".

## Step 6: Write milestones.md

- Start from `{{ENG_HOME}}/templates/milestones.md`. Write it to the folder as `milestones.md`.
- Keep `Status: DRAFT`. Never set it to APPROVED.
- Copy the `Epic:` line and the epic sentences from `epics.md`.
- Under each feature heading write its description: two or three sentences on what the user can do when it ships and why it matters. No design, screens, fields, or code.
- Under `#### Release note` write one or two business-friendly sentences for customers (at most 255 characters): what they can do now, with no jargon, ids, or code.
- Copy each story's "As a ..." line, its context, and its Gherkin scenarios from `stories.md`, changed only as recorded in "Changes from stories.md". Do not add design detail to them.
- Fill each story's "Notes for the builder" from Step 3: where to look, similar existing code, and what it depends on. These are pointers for the planner, not a design, and they are never published to ADO.
- Fill "Coverage" so every scenario in `stories.md` maps to a story here.

## Step 7: Check the format

Run exactly this command:

```
{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/ado/Export-Backlog.ps1" -Folder ".work/$1" -Check
```

- If it prints lines starting with `FORMAT:`, fix each one in `milestones.md` and run it again. Stop after 3 failed attempts (Core rule 6).
- When it passes, keep its summary line for the log.

## Step 8: Log and hand off

- Add a `progress.md` entry for `/slice` with the format check output.
- Tell the engineer, in a few lines: the features in order with their story counts, and anything under "Changes from stories.md" or "Open questions".
- Then: "Review `milestones.md`. When it is right, run `/approve $1 milestones`, then `/backlog $1` to make the import file (or `/backlog $1 ado` to create the items in ADO, or `/backlog $1 local` for local work items)."
