---
description: "Save a product fact, list the product notes, move product facts out of repo guides, or draft one product's note from its docs. Usage: /product-notes [add <product> <fact> | list | move | draft <product>]"
agent: writer
---

Product notes: **$ARGUMENTS**

Product notes are explained in the core rules (Product notes) and in `{{ENG_HOME}}/guides/product-notes.md`. This command writes product notes only through `Set-ProductNote.ps1`, and changes repo guides only by removing lines the engineer agreed to move. It changes no code.

If the first word is `add`, go to "Add". If it is `list` or there are no arguments, go to "List". If it is `move`, go to "Move". If it is `draft`, go to "Draft". Anything else: reply `Usage: /product-notes [add <product> <fact> | list | move | draft <product>]` and stop.

## Add

The product is the word after `add` (quote it if it has spaces); the fact is everything after it.

1. Match the product to one in the repo map (Products, "Also called"). If none matches, ask which product. Use its `Note:` line if it has one.
2. Read what is known: `{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/notes/Get-Knowledge.ps1" -Product "<product>"`.
   - Not available: reply with the reason it printed and stop.
   - "No product note yet": add `-Create` to the call in step 4.
   - A fact about how the team works (sprints, PRs, releases, done): it goes in the handbook. Use `-Note team/handbook.md` instead of `-Product` in step 4.
   - Who owns the product: not a note fact. Reply: "Owners live in Workshop: Settings, People, Owns." Stop.
   - A fact about one codebase (a command, a pattern, a file): not a note fact. Suggest `/memory <repo> <rule>` and stop.
3. Write the fact as one short line in the engineer's words. Replace "this" or "that" with the concrete thing. Never save secrets, tokens, passwords, connection strings or personal data: if the fact holds any, stop and say why. Pick the section: `Business rules`, `Gotchas`, `Who to ask`, `Decisions`, or `Remembered` when unsure (handbook: its section for the subject). If a line in the note already says the same thing, say so and stop. If one covers the subject differently, show it and ask: "Replace this line, keep both, or cancel?" Wait. Skip asking when `/retro` sent the fact: the engineer already picked and worded it.
4. Run `{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/notes/Set-ProductNote.ps1" -Product "<product>" -Section <section> -Line "<fact>" -Source "the engineer"`, with `-Replace "<text of the old line>"` if they chose to replace it.
5. Reply with what the script printed, and: "It shows as Changed by Tandem in Notes until you mark it reviewed. To undo, restore the earlier version from History in Notes." Stop.

## List

Run `{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/notes/Get-ProductNote.ps1" -List` and show what it prints. Then list the products in the repo map that have no note yet, and say: "Run `/product-notes add <product> <fact>` or `/product-notes draft <product>` to start one." Stop.

## Move

### Step 1: Check that product notes are available

Run the `-List` call above. If it says product notes are not available, show the reason and stop.

### Step 2: Collect the lines

For every folder in the workspace root that contains `.git` and has a repo guide (`<repo>/AGENTS.local.md`, else `<repo>/AGENTS.md`), read the lines under `## Remembered`. Skip repos with none.

### Step 3: Sort each line

Use the split rule from the core rules:

- **Product fact:** still true if the product's code were rewritten (a business rule, a customer need, why a decision was made). Pick the product from the repo map: the products whose repo table lists this repo. If there are several and the line does not say which, mark it `ask`. Pick a section: `Business rules`, `Gotchas`, `Who to ask`, `Decisions`, or `Remembered`. A line about how the team works (sprints, PRs, releases) goes to the handbook (`-Note team/handbook.md`); a line about who owns what is not moved (owners live in Workshop's People).
- **Code fact:** about this codebase (a command, a pattern, a file, a library, a test style). It stays in the repo guide.
- When unsure, it stays.

### Step 4: Show the plan and wait

Show one numbered table with every line: repo, the line, and either `stays` or `-> <product> / <section>`. Then ask:

"Move the lines marked with `->`? Reply `yes`, or list numbers to change (for example `3 stays`, `5 -> Stencil / Gotchas`), or `cancel`."

Wait. Apply the changes and show the table again until the engineer says `yes` or `cancel`. On `cancel`, stop. Resolve every `ask` before going on.

### Step 5: Move them

For each line to move, in table order:

1. Take the rule text without the leading `- ` and without its trailing `(<date>)`. Keep that date for the source.
2. Run `{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/notes/Set-ProductNote.ps1" -Product "<product>" -Section <section> -Line "<rule text>" -Source "<repo> repo guide, <date>"`. Add `-Create` if the product has no note yet (with `-Repos` and `-AlsoCalled` from the repo map).
3. Only if it printed `Changed` or `Already there`: remove that one line from the repo guide's `## Remembered`. If the repo guide is a committed `AGENTS.md` (`git -C <repo> ls-files AGENTS.md` prints it), do not edit it; list the line for the engineer to remove instead.
4. If it printed `Not changed`, leave the repo guide line and note the reason.

### Step 6: Report

Reply with:
- Each product note changed, with the lines added.
- Each repo guide changed, with the lines removed.
- Any line not moved and why.
- "The notes show as Changed by Tandem in Notes until you mark them reviewed. History in Notes has every earlier version."

## Draft

Started from Workshop (Settings, Knowledge, Products, **Draft from sources**) or by hand. Nobody is watching: ask nothing; if something is unclear, leave it out.

1. The product is everything after `draft` (quotes removed). Run `{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/notes/Get-Knowledge.ps1" -Product "<product>"`. If it says knowledge is not available, or the product is not in Workshop Settings, say so and stop.
2. Read only these, for the repos it lists: each repo's `README.md`, its `docs/` folder (Markdown files, at most 10), files with `architecture`, `adr` or `decision` in the name, and the product docs folder if it names one. Do not read code beyond what a doc points to.
3. Collect facts the note does not have yet, by its sections: `Summary` (at most 2 lines: what the product is and who uses it), `Business rules`, `Gotchas`, `Decisions` (with the ADR or doc that says why), `Links` (doc paths). Only facts a doc states; never guesses, plans or to-dos; never owners or people. Skip anything already in the note, and anything about one codebase (that belongs in the repo guide).
4. Write at most 15 lines, each with `{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/notes/Set-ProductNote.ps1" -Product "<product>" -Section <section> -Line "<fact>" -Source "<doc path>"` (add `-Create` to the first call if there is no note yet). If a doc contradicts a line in the note, flag that line (`-Flag`, see `{{ENG_HOME}}/guides/product-notes.md`) instead of replacing it.
5. Reply with each line added (section, line, source), each line flagged, and: "Review them in Notes: the note shows as Changed by Tandem, with the new lines highlighted."
