# Tandem MCP server

`tandem.mjs` is a local MCP server for opencode: the mechanical parts of the pipeline as tools that take a repo folder and a work item id and answer in JSON. A model fills in arguments instead of copying `git` and PowerShell command lines and reading terminal output, which matters most on smaller and self-hosted models.

- **No dependencies.** Node 18 or later, standard library only. Nothing to `npm install`, so it works behind a proxy.
- **No network listener.** opencode starts it and talks over stdio. It only reaches the network when a tool says so (`repo_merge_check` fetches the base; `tests_ensure_env` installs packages and a browser).
- **Installed by `install.ps1`** as the `tandem` entry in `opencode.json` when Node is found (`-NoTandemMcp` skips it). opencode names the tools `tandem_<name>`.

## Tools

| Tool | What it does |
|---|---|
| `repo_check` | Branch vs `repos.md`, uncommitted files, base found, ahead and behind |
| `repo_changes` | Commits, changed files with line counts, uncommitted files, one file's diff |
| `repo_merge_check` | Whether merging the base conflicts, with `git merge-tree` (git 2.38+); changes nothing |
| `repo_commit` | Stages exactly the named files and commits; refuses the wrong branch, other staged files, unchanged files, multi-line messages |
| `checks_list` | The repo guide's Stack, Commands, UI checks and Regression tests tables |
| `checks_run` | A repo guide command (build, unit, precommit, lint, format, or your own line) with test counts, failing names, compiler errors, lint counts; compares with `baseline.md`; `save` keeps the log; `baseline` writes the row |
| `ui_app_start`, `ui_app_stop`, `ui_check`, `tests_suite` | Run `Start-UiApp.ps1`, `Stop-UiApp.ps1`, `Test-Ui.ps1` and `Test-Suite.ps1` and return their result files |
| `tests_detect` | Angular project and port, unit runner, Playwright, config, browsers, test folder, routes, what is missing |
| `tests_ensure_env` | Installs only what is missing: `@playwright/test`, `playwright.config.ts` (webServer on `ng serve`), test folder, Chromium |
| `tests_scaffold` | A new spec with one `[AC-n]` test per criterion, an API mock and `page.goto`; each test fails until written |

Agents that must not change code have the write tools turned off in their frontmatter (`tools:`): chat, hub, quick and people-prep get none; product-manager and pr-reviewer get the read tools; planner, reviewer, investigator and writer get everything except `repo_commit`, `tests_ensure_env` and `tests_scaffold`.

## Where things run

opencode starts the server in the workspace root. A tool given `item` reads `.work/<item>-*/repos.md`: when the repo's row has a Path (a worktree), git runs there, and repo guide commands written from the workspace root (`dotnet test api/tests/...`) are pointed at the worktree. The repo guide itself is read from the repo folder, as the pipeline guide says. On Windows, commands run in PowerShell (`TANDEM_PS`, set by the installer); elsewhere in `/bin/sh`.

## Errors

A failed call returns `isError` with one line starting with a code: `NOREPO`, `NOITEM`, `NOGUIDE`, `NOCOMMAND`, `REFUSED`, `EXISTS`, `GIT`, `NOPS`, `NOSCRIPT`, or `FAILED`.

## Tests

`node --test "core/scripts/mcp/test/*.test.mjs"` (CI runs it on Linux and Windows). The tests build a scratch workspace with a git repo, a repo guide and a work item; nothing needs Playwright, dotnet or the network.
