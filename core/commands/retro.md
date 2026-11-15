---
description: "Turn review findings and rework into rules so the same mistake does not come back. Usage: /retro <id>, or /retro --since yyyy-MM-dd for patterns across items. Add auto to save nothing."
agent: writer
---

Run a retro. Arguments: **$ARGUMENTS**

You propose rules. You save only the ones the engineer picks from your list (Step 6), and only the way `/memory` does. Everything else you write stays inside `.work/`.

If the last argument is `auto`, nobody is watching (an eval or autopilot run): take it out of the arguments, propose the rules as usual, and save nothing (skip Step 6).

## Step 1: Pick the mode

- If the arguments are `--since <date>` with a `yyyy-MM-dd` date: **across items**. Go to Step 5.
- If the first argument is an id: **one item**. Find the folder in `.work/` that starts with `$1-`. If there is none, or more than one, stop and say so.
- Otherwise reply `Usage: /retro <id>, or /retro --since yyyy-MM-dd` and stop.

## Step 2: Read (one item)

- In the work folder: `review.md`, every `history/review-*.md`, `progress.md` (Notes, blocked entries, failed verifies, and `/approve` entries with `gate=edited`), `spec.md` or `bug.md`, and `tasks.md`.
- Run exactly this command for the findings, grouped:

```
{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/stats/Get-ReviewFindings.ps1" -WorkRoot ".work" -Id <id>
```

- For each repo in `repos.md`, read the `## Remembered` section of its repo guide (`<repo>/AGENTS.local.md`, else `<repo>/AGENTS.md`). Read `{{ENG_CONFIG}}/memory.md` too (it is already loaded). These are the rules that exist.
- If no review was written yet, say so and stop: a retro needs at least one `/review`.

## Step 3: Write retro.md (one item)

- Start from `{{ENG_HOME}}/templates/retro.md`. Write it to the work folder as `retro.md` (replace an older one).
- **What caused rework:** each review finding that became a fix task, each blocked task, each gate you see edited before approval, each failed full-suite check. One line each, with its evidence.
- **Candidate rules:** at most 5. Each one must:
  - prevent a specific finding or rework item above (say which in "Came from");
  - be one short imperative line that an agent could follow without this conversation ("In `api`, map new handlers in `HandlerRegistry.cs`, never in `Program.cs`.");
  - not repeat an existing rule. If an existing rule covers it but was broken, list it under "Rules that exist but were broken" instead.
- **Scope** (use the split rule in the Product notes section of `AGENTS.md`):
  - about one codebase: repo, `/memory <repo folder> <rule>`;
  - true in every repo: global, `/memory -global <rule>`;
  - a product fact that would survive a rewrite: product, `/memory -product <product> <fact>`.
- **For Tandem itself:** problems caused by the pipeline (task sizing, plan gaps, unclear commands). Never turn these into memory rules.
- If nothing is worth a rule, say so. An empty Candidate rules table is a fine result.

## Step 4: Hand off (one item)

- Add a `progress.md` entry for `/retro` with a `- Stats: rules_proposed=<n> broken_rules=<n>` line.
- Reply with the rework lines (at most 5), then go to Step 6.

## Step 5: Patterns across items

- Run exactly this command, with the date:

```
{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/stats/Get-ReviewFindings.ps1" -WorkRoot ".work" -Since <date>
```

- Take the "Repeating patterns" table: a repo and category that showed up in 2 or more work items. If it says "None yet", say so and stop.
- For each repeating pattern (most items first, at most 5):
  - Read the example findings, and the repo's `## Remembered` section.
  - If no rule covers it, propose one rule that would have prevented most of the examples, scoped as in Step 3.
  - If a rule covers it but keeps being broken, say so and propose a clearer wording to replace it (as a `/memory` line plus "then remove the old line").
- Write `.work/_retro/<today yyyy-mm-dd>.md` from `{{ENG_HOME}}/templates/retro.md`: fill "What caused rework" with the patterns (repo, category, number of items) and the rule tables as in Step 3. Leave "What went smoothly" as "Not covered by a cross-item retro".
- Reply with each pattern in one line, then go to Step 6. Do not write a `progress.md` entry (no single item owns this retro).

## Step 6: Pick and save

Skip this step in `auto` mode, or if there are no candidate rules: then end with the rules and their `/memory` lines, ready to copy.

- Show the candidate rules as a numbered checklist, one line each with its scope (`repo <folder>`, `global` or `product <name>`), and ask once: "Which should I save? Reply with numbers, `all` or `none`. Edit a rule's words in your reply if it is not quite right." Wait.
- For each rule they pick, in their wording if they changed it, follow Steps 2 to 6 of `{{ENG_HOME}}/../commands/memory.md` with that scope (it checks for duplicates and secrets, and `-product` facts go through `Set-ProductNote.ps1`). For a "replace the old line" rule, replace that line instead of adding a second one.
- Reply with what was saved, one line each with the file it went to. Rules they did not pick are not saved anywhere.
