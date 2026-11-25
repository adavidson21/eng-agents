---
description: "After Publish: fix a published PR whose CI failed, or merge its base in when it conflicts, on the branch, without pushing. Usage: /pr-fix <id> ci|conflict [auto]"
agent: implementer
---

Fix the published pull request of work item **$1**. Kind: **$2**. Mode: **$3**

Workshop runs this after Publish, when its watcher sees a failed CI run (`ci`) or a merge conflict with the base (`conflict`) on the item's PR. If the mode above is `auto`, nobody is watching: never ask and never wait; where a step says to stop, write the result and end.

This is the one implementer job with no task in `tasks.md`: the files you may change are the ones the failure points at, at most `taskFileCap` (Factory settings in `{{ENG_HOME}}/guides/pipeline.md`, test files do not count).

The branch is already on the remote and the team may be reviewing it. So:
- **Never rebase, amend, reset or force anything.** Add commits on top.
- **Never push.** Workshop shows **Push fix** and the engineer pushes it.

## Step 1: Find the failure

- Find the folder in `.work/` that starts with `$1-`. Read `repos.md`, `pr.md` and the last 2 entries of `progress.md`.
- `ci`: read the newest `ci/failure-<n>.md` without a `- Result:` line. `conflict`: the newest `ci/conflict-<n>.md` without one. If there is none, say `Nothing to fix for $1.` and stop.
- It names the repo, branch, base and commit. Work in that repo's Path when `repos.md` has one. Run `git -C <repo> branch --show-current`: it must be the branch. Run `git -C <repo> status --porcelain`: it must be clean. Otherwise write `- Result: NEEDS YOU the branch is not checked out cleanly` and stop.
- Read the repo guide and the stack files its `Stack:` line names.

## Step 2a: CI failed (`ci`)

1. Read each failed check's log tail. Decide the cause in one line: a build error, a failing test, a lint or format rule, or the pipeline itself (an agent offline, a timeout with no failing test, a quota, a network or package registry error).
2. **The pipeline itself:** change nothing. Write `- Result: NOT FIXED not caused by this change: <the cause>` and go to Step 3. A rerun on the host is the fix.
3. **Reproduce** with the repo guide's matching command (Build, the failing test's project or filter, or the lint check). If it passes locally, look for what differs (an environment variable, a file the CI builds from, a test that depends on order or time) before changing anything. If you cannot reproduce it and cannot see the cause in the log, change nothing: write `- Result: NOT FIXED could not reproduce: <what you ran>` and go to Step 3.
4. **Fix** with the smallest change that makes the failing command pass, in the files the failure points at. Fix the code, not the test, unless the test itself is wrong for what the spec asks (say so in the Result). Run the failing command after each change; stop after `retries` tries (core rule 6) with `- Result: NOT FIXED <what you tried, last error>`.
5. **Prove it:** run the repo's **Build** command if it has one, then its **All unit tests** command. A failure listed in `baseline.md` was there before the item; anything else must pass.
6. **Commit** only the files you changed: `git -C <repo> add <file> ...`, then `git -C <repo> commit -m "Fix CI: <short summary>"`, following the commit message convention in the pipeline guide (`AB#<id>` only for a linked item). Write `- Result: FIXED <short commit> <one line: the cause and the fix>`.

## Step 2b: Conflict with the base (`conflict`)

0. With the Tandem tools, first run `tandem_repo_merge_check` (repo, item): `needsYou` files mean NEEDS YOU without merging (as in 3).
1. `git -C <repo> fetch origin <base without origin/>`, then `git -C <repo> merge --no-edit <base>`.
2. It merges cleanly: go to 4.
3. It stops on conflicts: list them with `git -C <repo> diff --name-only --diff-filter=U`. Resolve a file only when every conflict in it keeps both sides with no decision about behavior: both sides added different imports, list or table entries, routes, or independent lines next to each other. Lock files and generated files, and anything that needs a decision, are not mechanical: run `git -C <repo> merge --abort`, write `- Result: NEEDS YOU conflicts in <files>`, and go to Step 3.
4. Run the repo's **Build** command if it has one, then its **All unit tests** command. If something fails because of the merge, fix it only if the fix is in a file the merge touched and within the file cap; otherwise `git -C <repo> merge --abort` (or, after the merge commit, leave it uncommitted and abort) and write `- Result: NEEDS YOU the merge breaks <what>`.
5. Commit the merge: `git -C <repo> commit --no-edit` (stage the files you resolved first). Write `- Result: FIXED <short commit> merged <base>`.

## Step 3: Record

- Append the `- Result:` line to the `ci/` file from Step 1 (nothing else in it changes).
- Add a `progress.md` entry for `/pr-fix` with `- Stats: pr-fix=<fixed, not-fixed or needs-you> kind=$2 attempts=<runs of the failing command>`.
- `auto`: end your reply with the Result line and stop.
- Not `auto`: say what you found and did in 2 lines, then: "Push it from Builds (**Push fix**), or `git -C <repo> push`."
