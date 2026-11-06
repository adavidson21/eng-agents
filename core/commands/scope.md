---
description: "Turn an idea into an epic, features, and user stories. Usage: /scope <idea>, or /scope scope-<name> to refine a draft"
agent: product-manager
---

Scope this: **$ARGUMENTS**

Follow these steps in order. Do not change any code.

## Step 1: New scope or refine a draft

- If the request above is empty, stop and reply: `Usage: /scope <idea>, or /scope scope-<name> to refine a draft`.
- **Refine:** if the request is one word that starts with `scope-`, it is an existing folder.
  - The folder is `.work/<that word>/`. If it does not exist, list the `.work/scope-*` folders and stop.
  - If `stories.md` says `Status: APPROVED`, stop and suggest `/slice <that word>`.
  - Read `epics.md`, `stories.md`, and `progress.md`. The engineer's notes under "Open questions", and any edits they made, are what to change. Keep everything else.
  - Go to Step 2. In Step 3, ask only about the open questions.
- **New:** otherwise the request is the idea.
  - Make a short name from the idea: the first 5 meaningful words, lowercase, joined with `-`, at most 40 characters, filler words (a, an, the, to, of, for, and, add, new) dropped. For example "I want to add a new ticket called a change request" gives `ticket-called-change-request`.
  - The folder is `.work/scope-<short name>/`. If it already exists, stop and ask: "`.work/scope-<short name>/` exists. Refine it (`/scope scope-<short name>`) or use another name?"
  - Copy `{{ENG_HOME}}/templates/progress.md` into the folder as `progress.md`. In its header use `scope-<short name>` in place of `<id>` and the idea as the title.

## Step 2: Read the product and the code

- Read the repo map (the workspace root `AGENTS.md`). Match words in the idea against the **Products** and **Glossary** tables to pick the product. If none matches, or more than one does, ask ONE question to pick it (this counts toward the 3 in Step 3). If there is no repo map, say so and use the repo folder names.
- If the product block names a "Product docs" folder, read the `technical-spec.md` in it if there is one, and any product docs the block links.
- Read the repo guide (`<repo>/AGENTS.local.md` if it exists, otherwise `<repo>/AGENTS.md`) of each repo in the product, and the product note (Product notes in the core rules).
- Search the code for the nouns in the idea and the closest existing thing (for a new ticket type: the existing ticket types). Find the entities, endpoints, screens, and business rules that already exist. Note each with its file path.
- For each repo in the product, run `git -C <repo> log --oneline -20`. For the paths you found, run `git -C <repo> log --oneline -10 -- <path>`. Note recent changes that matter to the idea.

## Step 3: Ask (at most 3 questions)

- Ask up to 3 questions, **one at a time**, with 2 to 4 options each and your recommendation. Wait for each answer.
- Pick the questions whose answers change the features or the MVP line the most: business rules, edge cases, permissions, what can wait. Example: "Does a change request need a multi-step approval workflow in the MVP? A) Single approver (Recommended: the existing ticket flow already has one approver step, `repo/path/File.cs`) B) Multi-step C) No approval in MVP".
- If the idea does not name the epic (the version this ships in), one of the questions must be: "Which epic is this? A) A new version, for example `<Product> v<next>` (Recommended) B) An existing ADO epic: give its id".
- If you still have open points after 3 questions, write them under "Open questions". Do not ask more.

## Step 4: Write epics.md

- Start from `{{ENG_HOME}}/templates/epics.md`. Write it to the folder as `epics.md` (in refine mode, update it).
- "What exists today" lists only what you found in Step 2, with paths.
- MVP features: each one is the smallest piece a user can use on its own. If a feature cannot be used without another, merge them. Number them in the order they should ship.
- Put everything else under "V2 / Icebox", one line each.
- Record each question and answer under "Decisions made during clarification".

## Step 5: Write stories.md

- Start from `{{ENG_HOME}}/templates/stories.md`. Write it to the folder as `stories.md` (in refine mode, update it).
- Keep `Status: DRAFT`. Never set it to APPROVED.
- One `## Feature <n>: <title>` section per MVP feature, same numbers and titles as `epics.md`. No sections for Icebox features.
- Every feature has at least one `### Story <n>.<m>: <title>`.
- Every story has the "As a ..., I want ..., so that ..." line and at least one Gherkin scenario with `Given`, `When`, and `Then`. Cover the edge cases from Step 3 as their own scenarios.
- No class names, table names, or file paths in this file.
- Update the "Stories" column of the MVP table in `epics.md` to match.

## Step 6: Log and hand off

- Add a `progress.md` entry for `/scope`.
- Tell the engineer, in a few lines: the epic, the MVP features with their story count, what went to Icebox, and any open questions.
- Then: "Review `epics.md` and `stories.md`. To change them, edit the files or add notes under Open questions and run `/scope scope-<short name>` again. When they are right, run `/approve scope-<short name>`, then `/slice scope-<short name>`."
