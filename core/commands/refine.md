---
description: "Define one story or bug: a description and Gherkin acceptance criteria, ready to publish. Usage: /refine <title>, or /refine refine-<name> to revise a draft"
agent: product-manager
---

Refine this: **$ARGUMENTS**

Follow these steps in order. Do not change any code. For anything bigger than one story, use `/scope` instead.

## Step 1: New or revise

- If the request above is empty, stop and reply: `Usage: /refine <title>, or /refine refine-<name> to revise a draft`.
- **Revise:** if the request is one word that starts with `refine-`, it is an existing folder.
  - The folder is `.work/<that word>/`. If it does not exist, list the `.work/refine-*` folders and stop.
  - If `refine.md` says `Status: APPROVED`, stop and say it is approved: publish it from Slate, or `/start <id> feature` once it is in ADO.
  - Read `refine.md` and `progress.md`. The engineer's notes under "Open questions", and any edits they made, are what to change. Keep everything else. Go to Step 2, and in Step 3 ask only about the open questions.
- **New:** otherwise the request is the title, optionally followed by a description on the next lines.
  - Make a short name: the first 5 meaningful words of the title, lowercase, joined with `-`, at most 40 characters, filler words (a, an, the, to, of, for, and, add, new) dropped.
  - The folder is `.work/refine-<short name>/`. If it already exists, stop and ask: "`.work/refine-<short name>/` exists. Revise it (`/refine refine-<short name>`) or use another name?"
  - Copy `{{ENG_HOME}}/templates/progress.md` into the folder as `progress.md`, with `refine-<short name>` as the id and the title.

## Step 2: Read what is known

- If the request names a work item (`#<id>`) and `.work/triage-<id>/triage.md` exists, read it and the `workitem.md` beside it: the request, its comments, and the answers in `answers.md` if there is one.
- If the request names a parent (`Parent: #<id>`) or a scope folder, read that scope's `epics.md` and `stories.md` so this story fits them.
- Read the repo map, the product note (Product notes in the core rules) and the repo guide of each repo in the product, then search the code for the nouns in the title and the closest thing that exists. Note each with its file path.

## Step 3: Ask (at most 2 questions)

- Ask up to 2 questions, **one at a time**, with 2 to 4 options each and your recommendation. Wait for each answer.
- Ask only what changes the acceptance criteria: business rules, edge cases, permissions. Do not ask about implementation.
- If you still have open points, write them under "Open questions". Do not ask more.

## Step 4: Write refine.md

- Start from `{{ENG_HOME}}/templates/refine.md`. Write it to the folder as `refine.md` (when revising, update it).
- `Type:` is `Bug` if the request is about something broken, otherwise `User Story`. `Parent:` is `#<id>` when one was named, otherwise `none`.
- Description: the story sentence, then two to four sentences of context in the user's language. No class names, tables, or file paths.
- Acceptance criteria: one Gherkin scenario per rule or edge case, each one a tester could run by hand.
- Notes for the builder: the file paths you found and what to watch. This section is for the engineer and is not published.
- Leave `Status: DRAFT`. Only `/approve` changes it.

## Step 5: Hand off

- Add a `progress.md` entry for `/refine`.
- Reply in 3 lines or fewer: the story sentence, the number of scenarios, open questions if any, and the next step: `/approve refine-<short name>`.
