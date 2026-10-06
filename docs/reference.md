# Reference

Agents, permissions, commands, files, conventions, and what `install.ps1` does. How the phases fit together is in [Pipeline](pipeline.md); layers and overrides are in [Customization](customization.md).

## Agents

Each agent has only the permissions it needs. Every agent may run read-only commands (file reads, search, read-only `git`, version checks). Nothing else is listed unless it differs.

| Agent | Commands | Can edit | Extra shell commands |
|---|---|---|---|
| `planner` | `/start`, `/spec`, `/plan`, `/tasks`, `/status`, `/pause`, `/resume` | `.work/` only | `git fetch origin`, branch creation, the ADO script. Switching branches and WIP commits ask. |
| `implementer` | `/do-task` | Code and tests. `AGENTS.md` asks. | Build, test, lint, `dotnet format`, `npm install` / `ci`, `git add`. `git commit` asks. |
| `reviewer` | `/review`, `/check-docs` | `.work/` only | Build, test, lint. `git add` and `git commit` denied. |
| `investigator` | `/bug`, `/spike`, `/onboard-repo` | `.work/`. A repo `AGENTS.md` and `.git/info/exclude` ask. | Build, test, lint. `git add` and `git commit` denied. |
| `writer` | `/pr`, `/docs` | Any `*.md` file, `docs/`, `.work/` | None. `git add` and `git commit` denied. |

No agent can push. Each agent file lists its permissions in its front matter.

### Permission tiers

The global `core/opencode.json` and every agent use the same tiers. Rules are evaluated top to bottom and the **last match wins**, so the guards at the bottom catch risky commands even when chained after an allowed one.

| Tier | Result | Examples |
|---|---|---|
| Read and inspect | Allowed | `Get-Content`, `Get-ChildItem`, `Select-String`, `rg`, `git status/diff/log/show/blame`, version checks |
| Build, test, lint | Allowed (not planner or writer) | `dotnet build/test/restore`, `npm test`, `npm run lint`, `npx ng test`, `npx playwright test` |
| Agent extras | Per agent | See the table above |
| Anything else | Asks | Unlisted commands, file moves and copies, redirects to files, network calls, starting processes |
| Destructive | Denied | `git push`, `git reset --hard`, `git clean`, `git restore`, `git checkout --`, recursive deletes, `dotnet ef database`, shutdown |

File reads through opencode's own tools are allowed inside the workspace; outside it they ask (except the installed eng-agents folder). Edits are allowed except `.git/` internals and `.env` files; the agents narrow this further.

## Commands

| Command | Agent | What it does |
|---|---|---|
| `/start <id> <feature\|bug>` | planner | Fetches the work item (or offline mode), creates `.work/<id>-<short-name>/`, proposes repos for you to confirm, creates the branch in each |
| `/spec <id>` | planner | Up to 6 clarifying questions, one at a time, then `spec.md` as DRAFT |
| `/plan <id>` | planner | Requires an approved spec. Writes `plan.md`: files per repo, pattern to follow, test plan |
| `/tasks <id>` | planner | Requires an approved plan. Writes `tasks.md`: small tasks with verify commands and a coverage check |
| `/do-task <id> <n>` | implementer | Does task `n` only: TDD for .NET, verify, check the box, log to `progress.md`, commit |
| `/review <id>` | reviewer | Runs tests, reviews the diff in two passes, writes `review.md`, turns accepted findings into tasks |
| `/pr <id>` | writer | Writes `pr.md`: short title and description per repo |
| `/bug <id>` | investigator | Root cause with confidence, `bug.md` as DRAFT, and up to 3 tasks |
| `/spike <id or topic>` | investigator | Read-only investigation (about 25 files max), writes `findings.md` |
| `/docs <target>` | writer | Clarifies audience, outlines, writes the doc, saves a sources list |
| `/check-docs <doc path>` | reviewer | Fact-checks every claim in a doc against the code, writes `check.md` |
| `/onboard-repo <folder>` | investigator | Drafts the repo's `AGENTS.md` and adds it to `.git/info/exclude`. **Review it.** |
| `/status [id]` | planner | Where an item stands and the next command, or a table of all items |
| `/pause <id> [reason]` | planner | Writes `paused.md`, offers a WIP commit for uncommitted changes |
| `/resume <id>` | planner | Restores branches, warns if `main` moved, gives the next command |

