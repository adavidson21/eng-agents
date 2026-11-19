# Repos for <id>

Lane: <feature | bug | spike>

Change repos in this order. Shared repos come first.

| Order | Repo folder | Branch | Shared? | Why it is involved | Base | Path |
|---|---|---|---|---|---|---|
| 1 | <repo-folder> | <dev/feature/id-short-name> | <yes/no> | <one line> | <origin/main, or main for a repo with no remote> | <empty, or .worktrees/<folder>/<repo>> |

Base is what the branch was made from and what the PR targets. Diffs and reviews compare against it.
Path is where the work happens when the repo folder was busy (a git worktree). Empty: the repo folder.

## Notes

- <anything about cross-repo order, for example "ui-repo needs the new endpoint from api-repo task 3">
