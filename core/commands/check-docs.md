---
description: "Fact-check a documentation file against the code. Usage: /check-docs <doc path>"
agent: reviewer
---

Fact-check the documentation at **$1**.

## Step 1: Read

- Read the doc at `$1`.
- Look for a matching `.work/docs-*/sources.md`. If one exists, read it.
- Read the `AGENTS.md` of the repo the doc is about.

## Step 2: Check every claim

For each factual statement in the doc (commands, file paths, class names, behavior, config keys, defaults):
- Find it in the code.
- Mark it `Correct`, `Wrong`, `Outdated`, or `Cannot verify`.
- For `Wrong` and `Outdated`, give the correct fact and the file that shows it.

If the doc lists commands, run the safe ones (build, test, lint) to confirm they work.

## Step 3: Check what is missing

- List anything a reader would need that the doc does not say.

## Step 4: Report

- Write the results to `.work/docs-<short-name>/check.md` as a table: claim, status, correction, evidence. Use the same folder as `sources.md` if it exists.
- Tell the engineer how many claims are Wrong, Outdated, and Cannot verify, and list the Wrong ones in one line each.
- You cannot edit the doc. Tell the engineer to fix it or rerun `/docs` with the corrections.
