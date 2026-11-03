---
description: "First-pass review of a teammate's ADO pull request. Drafts comments in .work/pr-<id>/review.md; never posts. Usage: /pr-review <PR link or number> [repo folder or ADO connection] [again]"
agent: pr-reviewer
---

Review pull request **$1**. Arguments: **$ARGUMENTS**

This is someone else's PR. You draft comments for the engineer. You never post, vote, approve, or reject, and you never check out the PR.

## Step 1: Check the arguments

- `$1` is a PR link (it contains `/pullrequest/<number>`) or a PR number.
- Any other argument is either the word `again` (review again even if the commit was already reviewed) or a repo folder in the workspace or an ADO connection name (only needed with a number).
- If `$1` is empty, stop and reply: `Usage: /pr-review <PR link or number> [repo folder or ADO connection] [again]`.

## Step 2: Fetch the PR

For a link, run exactly this command:

```
{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/ado/Get-PullRequest.ps1" -Url "$1" -WorkRoot ".work"
```

For a number, run exactly this command, adding `-From "<repo folder or connection>"` at the end if one was given:

```
{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/ado/Get-PullRequest.ps1" -Id $1 -WorkRoot ".work"
```

- If it succeeds, the last line is the folder (`.work/pr-<id>`). Remember it.
- If the line before it starts with `ALREADY:` and `again` was not given: tell the engineer "This commit was already reviewed. The review is in `<folder>/review.md`. Run `/pr-review $1 again` to review it again." and stop.
- If the error contains:
  - `AMBIGUOUS:` or `UNKNOWN:`: ask "Which repo folder or ADO connection is this PR in?" Run the number command again with `-From "<their answer>"`.
  - `NOCONN:`: tell the engineer the link's server and collection are not in their ADO `config.json`, and stop.
  - `NOREPO:`: tell the engineer which repo to clone into the workspace (the error names it and its URL), and stop.
  - `FETCH:`: show the git error in one line, and stop.
- Any other failure: show the error in one line and stop. Do not try other ways to get the code.

## Step 3: Read the context

- Read `context.md` and `threads.md` in the folder.
- Note the repo folder, the source commit (`<src>`, first 7 characters), and the merge base (`<base>`). Every git command below uses the exact commands from the "Read the code with" table in `context.md`.
- Read the repo guide: `<repo>/AGENTS.local.md` if it exists, otherwise `<repo>/AGENTS.md`. If neither exists, say "No repo guide for `<repo>`; reviewing against general rules only." and continue. (These describe the repo, not the PR, so reading them from disk is fine.)
- If `context.md` lists more than 40 changed files or more than 1500 changed lines, tell the engineer: "This PR is large (`<n>` files, `<lines>` lines). I will review the code files and skip generated files, lock files, and snapshots." Then continue.

## Step 4: Read the diff

- Run the "Changed files" command.
- For each changed file, run the "One file's diff" command. Skip generated files, lock files (`package-lock.json`, `*.lock`), migrations' `Designer` and snapshot files, and binary files; list them under "Checked and fine" as skipped.
- When a change only makes sense with more of the file (a method's callers, a class's fields), run "A whole file as of the PR" for that file, or "Find text in the PR's code" for the callers. Never open the file from disk.
- Stop reading more context for a file once you can judge it. Do not read more than about 30 extra files in total.

## Step 5: Pass 1, intent

- For each acceptance criterion in the linked work items, mark `Met`, `Partly met`, `Not met`, or `Not visible` (the diff does not show enough to tell) and give the file and line, or the test, as evidence.
- If no work item is linked, use the PR description's stated goal as the one criterion.
- List changes in the diff that no criterion and no part of the description asked for.

## Step 6: Pass 2, problems

Go through every changed code file against this list and the repo guide. Only keep findings that pass the four rules in your agent instructions.

1. **Correctness:** wrong logic, null handling, edge cases, off-by-one, wrong conditions, async/await misuse (`.Result`, `.Wait()`, fire-and-forget, `CancellationToken` not passed where the pattern does).
2. **Security and authorization:** missing authorization on a new endpoint, input not validated, secrets or personal data in code or logs, SQL built from strings, internal details returned to clients.
3. **Contracts:** API, DTO, event, or database changes that break callers, without a version or migration.
4. **Error handling:** swallowed exceptions, missing validation, errors that leave data half-written.
5. **Data integrity:** missing transactions across writes, race conditions, EF Core queries inside loops (N+1), missing `AsNoTracking()` where the repo uses it.
6. **Patterns:** what the repo guide says to follow (layers, naming, DI lifetimes). Angular: subscriptions cleaned up, no new `any`, the repo's state pattern.
7. **Tests:** meaningful new logic with no test, tests that test implementation details, skipped or commented-out tests, Playwright tests that call a real environment or use fixed waits.
8. **Build and deploy:** Dockerfile, pipeline, config, or package changes that could break a build or a deploy.
9. **Leftovers:** debug logging, commented-out code, TODOs added without a work item, magic numbers or strings with business meaning.
10. **AI-looking code:** needless abstraction, duplicated helpers that already exist in the repo (check with "Find text in the PR's code").

Drop anything already raised in `threads.md`.

## Step 7: Write review.md

- Start from `{{ENG_HOME}}/templates/pr-review.md`. Write it to the folder as `review.md`.
- `Reviewed commit:` is the first 7 characters of the source commit. `Reviewed:` is today's date.
- Recommendation:
  - `Request changes` if there is any `blocking` comment or any criterion is `Not met`.
  - `Needs clarification` if a question for the author would decide whether it is correct.
  - `Approve after optional cleanup` if the only comments are `optional`, or there are `should-fix` comments you would not hold the merge for.
  - `Approve` if there are no comments.
- Risk: `high` for security, data, contract, or deploy changes; `medium` for business logic; `low` for small, well-tested, or cosmetic changes.
- Number comments `C1`, `C2`, ... with `blocking` first. Each has exactly the four lines (`File`, `Line`, `Severity`, `Why`) and the comment as a `>` quote, in the template's format. `Line` is the line number in the PR's version of the file.
- Write each comment the way a teammate would say it: casual, short, specific, and kind. One or two sentences. Suggest the fix when it is simple. No "Great work, but...", no lectures.

## Step 8: Hand off

- Tell the engineer in four lines or fewer: the recommendation, the risk, how many comments of each severity, and the blocking ones in one line each.
- End with: "Comments are drafts in `<folder>/review.md`. Edit them and post the ones you agree with on the PR yourself: `<PR link from context.md>`."
- Do not offer to post them.
