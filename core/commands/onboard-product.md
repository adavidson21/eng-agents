---
description: "Get a product ready for its first build: scan its repos, draft its repo guides and product note, log what is missing as gaps, and start a trial run. Usage: /onboard-product <product name>"
agent: investigator
---

Onboard the product **$ARGUMENTS** so Tandem can build for it. Workshop's Loom shows each step as the product's new line lights up: Add, Scan, Fill the gaps, Trial run, Live.

Ask nothing in this command. What you cannot find out becomes a gap (core rule 3), answered once in Workshop's Teach cards.

## Step 1: Find the product and its repos

- Run exactly this command:

```
{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/notes/Get-Knowledge.ps1" -Product "$ARGUMENTS"
```

- Its Product block lists the product's repos (Workshop Settings, Knowledge, Products). If it says the product is not in Workshop's Settings, use the repo map's row for that product instead.
- Keep only repos that are folders in the workspace with a `.git` folder. For each one listed but missing, log a gap with `-Kind repo -Product "$ARGUMENTS" -Source "/onboard-product" -Question "Where is the <repo> repo? It is not in the workspace." -Assumed "Skipped it"`.
- If no repo is left, log a gap with `-Kind repo -Question "Which repos make up $ARGUMENTS?" -Assumed -` and stop: say `Needs you: tell Workshop which repos make up $ARGUMENTS (Settings, Knowledge, Products).`

## Step 2: Scan each repo

For each repo from Step 1, in the product's change order (shared repos first):

- If the repo has no repo guide (`<repo>/AGENTS.local.md` or `<repo>/AGENTS.md`), open `{{ENG_HOME}}/../commands/onboard-repo.md` and follow it for that repo, with these changes: ask nothing; for a committed team guide, use `link`; anything you would have asked becomes a `TODO(you)` line in the guide and a gap (`-Kind repo`, with your assumption).
- If it has a guide, read it. Do not rewrite it. If its Commands table has no build or no unit test command, or it has no `## UI checks` table while the repo has a UI, log a gap for each (`-Kind repo -Question "What command builds <repo>?"`, and so on), with the command you found in the code as the assumption, or `-` when you found none.
- Write down, per repo: its stack, its build and unit test commands, and whether it has a UI.

When every repo is scanned, record it:

```
{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/work/Set-Onboarding.ps1" -WorkRoot ".work" -Product "$ARGUMENTS" -Step scan -Value "<repos scanned, comma separated>"
```

## Step 3: Draft the product note

- Open `{{ENG_HOME}}/../commands/product-notes.md` and follow its `draft` steps for this product: lines from the product's READMEs and docs, each with its source, through `Set-ProductNote.ps1` only.
- For each thing a builder must know that no file answers (a business rule, a term in the code nobody explains, how a release goes out), log a gap with the right kind (`fact`, `term`, `process`) and `-Product "$ARGUMENTS"`. At most 5: the ones a first build would trip on.

## Step 4: Start a trial run

The trial run proves that build, tests and worktrees work for this product before real work starts. It is a quick change with one small, safe outcome.

- Pick the repo from Step 2 with a working unit test command, shared repos last. If none has one, skip this step and say so in Step 5.
- Pick the smallest real gap in its tests you saw while scanning: one function or component with no test. Write one sentence for it.
- Run exactly this command, with that sentence:

```
{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/work/New-LocalWorkItem.ps1" -WorkRoot ".work" -Title "Trial run: add a test for <thing>" -Description "<the sentence>. Onboarding trial run for $ARGUMENTS: one test, no behavior change." -AcceptanceCriteria "Given the <thing>, When its new unit test runs, Then it passes with the repo's unit test command." -Repos "<repo>" -Trial "$ARGUMENTS"
```

- The last line of output is the folder; its name starts with the local id. Record it:

```
{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/work/Set-Onboarding.ps1" -WorkRoot ".work" -Product "$ARGUMENTS" -Step trial -Value "<local id>"
```

Workshop builds the trial run as a hands-off Quick change. When it reaches Ready to publish, the product is live on Loom's floor.

## Step 5: Report

Reply with:

```
Onboarded: $ARGUMENTS
Repos: <each repo: guide written, guide kept, or skipped>
Product note: <lines added, or "nothing new">
Gaps: <how many, by kind>  (answer them in Workshop's Teach cards)
Trial run: <local id and title, or why there is none>
```

No `progress.md` entry: this command has no work folder.
