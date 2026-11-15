# Test baseline: <id> <title>

Written by `/start` right after the branches were created, before any change. `/do-task` reads it to tell old failures from new ones. Re-run a repo's command and update its row if the base branch changes.

| Repo | Command | Result | Failing tests before this work item |
|---|---|---|---|
| <repo-folder> | `<Pre-commit check or All unit tests command>` | <PASS / FAIL / no command / could not run> | <test names, a count if more than 20, or "none"> |
