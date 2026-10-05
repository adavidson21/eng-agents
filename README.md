# eng-agents

An opencode workspace that takes work from an Azure DevOps work item to a ready-to-open pull request, using a small set of narrowly scoped agents and slash commands.

It is designed for a capable but slower, less forgiving model (a Qwen-class model). Everything here leans on four ideas:

1. **Small steps.** Every task touches 1 to 3 files and has one exact command that proves it is done.
2. **Files are the memory.** Specs, plans, tasks and progress live on disk, so any fresh session can pick up exactly where the last one stopped.
3. **You trigger each phase.** Slash commands are explicit. Nothing depends on the model deciding on its own to load a skill.
4. **Humans gate the expensive decisions.** You approve the spec and the plan before any code is written.

> **Status:** v1 built, not yet run at work. Track what you have reviewed in [REVIEW.md](REVIEW.md). First-day setup is in [docs/setup-at-work.md](docs/setup-at-work.md). Design rationale and recovery steps are in [docs/pipeline.md](docs/pipeline.md).

---

## Table of contents

- [The three layers](#the-three-layers)
- [The pipeline](#the-pipeline)
- [Lanes](#lanes)
- [Agents](#agents)
- [Commands](#commands)
- [Work artifacts](#work-artifacts)
- [Default conventions](#default-conventions)
- [Testing rules](#testing-rules)
- [Workspace layout at work](#workspace-layout-at-work)
- [Repo layout](#repo-layout)
- [Setup](#setup)
- [Customization guide by layer](#customization-guide-by-layer)
- [Sharing with your team later](#sharing-with-your-team-later)
- [Assumptions to verify at work](#assumptions-to-verify-at-work)
- [Example: one feature, start to finish](#example-one-feature-start-to-finish)
- [Tuning when the model struggles](#tuning-when-the-model-struggles)
- [Review tracker](#review-tracker)

---

## The three layers

Every file in this setup belongs to exactly one layer. The layer decides where the file lives and who can ever see it.

| | Layer 1: Core | Layer 2: Personal | Layer 3: Company |
|---|---|---|---|
| **What it is** | The generic pipeline. Works at any company, for any engineer. | How *you* like to work. Your taste, not your employer's details. | Anything that names or describes your employer, its code, or its systems. |
| **Examples** | Agents, commands, templates, install script, ADO scripts with placeholders | House rules, auto-commit preference, task size limit, model overrides, extra EM commands | Repo map, per-repo `AGENTS.md`, ADO server URL, PAT, test helper locations, team PR sections, all `.work\` state |
| **Lives in** | `core/` in this repo | `personal/` in this repo | Work PC only |
| **Shareable with team?** | Yes, that is the goal | No. Each person writes their own. | Only through company-hosted locations, never this repo |

### Which layer does this belong in?

Ask in order and stop at the first yes:

1. Does it name or describe a company repo, server, product, team, customer, or work item? **Company.**
2. Is it true at any company, but it reflects your personal preference? **Personal.**
3. Otherwise: **Core.**

### How the layers combine

`install.ps1` builds your opencode config by layering, in order:

```
core/                                    generic defaults
  + personal/                            your preferences
  + %USERPROFILE%\.config\eng-agents\overlay\   company specifics (work PC only)
  = opencode global config folder
```

- **Agents, commands, templates:** a file in a later layer with the same name replaces the earlier one. New names are added.
- **`AGENTS.md`:** not replaced. Each layer's `AGENTS.md` is appended as its own section (Core, then Personal, then Company). Core rules tell the model that when sections conflict, the later section wins.
- **`opencode.json`:** permission entries are merged. A later layer's entry for the same key wins.

So you never edit core to express a preference. You override it in a higher layer.

---

## The pipeline

```
ADO work item #12345
   |
   v
/start 12345 feature   pull work item, create .work folder, create branch(es)
   |
   v
/spec 12345            planner asks clarifying questions ONE at a time, writes spec.md
   |                   >>> GATE: you edit spec.md, then set "Status: APPROVED"
   v
/plan 12345            planner writes plan.md: approach, files per repo, repo order, risks
   |                   >>> GATE: you edit plan.md, then set "Status: APPROVED"
   v
/tasks 12345           planner writes tasks.md: tiny tasks, each with a verify command
   |                   >>> GATE: you skim task sizes
   v
/do-task 12345 1       implementer does ONE task in a FRESH session, TDD, checks the box
/do-task 12345 2       repeat until tasks.md is all checked
   ...
   |
   v
/review 12345          reviewer: pass 1 = matches spec? pass 2 = code quality?
   |                   >>> GATE: you fix or accept findings
   v
/pr 12345              writes pr.md: short title + short description
   |
   v
You push and open the PR in ADO. Normal review and CI/CD take it to production.
```

The agents stop at the PR on purpose. Your existing pipeline, approvals and release process own production.

**Gates are a line in a file.** `spec.md`, `plan.md`, and `bug.md` start as `Status: DRAFT`. You approve by editing that line to `Status: APPROVED`. The next command refuses to run until you do. Agents are told never to change it.

---

## Lanes

| Lane | When to use | Flow |
|---|---|---|
| **Feature** | New behavior with acceptance criteria | `/start` → `/spec` → `/plan` → `/tasks` → `/do-task` (repeat) → `/review` → `/pr` |
| **Bug (fast lane)** | A defect with a reproducible symptom | `/start` → `/bug` → `/do-task` (repeat) → `/review` → `/pr` |
| **Spike** | A question you need answered before committing to an approach | `/spike` → `findings.md` (read only, no code changes). Can feed into `/spec`. |
| **Docs** | Writing or updating documentation | `/docs` (writer drafts) → new session → `/check-docs` (reviewer fact-checks every claim against the code) |

**Bug lane rules**

- `/bug` produces `bug.md`: repro steps, expected vs actual, suspected root cause, and the failing test that proves the bug.
- The bug lane skips `/plan` and `/tasks`. `bug.md` contains at most 3 tasks.
- If the root cause is unclear after `/bug`, stop and run `/spike` instead of guessing.
- If the fix needs more than 3 tasks, it is not a fast-lane bug. Move it to the feature lane.

---

## Agents

Each agent has the fewest permissions it needs. Weaker models do better when they cannot wander.

| Agent | Purpose | Read code | Edit code | Write `.work\` | Run shell |
|---|---|---|---|---|---|
| `planner` | Specs, plans, task breakdowns | Yes | **No** | Yes | Read-only commands |
| `implementer` | Executes exactly one task | Yes | Yes | `tasks.md`, `progress.md` only | Yes (build, test, lint, git commit) |
| `reviewer` | Two-pass review against spec, then quality | Yes | **No** | `review.md` only | Tests and lint only |
| `investigator` | Spikes and bug root-causing | Yes | **No** | Yes | Read-only commands, tests |
| `writer` | Documentation and PR text | Yes | Docs files only | Yes | No |

No agent can run `git push`. Pushing is always you.

---

## Commands

| Command | Agent | What it does |
|---|---|---|
| `/start <id> <feature\|bug>` | planner | Fetches the work item (or asks you to paste it), creates `.work\<id>-<slug>\`, asks which repos are involved, creates the branch in each. |
| `/spec <id>` | planner | Clarifying questions one at a time, then writes `spec.md` from the template. |
| `/plan <id>` | planner | Reads `spec.md` plus the relevant repo `AGENTS.md` files, writes `plan.md`. |
| `/tasks <id>` | planner | Breaks `plan.md` into numbered tasks in `tasks.md`. Each task lists repo, files, change, and verify command. |
| `/do-task <id> <n>` | implementer | Does task `n` only. Writes the test first (for .NET), runs verify, checks the box, appends to `progress.md`, commits. |
| `/review <id>` | reviewer | Runs all tests, then reviews the full diff: pass 1 spec compliance, pass 2 code quality. Writes `review.md`. |
| `/pr <id>` | writer | Writes `pr.md`: a short title and a short description with test evidence. One per repo touched. |
| `/bug <id>` | investigator | Reproduces, root-causes, writes `bug.md` with up to 3 tasks. |
| `/spike <id-or-topic>` | investigator | Timeboxed investigation, writes `findings.md`. No code changes. |
| `/docs <target>` | writer | Clarifies audience, outlines, drafts or updates docs, saves a sources list. |
| `/check-docs <path>` | reviewer | Fact-checks every claim in a doc against the code. |
| `/onboard-repo <folder>` | investigator | Scans a repo and drafts its local `AGENTS.md`. **You must review it.** |
| `/status [id]` | planner | Reads `.work\` and tells you where you left off and what to run next. |
| `/standup [days]` | planner | **Personal layer example.** Drafts Yesterday / Today / Blockers from all progress logs. |

**Golden rule:** start a fresh opencode session (`/new`) for every `/do-task`. Long sessions are where slower models drift.

---

## Work artifacts

All pipeline state lives in the workspace, outside every git repo. This is Layer 3 content: it never leaves the work PC.

```
.work\12345-short-name\
  workitem.md     raw work item text (fetched or pasted)
  repos.md        which repos this item touches, and the order to change them in
  spec.md         goal, acceptance criteria, non-goals, open questions
  plan.md         approach, files per repo, risks
  tasks.md        numbered checkbox tasks with verify commands
  progress.md     append-only log: what each session did and the verify output
  review.md       reviewer findings
  pr.md           PR title and description (one section per repo)
  bug.md          bug lane only
  findings.md     spike lane only

.work\spike-short-name\findings.md     spikes without a work item
.work\docs-short-name\sources.md       docs lane: claims and their source files
.work\docs-short-name\check.md         docs lane: fact-check results
.work\_onboard\<repo>-AGENTS.md        onboard draft when a repo AGENTS.md already exists
```

---

## Default conventions

These are Core defaults. Override any of them in your Personal or Company `AGENTS.md` section.

| Item | Default |
|---|---|
| Base branch | `main` |
| PR target | `main` |
| Feature branch | `dev/feature/<id>-short-name` |
| Bug branch | `dev/bug/<id>-short-name` |
| Commit message | Short summary only (for example: `Add retry to export job`) |
| PR output | Draft title and short description only. You open the PR yourself. |
| Shell | PowerShell |

`short-name` is 3 to 5 lowercase words from the work item title, hyphenated.

---

## Testing rules

The agent must be able to run every test locally **without a database, real backend, or shared environment**.

| Layer | Framework | Rule |
|---|---|---|
| .NET | xUnit | **Strict TDD.** Write the failing test, run it, confirm it fails for the right reason, implement, confirm it passes. Unit tests with mocked dependencies against the Application and Domain layers. No DB. |
| Angular | Project's existing unit test runner | Tests required. Order is flexible. Run headless. |
| Playwright | Playwright | Tests required. Order is flexible. Run against `ng serve` with the API **mocked via `page.route`**. Never hit a real environment. |

A task is not done until its verify command passes and the output is pasted into `progress.md`.

---

## Workspace layout at work

```
C:\src\work\                       NOT a git repo. Launch opencode from here.
  AGENTS.md                        repo map (Layer 3, you write it from the template)
  .work\                           pipeline state (Layer 3)
  <shared-repo>\                   cloned ONCE, used by every project below
  <api-repo-a>\
  <ui-repo-a>\
  <api-repo-b>\
  ...
```

- All repos sit **flat, side by side**, in one folder. Do not group them into per-project subfolders.
- opencode finds `AGENTS.md` by walking **up** from the folder you launch in. Launching from `C:\src\work\` loads the workspace `AGENTS.md`, but **not** the per-repo ones. Every command therefore tells the agent to read `<repo>\AGENTS.md` before touching that repo.
- Each repo's `AGENTS.md` is hidden from git via `.git\info\exclude`, a local-only ignore file. The company's `.gitignore` is never modified.

### Shared repos used by multiple projects

A shared monorepo (one that several other repos depend on) gets special handling:

1. **Clone it once, as a sibling** of everything else. This setup assumes consumers reference shared code by **relative path** (for example `..\..\<shared-repo>\src\Lib.csproj`). A flat layout with the expected folder names satisfies every consumer at once. Duplicate clones drift apart and cause "works here, fails there" bugs.
2. **Record the references** in the workspace `AGENTS.md` repo map: which repos depend on the shared repo, with one example path each. `/onboard-repo` also records them in each consumer's `AGENTS.md`.
3. **Plan shared changes first.** When a work item touches the shared repo, `repos.md`, `plan.md`, and `tasks.md` put it first. Because references are relative, consumers see the change immediately, so run the tests of every affected consumer. (If a shared repo is ever consumed as a published package instead, the plan needs a version bump task. Note that in the repo map.)
4. **Use worktrees for parallel work.** One clone can only have one branch checked out. If two work items both need shared-repo changes at the same time, add a worktree instead of a second clone:

   ```powershell
   cd C:\src\work\<shared-repo>
   git worktree add ..\<shared-repo>-12345 dev/feature/12345-short-name
   ```

   Remove it with `git worktree remove ..\<shared-repo>-12345` after the PR merges. Note that relative-path consumers still point at the main clone, so only build consumers against a worktree if you redirect their references.

---

## Repo layout

### This repo (Layers 1 and 2)

```
eng-agents/
  README.md
  REVIEW.md                         review tracker: what each file does, what you must check
  install.ps1                       layers core + personal + company into opencode config
  core/                             LAYER 1: generic, team-shareable
    AGENTS.md                       universal rules for every session
    opencode.json                   permissions only. No provider, no model.
    agents/
      planner.md  implementer.md  reviewer.md  investigator.md  writer.md
    commands/
      start.md  spec.md  plan.md  tasks.md  do-task.md  review.md  pr.md
      bug.md  spike.md  docs.md  check-docs.md  onboard-repo.md  status.md
    templates/
      spec.md  plan.md  tasks.md  progress.md  review.md  pr.md
      bug.md  findings.md  repos.md  workitem.md  repo-agents.md
    scripts/
      ado/
        Get-WorkItem.ps1            reads a work item via REST, creates the .work folder
        config.example.json         placeholder connection settings
  personal/                         LAYER 2: your preferences
    AGENTS.md                       your house rules section
    commands/standup.md             example EM-only command
    (opencode.json, agents/, templates/ are optional; add them when you need an override)
  workspace-template/               Layer 3 starting points. Copied to the work PC, filled in there.
    AGENTS.md                       fill-in-the-blanks repo map (SAMPLE data)
    company-overlay/
      AGENTS.md                     company-wide rules (SAMPLE data)
      README.md                     what you can put in the overlay
  docs/
    pipeline.md                     design rationale, gates, lanes, recovery
    setup-at-work.md                step-by-step first-day setup and verification
```

### What install.ps1 writes

| Destination (in your opencode config folder) | Content |
|---|---|
| `agents\*.md`, `commands\*.md` | Layered files. A later layer replaces a same-named file. |
| `AGENTS.md` | One section per layer, inside `eng-agents:begin` / `eng-agents:end` markers. Your own text outside the markers is kept. HTML comments (your notes) are stripped. |
| `opencode.json` | Layer permissions merged into your existing file. Provider and model settings are kept. |
| `eng-agents\templates\`, `eng-agents\scripts\` | Templates and scripts. Commands find them via the `{{ENG_HOME}}` token, which install replaces with the real path. |
| `eng-agents\manifest.json` | What was installed, so files you delete from a layer are cleaned up next time. |
| `eng-agents\backup\<time>\` | A copy of anything that was overwritten. |

Use `-DryRun` to preview, `-CoreOnly` to skip Personal and Company, `-Target`, `-Personal`, `-Company` to change locations.

### Work PC only (Layer 3)

```
%USERPROFILE%\.config\eng-agents\
  config.json                       ADO server, collection, project, api-version
  overlay\                          company overlay, same shape as core\
    AGENTS.md                       company rules section
    opencode.json                   optional
    agents\  commands\  templates\  optional overrides

C:\src\work\
  AGENTS.md                         repo map
  .work\                            pipeline state
  <each repo>\AGENTS.md             per-repo guide (git-excluded)

Environment variable: ADO_PAT       (user-level, never in a file)
```

---

## Setup

### At home (building and changing Layers 1 and 2)

1. Edit `core\` only for changes that would help anyone. Edit `personal\` for your own preferences.
2. Optional: test changes against a personal project with a similar open model before taking them to work.
3. Commit and push. Run the [layer test](#which-layer-does-this-belong-in) on anything you are unsure of.

### At work (first time)

Full commands and the verification checklist are in [docs/setup-at-work.md](docs/setup-at-work.md). In short:

1. **Clone** this repo somewhere outside the workspace, for example `C:\tools\eng-agents`.
2. **Create the company overlay:** copy `workspace-template\company-overlay\` to `%USERPROFILE%\.config\eng-agents\overlay\` and fill it in.
3. **ADO:** create a PAT, set the `ADO_PAT` environment variable, copy `config.example.json` to `%USERPROFILE%\.config\eng-agents\config.json` and fill it in.
4. **Install:** run `.\install.ps1 -DryRun`, then `.\install.ps1`. Use `-Target <path>` if your opencode config folder is not the default (see [Assumptions](#assumptions-to-verify-at-work)).
5. **Workspace:** create `C:\src\work\`, clone all repos flat into it (shared repos once), copy `workspace-template\AGENTS.md` to `C:\src\work\AGENTS.md`, and fill it in.
6. **Onboard repos:** from `C:\src\work\`, run `/onboard-repo <repo-folder>` for each repo, shared repos first. It also adds `AGENTS.md` to the repo's `.git\info\exclude`. Review and correct each generated `AGENTS.md`.
7. **Verify:** run the day-one checks in the setup doc.
8. **Smoke test:** run `/start` on a small, low-risk bug and walk the bug lane end to end.

### At work (updating)

`git pull` in your clone, then re-run `.\install.ps1`. Layer 3 files are untouched because they live outside this repo. Re-running install also picks up edits to your company overlay.

---

## Customization guide by layer

### Layer 1: Core (this repo, `core\`)

Edit core only when the change would help **anyone** using this pipeline. Keep it free of company and personal detail.

| What | File | Why you might change it |
|---|---|---|
| Global permission baseline, in three tiers (see below) | `core\opencode.json` | Safe baseline for everyone. Loosen per person in Personal, not here. |
| Agent behavior and per-agent permissions (for example, the implementer may run `dotnet`, `npm`, `npx` test/build/lint commands and `git add`; `git commit` asks) | `core\agents\*.md` | Fixing a flaw in how an agent works for everyone. |
| Command steps | `core\commands\*.md` | Fixing or improving a phase of the pipeline. |
| Default templates | `core\templates\*.md` | Better structure for specs, plans, tasks, PRs. |
| Default conventions | `core\AGENTS.md` | Changing a default that should apply to everyone. |

**Permission tiers.** Every agent and the global config use the same tiers. Rules are evaluated top to bottom and the **last match wins**, so the guards at the bottom catch risky commands even when piped after an allowed one.

| Tier | Result | Examples |
|---|---|---|
| Read and inspect | Allowed | `Get-Content`, `Get-ChildItem`, `Select-String`, `rg`, read-only `git` (status, diff, log, show, blame), version checks |
| Build, test, lint | Allowed (not for planner or writer) | `dotnet build/test/restore`, `npm test`, `npm run lint`, `npx ng test`, `npx playwright test` |
| Anything else | Asks you | Unlisted commands, file moves and copies, redirects to files, network calls, starting processes |
| Agent extras | Per agent | Implementer: `npm install`, `dotnet format`, `git add` allowed, `git commit` asks. Planner: branch creation, ADO script. |
| Destructive | Denied | `git push`, `git reset --hard`, `git clean`, `git restore`, recursive deletes, database updates, shutdown |

File reads through opencode's own read, search, and list tools are always allowed inside the workspace. Files outside the workspace ask first. Edits are allowed except `.git` internals and `.env` files (pipeline agents narrow this further).

The tier lists are repeated in each agent file so they apply no matter how opencode merges agent and global rules. When you change one, change it everywhere.

### Layer 2: Personal (this repo, `personal\`)

How **you** like to work as an engineering manager. Still no company content. A teammate would write their own version of this folder.

| What | File | Why it is personal |
|---|---|---|
| House rules: naming, patterns you prefer or avoid, how terse output should be, writing style rules (for example, no em dashes) | `personal\AGENTS.md` | Your taste, applied to every session. |
| Whether the implementer commits after each passing task (core default: yes, with an approval prompt) | A rule in `personal\AGENTS.md` (a SAMPLE line is already there) | Some people prefer committing by hand. |
| Task size cap (core default: 3 files) | A rule in `personal\AGENTS.md` (a SAMPLE line is already there) | Depends on how much you trust the model after real use. |
| Looser or tighter shell permissions | `personal\opencode.json` | Your risk tolerance. |
| Per-agent model override | `model:` in a personal agent override | Only if your setup offers more than one model. |
| EM-specific extras (`/standup` is included as an example) | `personal\commands\` | Useful to you, not necessarily to an IC. |

### Layer 3: Company (work PC only)

Anything that names or describes your employer. It never goes in this repo.

**Must do before first use**

| # | What | Where | Why it is Layer 3 |
|---|---|---|---|
| 1 | Create an ADO PAT with **Work Items (Read)** and **Code (Read)** | ADO Server, your profile | Credentials. Only add Code (Read & Write) if you later want PRs created automatically. |
| 2 | Store the PAT as a user-level environment variable `ADO_PAT` | Your machine | Keeps the token out of every file. |
| 3 | Fill in `config.json`: server URL, collection, project, api-version | `%USERPROFILE%\.config\eng-agents\config.json` | Company URLs and names. api-version is a setting because your ADO Server version is unconfirmed. |
| 4 | Write the workspace repo map: each repo's folder name, purpose, which repos reference the shared repo (with an example relative path), which repos usually change together, and domain glossary terms | `C:\src\work\AGENTS.md` | Only you know how the repos relate. The planner uses this to decide which repos a feature touches and in what order. A wrong map produces wrong plans. |
| 5 | Review every `/onboard-repo` output | `C:\src\work\<repo>\AGENTS.md` | Every future session trusts it blindly. A wrong build command or misread architecture layer gets repeated in every task. |
| 6 | Confirm `AGENTS.md` is in `.git\info\exclude` in each repo (`/onboard-repo` adds it) | Each repo | Keeps local agent files out of company commits. |

**Should do early**

| # | What | Where | Why it matters |
|---|---|---|---|
| 7 | Point the UI repo guide at existing Playwright mock helpers (fixtures, mock data, `page.route` utilities) | `C:\src\work\<ui-repo>\AGENTS.md` | Without this, the model invents a new mocking style per test. |
| 8 | Point each repo guide at its architecture doc, if one exists, and list Clean Architecture layer rules (what may reference what) | Each repo `AGENTS.md` | Layer violations are the most likely mistake, and the reviewer only catches what is written down. |
| 9 | Team-specific PR sections, if your team expects any | `overlay\templates\pr.md` | Team conventions are company detail. Keep it short. |
| 10 | Company-wide rules that apply across all repos (for example, a required logging pattern) | `overlay\AGENTS.md` | Applies to every session at work without touching core. |

### Never do

- Put company names, URLs, code, or work item content in this repo, in either `core\` or `personal\`.
- Put the PAT in any file.
- Let an agent push, merge, or deploy.
- Skip reviewing `spec.md`, `plan.md`, or a generated repo `AGENTS.md`. Those drive everything downstream.

---

## Sharing with your team later

The layers are designed so you can share Core without exposing anything else.

1. **Prove it works for you first.** Run several real work items through every lane and fold the fixes into `core\`.
2. **Split Personal out.** Move `personal\` to its own private repo (for example, `eng-agents-personal`) and point `install.ps1 -Personal <path>` at it. Core is now the only thing left in this repo.
3. **Decide where the team copy lives.** If company policy prefers internal hosting, push Core to a company ADO repo. Company-specific shared content (a team overlay, repo `AGENTS.md` files) can live there too, since it is company-hosted.
4. **Consider committing repo guides.** Once the team uses this, each repo's `AGENTS.md` could be committed to the repo itself instead of git-excluded, so everyone benefits from one reviewed copy.
5. **Teammates install Core, then add their own Personal layer and the shared Company overlay.**

---

## Assumptions to verify at work

| Assumption | How to check | If wrong |
|---|---|---|
| opencode's global config folder on Windows is `%USERPROFILE%\.config\opencode` | Look for an existing `opencode.json` there or in `%APPDATA%\opencode` | Re-run `install.ps1 -Target <correct path>` |
| opencode runs shell commands in PowerShell | Ask opencode to run `$PSVersionTable.PSVersion` | Adjust script calls in commands to match the shell it uses |
| Per-repo `AGENTS.md` is not auto-loaded when launching from the workspace root | Launch from `C:\src\work\` and ask what a repo's `AGENTS.md` says without telling it to read the file | If it already knows, the explicit read step is harmless; leave it |
| ADO Server supports REST api-version `6.0` | Run `Get-WorkItem.ps1` against a known work item | Lower `apiVersion` in `config.json` (for example `5.1`) |
| Angular unit tests run with a single headless command | Check `angular.json` and `package.json` test scripts | Record the right command in the UI repo `AGENTS.md` |
| Consumers of the shared repo build correctly from a flat sibling layout | Build one consumer from `C:\src\work\` | Rename folders to match the relative paths the consumers expect |
| Edit permission path patterns (`.work/**`) match on Windows | Day-one check 3 in the setup doc | Change `edit` to `ask` in the read-only agents and reinstall |
| `external_directory` allows reading the installed templates without prompting | Day-one check 5 in the setup doc | Approve once with "always", or add the exact path in your overlay `opencode.json` |
| The ADO script's HTML-to-text conversion is readable for your work items | Fetch a work item with rich formatting and open `workitem.md` | Paste the details by hand for that item; report the pattern so the script can be improved |

---

## Example: one feature, start to finish

```
cd C:\src\work
opencode

/start 12345 feature
  -> pulls #12345, creates .work\12345-export-retry\
  -> asks: which repos? you answer: shared-repo, api-repo
  -> writes repos.md (shared-repo first), creates dev/feature/12345-export-retry in both

/spec 12345
  -> asks 3 to 6 questions, one at a time
  -> writes spec.md. You edit it and set "Status: APPROVED".

/plan 12345
  -> writes plan.md. You edit it and set "Status: APPROVED".

/tasks 12345
  -> writes tasks.md with 6 tasks (2 in shared-repo, 4 in api-repo)

/new  then  /do-task 12345 1
/new  then  /do-task 12345 2
  ... through 6

/review 12345
  -> review.md: 1 spec gap, 2 nits. You fix the gap with one more /do-task.

/pr 12345
  -> pr.md with one section per repo. You push both branches and open the PRs in ADO.
```

---

## Tuning when the model struggles

| Symptom | Fix |
|---|---|
| Task fails or wanders | Split it. Tasks should touch fewer files. |
| Ignores conventions | Move the rule into the repo `AGENTS.md` or the command file. Rules in the conversation do not carry over. |
| Claims done without proof | The verify output must be in `progress.md`. Re-run `/do-task` and point at the missing evidence. |
| Asks too many questions | Answer them in `spec.md` directly, then re-run the next command. |
| Gets confused mid-task | Start a fresh session. State is on disk; nothing is lost. |
| Plans touch the wrong repo, or the wrong order | Fix the workspace `AGENTS.md` repo map. |

---

## Review tracker

[REVIEW.md](REVIEW.md) lists every file, its layer, what it does, and what you need to check. It is split into:

1. **Needs your input:** files with SAMPLE or `TODO(you)` content, and defaults you should consciously accept.
2. **Read once:** the generic agents, commands, and templates.
3. **Work PC setup:** the Layer 3 steps, which are never committed.

Check items off and commit `REVIEW.md` as you go.
