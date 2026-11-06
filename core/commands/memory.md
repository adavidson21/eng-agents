---
description: "Remember a rule for one repo, for every repo with -global, or a product fact with -product. Usage: /memory [-global | -product <product> | <repo folder>] <rule>, or /memory -list [repo folder]"
agent: writer
---

Remember this: **$ARGUMENTS**

First word: **$1**

Do not change any code. Write only the one memory file chosen below (for `-product`, only through `Set-ProductNote.ps1`).

## Step 1: Pick the scope

Use the first word:

| First word | Scope | The rule is |
|---|---|---|
| `-global`, `--global`, or `-g` | Global: every repo | Everything after the first word |
| `-product` | One product: its product note. Go to "Product facts" below. | The second word is the product (quote it if it has spaces); the fact is everything after it |
| `-list` | Show memory, write nothing. Go to "Listing" at the end. | |
| A folder in the workspace root that contains `.git` | That repo | Everything after the first word |
| Anything else | One repo | All of the arguments |

If the scope is "one repo" but no repo was named, pick it:

1. If this conversation has read or changed files in exactly one repo, use that repo.
2. Otherwise, if this conversation is about one work item and its `repos.md` lists exactly one repo, use that repo.
3. Otherwise ask: "Which repo is this for? `<repos from this conversation, or every repo folder in the workspace>`, or `-global` for every repo." Wait for the answer.

If there are no arguments, reply: `Usage: /memory [-global | -product <product> | <repo folder>] <rule>, or /memory -list [repo folder]`. Stop.

If the scope is one repo or global but the rule is a product fact (it would still be true if the product's code were rewritten: a business rule, who owns what, why a decision was made), ask: "This sounds like a fact about `<product>`. Save it in its product note instead?" Wait. If yes, go to "Product facts".

## Step 2: Write the rule as one line

- One short instruction, in the engineer's words where possible. Example: `Use FluentAssertions in new tests. Do not add Shouldly.`
- If the rule says "this" or "that" about something earlier in the conversation, replace it with the concrete thing (the file, command, or pattern). If you cannot tell what it refers to, ask.
- Do not add anything the engineer did not say.
- Never save secrets, tokens, passwords, connection strings, or personal data. If the rule contains any, stop and say why.
- Global scope only: if the rule names a path or a name that exists in only one repo, ask: "This looks specific to `<repo>`. Save it for that repo instead?" Wait.

## Step 3: Find the memory file

**Global:** `{{ENG_CONFIG}}/memory.md`. If it does not exist, create it with exactly this content:

```markdown
# Global memory

Rules from the engineer for every repo. Written by /memory. Edit or delete lines freely.

## Remembered
```

**One repo:** the repo guide: `<repo>/AGENTS.local.md` if it exists, otherwise `<repo>/AGENTS.md`.

- If neither exists, stop and reply: "`<repo>` has no repo guide yet. Run `/onboard-repo <repo>` first, or use `/memory -global`."
- If the repo guide is `AGENTS.md`, run `git -C <repo> ls-files AGENTS.md`. If it prints `AGENTS.md`, the file is committed and belongs to the team. Do not write to it. Reply: "`<repo>/AGENTS.md` is committed. Run `/onboard-repo <repo>` to create `AGENTS.local.md`, then try again." Stop.
- If the repo guide has no `## Remembered` section, add one at the end of the file.

## Step 4: Check what is already there

Read the whole memory file.

- If a line in `## Remembered` already says the same thing, do not add a new one. Tell the engineer and stop.
- If a line in `## Remembered` contradicts the new rule, show both and ask: "Replace the old rule, keep both, or cancel?" Wait.
- One repo only: if the rule corrects a fact elsewhere in the repo guide (a command, a path, a pattern file), show that line and ask: "Fix this line instead of adding a memory line?" Wait. If yes, change only that line, then skip Step 5.

## Step 5: Write it

- Run `Get-Date -Format yyyy-MM-dd` for today's date.
- Add `- <rule> (<date>)` as the last line of the `## Remembered` section.
- Change nothing else in the file, except a line the engineer told you to replace in Step 4.
- If `## Remembered` now has more than 20 lines, tell the engineer and suggest merging or deleting old ones.

## Step 6: Confirm

Reply with:
- The file you changed and the exact line.
- When it takes effect:
  - One repo: the next time an agent reads that repo guide (every pipeline command does).
  - Global: every new session. Run `/new` to load it now in other work.
- "To undo, delete the line from that file."

## Product facts

For `-product <product> <fact>`:

1. Match `<product>` to a product in the repo map (Products, "Also called"). If none matches, ask which product. Use its `Note:` line if it has one.
2. Read the note: `{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/notes/Get-ProductNote.ps1" -Product "<product>"`.
   - Not available: reply with the reason it printed and stop.
   - Does not exist yet: add `-Create` to the call in step 4.
3. Write the fact as one line (Step 2's rules). Pick the section: `Business rules`, `Gotchas`, `People`, `Decisions`, or `Remembered` when unsure. If a line in the note already covers the subject, show it and ask: "Replace this line, keep both, or cancel?" Wait.
4. Run `{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/notes/Set-ProductNote.ps1" -Product "<product>" -Section <section> -Line "<fact>" -Source "the engineer"`, with `-Replace "<text of the old line>"` if they chose to replace it.
5. Reply with what the script printed, and: "It shows as Changed by Tandem in Notes until you mark it reviewed. To undo, restore the earlier version from History in Notes."

## Listing

For `/memory -list`, write nothing. Show:
- The `## Remembered` lines of `{{ENG_CONFIG}}/memory.md`, or "No global memory yet."
- If a repo folder follows `-list`, that repo guide's `## Remembered` lines. Otherwise, for every repo folder in the workspace root that has a repo guide, its folder name and its `## Remembered` lines. Skip repos with none.