## Work files

All pipeline state lives in the workspace, outside every git repo. It never leaves the work PC.

```
.work/<id>-<short-name>/
  workitem.md     work item text (fetched or pasted)
  repos.md        lane, repos in order, branch per repo
  spec.md         goal, acceptance criteria, non-goals, decisions, open questions
  plan.md         approach, changes per repo, test plan, risks
  tasks.md        numbered checkbox tasks with verify commands
  progress.md     append-only log, including verify output
  review.md       findings and verdict
  pr.md           PR title and description, one section per repo
  bug.md          bug lane only
  findings.md     spike on a work item
  paused.md       written by /pause

.work/spike-<short-name>/findings.md     spike without a work item
.work/docs-<short-name>/sources.md       docs lane: claims and source files
.work/docs-<short-name>/check.md         docs lane: fact-check results
.work/_onboard/<repo>-AGENTS.md          onboard draft when the repo already has an AGENTS.md
```

## Conventions

Core defaults. Override them in your Personal or Company `AGENTS.md`.

| Item | Default |
|---|---|
| Base branch and PR target | `main` |
| Feature branch | `dev/feature/<id>-<short-name>` |
| Bug branch | `dev/bug/<id>-<short-name>` |
| `<short-name>` | First 5 words of the work item title, lowercase, filler words dropped, hyphenated, max 40 characters |
| Commit message | Short plain summary, no prefix or work item number (`Add retry to export job`) |
| Task size | At most 3 files, one repo |
| Shell | PowerShell, one command per call |

## Testing rules

Every test must run locally **without a database, real backend, or shared environment**.

| Code | Framework | Rule |
|---|---|---|
| .NET | xUnit | **Strict TDD**: write the test, confirm it fails for the right reason, implement, confirm it passes. Mock dependencies. |
| Angular | The repo's unit test runner | Tests required, any order. Headless, single run. |
| Playwright | Playwright | Tests required, any order. Mock every API call with `page.route`. Use the repo's mock helpers. |

A task is not done until its verify command passes and the output is in `progress.md`.

## Workspace layout

```
C:\src\work\                 not a git repo; launch opencode here
  AGENTS.md                  repo map
  .work\                     pipeline state
  <shared-repo>\             cloned once, used by the repos below
  <api-repo>\
  <ui-repo>\
```

- Repos sit flat, side by side. No per-project subfolders.
- opencode loads `AGENTS.md` from the launch folder upward, so the repo map loads but per-repo guides do not. Every command reads `<repo>\AGENTS.md` before touching that repo.
- Each repo's `AGENTS.md` is hidden via `.git\info\exclude`. The company `.gitignore` is never changed.

### Shared repos

- Consumers reference shared code by relative path (for example `..\..\<shared-repo>\src\Lib.csproj`), so one flat clone satisfies them all. Duplicate clones drift apart.
- Record each dependency with one example path in the repo map. `/onboard-repo` also records it in the consumer's `AGENTS.md`.
- Shared repos change first, then the tests of every affected consumer run. If a shared repo is ever consumed as a published package instead, the plan needs a version bump task; note that in the repo map.
- One clone has one branch checked out. For parallel work on a shared repo, add a worktree:

  ```powershell
  cd C:\src\work\<shared-repo>
  git worktree add ..\<shared-repo>-12345 dev/feature/12345-short-name
  ```

  Remove it with `git worktree remove ..\<shared-repo>-12345` after the PR merges. Relative-path consumers still point at the main clone.

## Repo layout

