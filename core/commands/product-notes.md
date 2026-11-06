---
description: "Move product facts from repo guides' Remembered sections into product notes, or list the product notes. Usage: /product-notes [move | list]"
agent: writer
---

Product notes: **$ARGUMENTS**

Product notes are explained in the core rules (Product notes). This command writes product notes only through `Set-ProductNote.ps1`, and changes repo guides only by removing lines the engineer agreed to move. It changes no code.

If the first word is `list` or there are no arguments, go to "List". If it is `move`, go to "Move". Anything else: reply `Usage: /product-notes [move | list]` and stop.

## List

Run `{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/notes/Get-ProductNote.ps1" -List` and show what it prints. Then list the products in the repo map that have no note yet, and say: "Run `/onboard-repo <repo>` or `/memory -product <product> <fact>` to start one." Stop.

## Move

### Step 1: Check that product notes are available

Run the `-List` call above. If it says product notes are not available, show the reason and stop.

### Step 2: Collect the lines

For every folder in the workspace root that contains `.git` and has a repo guide (`<repo>/AGENTS.local.md`, else `<repo>/AGENTS.md`), read the lines under `## Remembered`. Skip repos with none.

### Step 3: Sort each line

Use the split rule from the core rules:

- **Product fact:** still true if the product's code were rewritten (a business rule, a customer need, who owns what, why a decision was made). Pick the product from the repo map: the products whose repo table lists this repo. If there are several and the line does not say which, mark it `ask`. Pick a section: `Business rules`, `Gotchas`, `People`, `Decisions`, or `Remembered`.
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
