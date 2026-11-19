---
description: "Draft a short PR title and description per repo in pr.md. Usage: /pr <id>"
agent: writer
---

Draft the pull request text for work item **$1**.

## Step 1: Find the work folder and check the review

- Find the folder in `.work/` that starts with `$1-`.
- Read `review.md`. If it does not exist or the verdict is not `READY`, tell the engineer and ask whether to continue anyway. Wait.

## Step 1b: Catch up with the base

Follow "Catch up with the base" in `{{ENG_HOME}}/guides/pipeline.md` for each repo. On a conflict, stop: write it in `progress.md` and tell the engineer (`auto` or not) `Needs you: <repo> conflicts with <base> in <files>.` Then, when the base had new commits (`rebase=clean`), run each repo's Build and All unit tests commands once more; a failure is the same kind of stop. This is the item's last full check before the PR.

## Step 2: Read

- Read `repos.md`, `spec.md` (or `bug.md`, or `quick.md`), and `progress.md`.
- For each repo, take its base from the **Base** column in `repos.md` (`origin/main` if there is no Base column, from an older item).
- For each repo, run `git -C <repo> log --oneline <base>..HEAD` and `git -C <repo> diff --stat <base>...HEAD`.

## Step 3: Write pr.md

- Start from `{{ENG_HOME}}/templates/pr.md`. Write it to the work folder as `pr.md`.
- One section per repo that has commits. In its `Branch:` line, the target is the base without `origin/` (base `origin/develop` gives `-> develop`).
- Title: a short plain summary, under 70 characters.
- Description: one or two sentences that lead with why, then what; then at most 4 bullets; then one testing line (how to test, then what was run). When the change touches UI files, add a `Screenshots:` line: `see the UI check` when `review.md` has a UI PASS for that repo (Workshop shows the before and after shots), else a placeholder. End with the work item link: `AB#<number>` for a linked ADO work item (pipeline guide, Who links to ADO), `Closes owner/repo#<n>` for a GitHub issue (from the `- GitHub:` line in `workitem.md`), and for a local item its id (`L12`).
- **Keep it short.** No headings inside the description. No restating the spec. No list of every file.
- **Checks.** Fill the `## Checks` block at the top of `pr.md` from `review.md` and `progress.md`: builds, unit tests (passed and new), UI tests (passed, or `none in this repo`), docs (what was updated, or `no doc change needed`), clean up (leftovers found and fixed, or `none`), and the review verdict. Copy numbers from the recorded runs; never write a check you did not see pass. Loom shows this block on the card at Ready.

## Step 4: Hand off

- Add a `progress.md` entry for `/pr` with a `- Stats: rebase=<clean, none, skipped or conflict>` line.
- **Run retro.** Run exactly `{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/work/Find-Repeats.ps1" -WorkRoot ".work" -Write`. It suggests fixes for what keeps coming back (in Folio's review list); name any new suggestion in one line. It never blocks.
- In Workshop, the engineer publishes from Loom (Publish pushes every branch and opens the PRs); there is nothing else to run. Otherwise tell the engineer: "PR text is in `pr.md`. Push each branch with `git -C <repo> push -u origin <branch>` (or tell me to, or use Push in Loom), then open the PR on your git host (Azure DevOps, GitHub, or another) targeting `<target>`." Name each repo's target. If they ask you to push, run that command for each repo; each push asks for approval.
- For a repo whose base has no `origin/` (no remote), say there is nothing to push: the work is on `<branch>`, ready to merge into `<base>` locally.
- End with one line: "When it is merged, `/retro $1` turns this item's review findings into rules."
