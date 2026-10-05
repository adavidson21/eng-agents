---
description: "Draft a short PR title and description per repo in pr.md. Usage: /pr <id>"
agent: writer
---

Draft the pull request text for work item **$1**.

## Step 1: Find the work folder and check the review

- Find the folder in `.work/` that starts with `$1-`.
- Read `review.md`. If it does not exist or the verdict is not `READY`, tell the engineer and ask whether to continue anyway. Wait.

## Step 2: Read

- Read `repos.md`, `spec.md` (or `bug.md`), and `progress.md`.
- For each repo, run `git -C <repo> log --oneline origin/main..HEAD` and `git -C <repo> diff --stat origin/main...HEAD`.

## Step 3: Write pr.md

- Start from `{{ENG_HOME}}/templates/pr.md`. Write it to the work folder as `pr.md`.
- One section per repo that has commits.
- Title: a short plain summary, under 70 characters.
- Description: one or two sentences, then at most 4 bullets, then one testing line, then `Work item: #$1`.
- **Keep it short.** No headings inside the description. No restating the spec. No list of every file.

## Step 4: Hand off

- Add a `progress.md` entry for `/pr`.
- Tell the engineer: "PR text is in `pr.md`. Push each branch yourself with `git -C <repo> push -u origin <branch>`, then open the PR in ADO targeting `main`."