```
eng-agents/
  README.md                 daily usage
  CONTRIBUTING.md           changing Core
  install.ps1               layers Core + Personal + Company into the opencode config
  core/
    AGENTS.md               rules for every session
    opencode.json           permissions only (no provider or model)
    agents/                 planner, implementer, reviewer, investigator, writer
    commands/               the 15 commands above
    templates/              one template per work file, plus repo-agents.md
    scripts/ado/            Get-WorkItem.ps1, config.example.json
  personal/TODO.md          placeholder; your fork adds your files here
  company/                  gitignored except TODO.md and repo-map.template.md
  docs/
```

Work PC only:

```
%USERPROFILE%\.config\eng-agents\
  config.json               ADO server, collection, project, api-version, auth
  overlay\                  same shape as core\ (AGENTS.md, opencode.json, agents\, commands\, templates\)
ADO_PAT                     user environment variable, never in a file
C:\src\work\AGENTS.md, .work\, <repo>\AGENTS.md
```

## What install.ps1 does

| Writes to the opencode config folder | Content |
|---|---|
| `agents\*.md`, `commands\*.md` | Layered files. A later layer replaces a same-named file. |
| `AGENTS.md` | One section per layer between `eng-agents:begin` / `eng-agents:end` markers. Your text outside the markers is kept. HTML comments are stripped. |
| `opencode.json` | Layer permissions merged into your file. Provider and model settings are kept. An `opencode.jsonc` or unparseable file is left alone and the permissions are written to `opencode.eng-agents.json` for you to merge. |
| `eng-agents\templates\`, `eng-agents\scripts\` | Templates and scripts |
| `eng-agents\manifest.json` | What was installed, so files removed from a layer are cleaned up next time |
| `eng-agents\backup\<time>\` | Copies of anything overwritten |

Tokens replaced in installed files: `{{ENG_HOME}}` becomes the `eng-agents` folder path; `{{PS}}` becomes `powershell` (Windows PowerShell 5.1) or `pwsh` (PowerShell 7).

| Flag | Effect |
|---|---|
| `-DryRun` | Preview, write nothing |
| `-CoreOnly` | Skip Personal and Company |
| `-Target <path>` | opencode config folder (default `~/.config/opencode`) |
| `-Personal <path>` | Personal layer (default `personal/` next to the script) |
| `-Company <path>` | Company overlay (default `~/.config/eng-agents/overlay`) |

A layer is skipped if it has none of `AGENTS.md`, `opencode.json`, `agents/`, `commands/`, `templates/`, `scripts/`. Install warns if a Personal or Company `AGENTS.md` still contains `TODO(you)`, refuses to run as root, and ends with two ADO checks (config file, `ADO_PAT`).

## Assumptions to verify at work

| Assumption | How to check | If wrong |
|---|---|---|
| opencode's Windows config folder is `%USERPROFILE%\.config\opencode` | Look for `opencode.json` there or in `%APPDATA%\opencode` | Reinstall with `-Target <path>` |
| opencode runs shell commands in PowerShell | Day-one check 2 | Tell the agents the shell in your overlay `AGENTS.md` |
| Edit path patterns (`.work/**`) match on Windows | Day-one checks 3 and 4 | Change `edit` to `ask` in the read-only agents and reinstall |
| Installed templates are readable without an external directory prompt | Day-one check 5 | Approve with "always", or add the path to your overlay `opencode.json` |
| ADO Server supports api-version `6.0` | Run `Get-WorkItem.ps1` on a known item | Set `apiVersion` to `5.1` |
| The ADO script's HTML-to-text output is readable | Fetch a richly formatted item and open `workitem.md` | Paste details by hand for that item; report the pattern |
| Angular unit tests run with one headless command | Check `angular.json` and `package.json` | Record the right command in the UI repo `AGENTS.md` |
| Shared-repo consumers build from the flat layout | Build one consumer from `C:\src\work` | Rename folders to match the relative paths |
| `install.ps1` works in Windows PowerShell 5.1 | Run it at work | Use PowerShell 7 (`pwsh`) |
