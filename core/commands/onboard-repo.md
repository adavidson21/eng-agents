---
description: "Scan a repo and draft its AGENTS.md for the engineer to review. Usage: /onboard-repo <repo folder>"
agent: investigator
---

Draft the `AGENTS.md` for the repo in folder **$1**.

## Step 1: Check the folder

- `$1` must be a folder in the workspace root that contains a `.git` folder. If not, stop and tell the engineer.
- Decide where to write:
  - If `$1/AGENTS.md` does not exist, you will write to `$1/AGENTS.md`.
  - If it exists, read it. You will write the new draft to `.work/_onboard/$1-AGENTS.md` instead, so the engineer can merge it by hand.

## Step 2: Gather facts

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

## Step 3: Offer to test the commands

- Show the engineer the build and test commands you found. Ask: "Should I run these now to confirm they work? They may take a few minutes." Wait.
- If yes, run them one at a time and record whether each works.

## Step 4: Write the draft

- Start from `{{ENG_HOME}}/templates/repo-agents.md`.
- Mark every item you inferred but did not confirm with `(inferred, verify)`.
- Write `TODO(you)` for anything that should exist but you could not find.
- If a section or table row does not apply to this repo, **delete it**. Do not write "n/a" and do not explain why it does not apply. Examples: Angular and Playwright rows in a .NET-only repo, the Clean Architecture table in a repo with no layers, the EF Core section in a repo without EF Core.
- Write it to the location chosen in Step 1. Ask the engineer to approve the write if prompted.

## Step 5: Hide it from git

- Read `$1/.git/info/exclude`. If it does not contain a line `AGENTS.md`, add that line at the end. This keeps the file out of commits without changing `.gitignore`.

## Step 6: Hand off

Tell the engineer:
- Where the draft was written.
- A list of every `(inferred, verify)` item and every `TODO(you)`, one line each.
- "Review and correct this file before using this repo in the pipeline. Every agent will trust it."
