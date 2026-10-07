---
description: "Fact-check a documentation file against the code. Usage: /check-docs <doc path>"
agent: reviewer
---

Fact-check the documentation at **$1**.

## Step 1: Read

- Read the doc at `$1`.
- Look for `sources.md` in the same folder as the doc, then for a matching `.work/docs-*/sources.md`. If one exists, read it.
- Read the `AGENTS.md` of the repo the doc is about.

## Step 2: Check every claim

For each factual statement in the doc (commands, file paths, class names, behavior, config keys, defaults):
- Find it in the code.
- Mark it `Correct`, `Wrong`, `Outdated`, or `Cannot verify`.
- For `Wrong` and `Outdated`, give the correct fact and the file that shows it.

**Diagrams are claims too.** For each Mermaid block, check every box, arrow, participant, message, entity, column, and relationship the same way. In the report, name the diagram by the heading above it, for example `Containers: arrow Orders API to Payment gateway`. Check ER diagrams against the migrations `*ModelSnapshot.cs` when one exists.

If the doc has Mermaid blocks, run exactly this command and record the last line in the report:

```
{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/diagrams/Test-Mermaid.ps1" -Path "$1"
```

If the doc lists commands, run the safe ones (build, test, lint) to confirm they work.

## Step 3: Check what is missing

- List anything a reader would need that the doc does not say.

## Step 4: Report

- Write the results to `.work/docs-<short-name>/check.md` as a table: claim, status, correction, evidence. Use the same folder as `sources.md` if it exists. For a TSD, that is the TSD's own folder.
- Tell the engineer how many claims are Wrong, Outdated, and Cannot verify, and list the Wrong ones in one line each.
- You cannot edit the doc. Tell the engineer to fix it or rerun `/docs` (or `/tsd`) with the corrections.
