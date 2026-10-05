---
description: "Two-pass review of all changes for a work item: spec compliance, then code quality. Usage: /review <id>"
agent: reviewer
---

Review all changes for work item **$1**.

## Step 1: Find the work folder

- Find the folder in `.work/` that starts with `$1-`.
- Read `repos.md`, `spec.md` (or `bug.md` for the bug lane), `plan.md` if it exists, `tasks.md`, and `progress.md`.
- If any task in `tasks.md` is not checked, list them and ask the engineer whether to review anyway. Wait.

## Step 2: Read the rules

- Read `<repo>/AGENTS.md` for every repo in `repos.md`.

## Step 3: Run the tests

- For each repo, run its "All unit tests" command from its `AGENTS.md`. If the work touched Playwright tests, run the Playwright command too.
- Record each result.

## Step 4: Read the diff

- For each repo, run `git -C <repo> diff --stat origin/main...HEAD`, then `git -C <repo> diff origin/main...HEAD`.
- If the diff is large, read it one file at a time with `git -C <repo> diff origin/main...HEAD -- <file>`.

## Step 5: Pass 1, spec compliance

- For each acceptance criterion, mark `Met`, `Partly met`, or `Not met`. Give the test and file that prove it.
- List changes that no criterion or task asked for.

## Step 6: Pass 2, code quality

Check every changed file against this list and the repo `AGENTS.md`:

- **Architecture:** layer references follow the repo's allowed-references table. Business logic is not in controllers or components.
- **Consistency:** matches the "pattern to follow" files in naming, structure, and error handling.
- **Correctness:** null handling, edge cases, off-by-one, async/await used correctly (no `.Result` or `.Wait()`, `CancellationToken` passed through where the pattern does).
- **EF Core:** no queries inside loops, read-only queries use `AsNoTracking()` if the repo does, no unexpected migration changes.
- **Security:** input validated, authorization not bypassed, no secrets, no personal data in logs.
- **Tests:** test behavior, not implementation details. No skipped or commented-out tests. .NET tests use mocks, no real database.
- **Angular:** subscriptions are cleaned up, no `any` unless the code already uses it, follows existing component patterns.
- **Playwright:** every API call mocked with `page.route`, no fixed waits (`waitForTimeout`), stable selectors.
- **Leftovers:** no debug logging, commented-out code, or TODO comments added.

## Step 7: Write review.md

- Start from `{{ENG_HOME}}/templates/review.md`. Write it to the work folder as `review.md`.
- Verdict is `READY` only if all tests pass, every criterion is `Met`, and there are no Blockers.

## Step 8: Hand off

- Add a `progress.md` entry for `/review`.
- Summarize for the engineer: verdict, number of findings by severity, and the Blockers in one line each.
- If there are findings, ask: "Which findings should become fix tasks?" When they answer, append those tasks to the end of `tasks.md`, numbered after the last task, in the normal task format. Then tell them to run `/do-task $1 <n>` for each in a new session, then `/review $1` again.
- If the verdict is READY, tell them to run `/pr $1`.
