---
description: "Scan a repo and draft its repo guide (AGENTS.md) for the engineer to review. Usage: /onboard-repo <repo folder>"
agent: investigator
---

Draft the repo guide for the repo in folder **$1**.

## Step 1: Check the folder and pick the guide file

- `$1` must be a folder in the workspace root that contains a `.git` folder. If not, stop and tell the engineer.
- Run `git -C $1 ls-files AGENTS.md`.
  - If it prints `AGENTS.md`, the team has committed its own `AGENTS.md`. Do not edit it. The guide file is `AGENTS.local.md`.
  - If it prints nothing, the guide file is `AGENTS.md`.
- Decide where to write:
  - If `$1/<guide file>` does not exist, you will write to `$1/<guide file>`.
  - If it exists, read it. You will write the new draft to `.work/_onboard/$1-<guide file>` instead, so the engineer can merge it by hand. Copy its `## Remembered` section into the draft **unchanged**.

## Step 2: Find committed agent guides

Run exactly this command:

```
git -C $1 ls-files "*CLAUDE.md" "*CLAUDE.local.md" "*AGENTS.md" ".claude/*.md" ".github/copilot-instructions.md" ".cursorrules" ".cursor/rules/*"
```

- These are **team guides**: instructions other people committed for AI tools. Read every file it lists.
- A team guide applies to the folder it is in and everything below it. `CLAUDE.md` at the root applies to the whole repo. `src/Web/CLAUDE.md` applies to `src/Web/`.
- If a line in a team guide starts with `@` followed by a path (for example `@docs/testing.md`), it imports that file. Read that file too and treat it as part of the same team guide.
- Note the build and test commands, rules, and conventions each team guide gives. You will check them against the code in Step 3.
- If the command prints nothing, there are no team guides. Skip Step 4.

## Step 3: Gather facts

Read only what you need. Record the file each fact came from.

1. **Purpose:** `README.md`, any `docs/` folder.
2. **Architecture doc:** search for files with names containing `architecture`, `adr`, or `design`. Record the path. Read it if short.
3. **.NET structure:** find `*.sln` and `*.csproj` files. From `ProjectReference` entries, work out the layers (Domain, Application, Infrastructure, Api or Web) and which references which.
4. **Shared repo references:** any `ProjectReference` or path that starts with `..` and leaves this repo. Record the other repo and the example path.
5. **.NET tests:** test projects, xUnit version, mocking library (Moq, NSubstitute, or FakeItEasy from `PackageReference`), and test naming style from 2 or 3 existing tests.
6. **EF Core:** the `DbContext` class and the migrations folder.
7. **Angular:** `package.json` scripts, `angular.json` test builder (Karma or Jest), Angular version. Open 2 existing component tests and note how they stub services (for example `jasmine.createSpyObj`) and how they select elements (for example `data-testid` attributes, `By.css`, or CSS classes). Future tasks must copy this style.
8. **Playwright:** `playwright.config.*` (testDir, baseURL, webServer), existing helpers or fixtures that call `page.route`, folders of mock data, and the selector style the tests use (for example `getByTestId`).
9. **Lint and format:** `.editorconfig`, ESLint and Prettier config, `dotnet format` usage.
10. **Patterns to follow:** one good example file for each row in the template's "Patterns to follow" table.
11. **Team guide check:** for each command or rule from Step 2, check it against what you found. If they disagree, write down both and which one the code supports.

## Step 4: Ask how to use the team guides

Only if Step 2 found team guides. Ask the engineer exactly this, filling in the list:

"This repo has committed agent guides: `<file>`, `<file>`. How should the repo guide use them?
1. **Link (recommended):** agents read them every time, so they stay in sync automatically. The repo guide only adds what they are missing.
2. **Copy:** copy their rules into the repo guide. Agents warn you when the original changes.
3. **Ignore:** agents do not read them."

Wait for the answer. The engineer can choose differently per file.

## Step 5: Offer to test the commands

- Show the engineer the build and test commands you found. Ask: "Should I run these now to confirm they work? They may take a few minutes." Wait.
- If yes, run them one at a time and record whether each works.

## Step 6: Write the draft

- Start from `{{ENG_HOME}}/templates/repo-agents.md`.
- Mark every item you inferred but did not confirm with `(inferred, verify)`.
- Write `TODO(you)` for anything that should exist but you could not find.
- If a section or table row does not apply to this repo, **delete it**. Do not write "n/a" and do not explain why it does not apply. Examples: Angular and Playwright rows in a .NET-only repo, the Clean Architecture table in a repo with no layers, the EF Core section in a repo without EF Core.
- **Team guides section:** one row per team guide the engineer did not choose to ignore. Delete the section if there are none.
  - `link` rows: do not repeat what the team guide already says. Write only facts it is missing.
  - `copy` rows: copy the team guide's rules into the matching sections of the draft and end each copied line with `(from <file>)`. Fill in "Synced at" with the output of `git -C $1 log -1 --format=%h -- <file>`.
  - Every disagreement from Step 3 item 11 goes under "Gotchas" as: `<file> says <X>. The code shows <Y>. Follow <Y>.`
- Keep the `## Remembered` section from the template (empty) or from the existing guide (Step 1).
- Write it to the location chosen in Step 1. Ask the engineer to approve the write if prompted.

## Step 7: Hide it from git

- Read `$1/.git/info/exclude`. If it does not contain a line with the guide file name (`AGENTS.md` or `AGENTS.local.md`), add that line at the end. This keeps the file out of commits without changing `.gitignore`.

## Step 8: Hand off

Tell the engineer:
- Where the draft was written, and which guide file it is (`AGENTS.md` or `AGENTS.local.md`).
- Each team guide and the mode chosen (link, copy, or ignore).
- A list of every `(inferred, verify)` item, every `TODO(you)`, and every team guide disagreement, one line each.
- "Review and correct this file before using this repo in the pipeline. Every agent will trust it."
