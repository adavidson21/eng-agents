---
description: "Backfill regression tests for a product: one hands-off Quick change per UI repo that adds end-to-end tests for what already works. Usage: /cover <product> [-- <area or pages>]"
agent: investigator
---

Backfill regression tests. Arguments: **$ARGUMENTS**. Everything before ` -- ` is the product (below, `<product>`); everything after it is the area (below, `<area>`; none means the main pages).

Ask nothing in this command. What you cannot find out becomes a gap (core rule 3). Change no product code: this command only writes repo guide tables and creates work items. The tests themselves are written by the items it creates, which Workshop builds hands-off.

## Step 1: Find the product's UI repos

- Run exactly `{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/notes/Get-Knowledge.ps1" -Product "<product>"`. Its Product block lists the repos. If the product is not in Workshop's Settings, use the repo map's row for it.
- Keep only repos that are workspace folders with a `.git` folder and a UI: their guide's `Stack:` line names `angular` or `playwright`, or the guide has a `## UI checks` table.
- If none is left, stop and say: `No UI repo for <product>: nothing to cover.`

## Step 2: Make sure each repo has a suite

For each UI repo, read its guide (`AGENTS.local.md`, else `AGENTS.md`). With the Tandem tools, `tandem_tests_detect` answers the questions below (config, testDir, routes for Step 3):

- **Has a `## Regression tests` table:** go on.
- **Has `playwright.config.*` but no table:** add the table to the guide (template in `{{ENG_HOME}}/templates/repo-agents.md`): Command from `package.json`'s e2e script, else `npx playwright test`; Runner `playwright`; Folder the config's testDir.
- **No Playwright at all:** add the table with Command `npx playwright test`, Runner `playwright`, Folder `e2e/`, and remember that this repo's item must set the suite up first (Step 4).

Changing a guide table is the only edit this command makes in a repo. List each one in your reply.

## Step 3: Pick what to cover

At most 5 pages per repo. Take them from, in order: the area `<area>` (page paths or a feature name you find in the routes), else the guide's `## UI checks` Pages, else the app's top-level routes (read the router file the guide's patterns name). Skip a page that already has tests in the suite's Folder for its main action (search the test titles and `page.goto` paths).

For each page, write one acceptance criterion for what it does **today**, from the code you read: `Given <page> with mocked data, When <its main action>, Then <what the person sees>`. Never describe behavior you did not see in the code.

## Step 4: Create the items

One local item per repo, run exactly:

```
{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/work/New-LocalWorkItem.ps1" -WorkRoot ".work" -Title "Regression tests for <repo>: <pages, short>" -Description "<sentence>" -AcceptanceCriteria "<the criteria, one per line>" -Repos "<repo>" -Areas "<the suite's Folder>" -Coverage "<product>"
```

The description is one sentence: "Add end-to-end tests for what these pages do today, with every API mocked. No change to product code." For a repo with no Playwright, add: "First set up Playwright (`tandem_tests_ensure_env` when available): a config whose webServer starts the app with mocked APIs, and one smoke test." Its last output line is the new folder.

## Step 5: Hand off

- Say in one line per item: its id, repo and how many pages. Then: "Workshop builds these hands-off as Quick changes; you publish each PR. Every build after that runs them."
- If the workspace has no Workshop, say: "Run `/start <id> quick` for each."
