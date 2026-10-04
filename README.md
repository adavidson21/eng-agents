# eng-agents

A personal opencode workspace that takes work from an Azure DevOps work item to a ready-to-open pull request, using a set of narrowly scoped agents and slash commands.

It is designed for a capable but slower, less forgiving model (a Qwen-class model). Everything here leans on four ideas:

1. **Small steps.** Every task touches 1 to 3 files and has one exact command that proves it is done.
2. **Files are the memory.** Specs, plans, tasks and progress live on disk, so any fresh session can pick up exactly where the last one stopped.
3. **You trigger each phase.** Slash commands are explicit. Nothing depends on the model deciding on its own to load a skill.
4. **Humans gate the expensive decisions.** You approve the spec and the plan before any code is written.

> **Status:** planning. This README is the source of truth for v1. Folders listed below marked *(planned)* do not exist yet.

---

## Table of contents

- [Ground rules for this repo](#ground-rules-for-this-repo)
- [The pipeline](#the-pipeline)
- [Lanes](#lanes)
- [Agents](#agents)
- [Commands](#commands)
- [Work artifacts](#work-artifacts)
- [Conventions baked in](#conventions-baked-in)
- [Testing rules](#testing-rules)
- [Workspace layout at work](#workspace-layout-at-work)
- [Repo layout](#repo-layout)
- [Setup](#setup)
- [What you are responsible for](#what-you-are-responsible-for)
- [Assumptions to verify at work](#assumptions-to-verify-at-work)
- [Example: one feature, start to finish](#example-one-feature-start-to-finish)
- [Tuning when the model struggles](#tuning-when-the-model-struggles)
- [v1 build checklist](#v1-build-checklist)

---

## Ground rules for this repo

This repo is private and **must contain zero company-specific content**. That means no:

- company, product, team, or repo names
- server URLs, collection or project names
- code, schemas, or snippets from work repos
- work item titles, descriptions, or IDs
- PATs, tokens, or credentials of any kind

Everything company-specific is created **at work, on the work machine**, and stays outside this repo (see [What you are responsible for](#what-you-are-responsible-for)).

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
   |                   >>> GATE: you approve acceptance criteria
   v
/plan 12345            planner writes plan.md: approach, files per repo, risks
   |                   >>> GATE: you approve the approach
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

---

## Lanes

| Lane | When to use | Flow |
|---|---|---|
| **Feature** | New behavior with acceptance criteria | `/start` → `/spec` → `/plan` → `/tasks` → `/do-task` (repeat) → `/review` → `/pr` |
| **Bug (fast lane)** | A defect with a reproducible symptom | `/start` → `/bug` → `/do-task` (repeat) → `/review` → `/pr` |
| **Spike** | A question you need answered before committing to an approach | `/spike` → `findings.md` (read only, no code changes). Can feed into `/spec`. |
| **Docs** | Writing or updating documentation | `/docs` → writer drafts → reviewer checks every claim against the code |

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
| `writer` | Documentation | Yes | Docs files only | Yes | No |

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
| `/pr <id>` | writer | Writes `pr.md`: a short title and a short description with test evidence. |
| `/bug <id>` | investigator | Reproduces, root-causes, writes `bug.md` with up to 3 tasks. |
| `/spike <id-or-topic>` | investigator | Timeboxed investigation, writes `findings.md`. No code changes. |
| `/docs <target>` | writer | Drafts or updates docs, then hands to the reviewer for a fact check. |
| `/onboard-repo <folder>` | investigator | Scans a repo and drafts its local `AGENTS.md`. **You must review it.** |
| `/status [id]` | planner | Reads `.work\` and tells you where you left off and what to run next. |

**Golden rule:** start a fresh opencode session for every `/do-task`. Long sessions are where slower models drift.

---

## Work artifacts

All pipeline state lives in the workspace, outside every git repo:

```
.work\12345-short-name\
  workitem.md     raw work item text (fetched or pasted)
  spec.md         goal, acceptance criteria, non-goals, open questions
  plan.md         approach, files per repo, risks
  tasks.md        numbered checkbox tasks with verify commands
  progress.md     append-only log: what each session did and the verify output
  review.md       reviewer findings
  pr.md           PR title and description
  bug.md          bug lane only
  findings.md     spike lane only
```

Because `.work\` is outside every repo, none of this can be committed by accident.

---

## Conventions baked in

| Item | Convention |
|---|---|
| Base branch | `main` (all repos) |
| PR target | `main` |
| Feature branch | `dev/feature/12345-short-name` |
| Bug branch | `dev/bug/12345-short-name` |
| Commit message | Short summary only (for example: `Add retry to export job`) |
| PR output | Draft title and short description only. Not verbose. You open the PR yourself. |
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
  AGENTS.md                        repo map (you write this from the template)
  .work\                           pipeline state (see above)
  <api-repo>\                      each repo has a local AGENTS.md
  <ui-repo>\
  <shared-repo>\
```

- Cloning all related repos under one parent lets a single feature span API, UI and shared code.
- opencode finds `AGENTS.md` by walking **up** from the folder you launch in. Launching from `C:\src\work\` loads the workspace `AGENTS.md`, but **not** the per-repo ones. Every command therefore tells the agent to read `<repo>\AGENTS.md` before touching that repo.
- Each repo's `AGENTS.md` is hidden from git via `.git\info\exclude`, a local-only ignore file. The company's `.gitignore` is never modified.

---

## Repo layout

```
eng-agents/
  README.md                         this file
  install.ps1                       (planned) copies global\ into your opencode config folder
  global/                           (planned) everything that installs globally
    AGENTS.md                       universal rules for every session
    opencode.json                   permissions only. No provider, no model.
    agents/
      planner.md
      implementer.md
      reviewer.md
      investigator.md
      writer.md
    commands/
      start.md  spec.md  plan.md  tasks.md  do-task.md  review.md  pr.md
      bug.md  spike.md  docs.md  onboard-repo.md  status.md
    templates/
      spec.md  plan.md  tasks.md  progress.md  review.md  pr.md
      bug.md  findings.md  repo-agents.md  workitem.md
    scripts/
      ado/
        Get-WorkItem.ps1            reads a work item via REST
        config.example.json         placeholder connection settings
  workspace-template/               (planned)
    AGENTS.md                       fill-in-the-blanks repo map
  docs/                             (planned)
    pipeline.md                     deeper notes on each phase
    setup-at-work.md                step-by-step first-day setup
```

---

## Setup

### At home (building and changing the scaffolding)

1. Clone this repo and edit files under `global\` and `workspace-template\`.
2. Optional: test changes against a personal project with a similar open model before taking them to work.
3. Commit and push. Never add company content (see [Ground rules](#ground-rules-for-this-repo)).

### At work (first time)

1. **Clone** this repo somewhere outside the workspace, for example `C:\tools\eng-agents`.
2. **Install:** run `.\install.ps1` in PowerShell. It copies `global\*` into your opencode global config folder. Use `-Target <path>` if your config folder is not the default (see [Assumptions to verify](#assumptions-to-verify-at-work)).
3. **Workspace:** create `C:\src\work\`, clone the related repos into it, copy `workspace-template\AGENTS.md` to `C:\src\work\AGENTS.md`, and fill it in.
4. **ADO:** create a PAT, set it as an environment variable, and create `config.json` from the example (details below).
5. **Hide local files:** add `AGENTS.md` to `.git\info\exclude` in each repo.
6. **Onboard repos:** from `C:\src\work\`, run `/onboard-repo <repo-folder>` for each repo, then review and correct each generated `AGENTS.md`.
7. **Smoke test:** run `/start` on a small, low-risk bug and walk the bug lane end to end.

### At work (updating)

`git pull` in your clone, then re-run `.\install.ps1`. Your workspace files, `config.json`, and repo `AGENTS.md` files are untouched because they live outside this repo.

---

## What you are responsible for

The scaffolding is generic. These pieces are **yours** because they are company-specific, security-sensitive, or require judgment the model cannot be trusted with.

### Must do before first use

| # | What | Where it lives | Why it is yours |
|---|---|---|---|
| 1 | **Confirm the opencode global config folder** on Windows and pass it to `install.ps1 -Target` if needed | Your machine | The opencode docs do not state the Windows path. Installing to the wrong folder means none of the agents or commands load. |
| 2 | **Create an ADO PAT** with scopes **Work Items (Read)** and **Code (Read)** | ADO Server, your profile | Credentials never go in this repo. These two scopes are enough to read work items and repos. Only add Code (Read & Write) if you later want PRs created automatically. |
| 3 | **Store the PAT as an environment variable** `ADO_PAT` (user-level) | Your machine | Keeps the token out of every file, including `config.json`. The scripts read it from the environment. |
| 4 | **Fill in `config.json`** (copy of `config.example.json`): server URL, collection, project, api-version | `%USERPROFILE%\.config\eng-agents\config.json` (outside this repo) | Company URLs and names must never be committed here. api-version is a setting because your exact ADO Server version is not confirmed. |
| 5 | **Write the workspace `AGENTS.md`** from the template: each repo's folder name, purpose, how repos depend on each other, what lives in the shared repo, and how to run each one locally | `C:\src\work\AGENTS.md` | Only you know how the repos relate. The planner uses this map to decide which repos a feature touches. A wrong map produces wrong plans. |
| 6 | **Review every `/onboard-repo` output** before using that repo in the pipeline | `C:\src\work\<repo>\AGENTS.md` | The model drafts it, but every future session trusts it blindly. One wrong build command or misread architecture layer gets repeated in every task. Fix it once here. |
| 7 | **Add `AGENTS.md` to `.git\info\exclude`** in each repo | Each repo's `.git\info\exclude` | Keeps your local agent files out of company commits without touching the shared `.gitignore`. |

### Should decide early

| # | Decision | Where | Why it is yours |
|---|---|---|---|
| 8 | **Shell command allowlist.** v1 allows `dotnet`, `npm`, `npx`, `ng`, read-only `git`, `git checkout -b`, `git add`, `git commit`. `git push` is denied. Anything else asks. | `global\opencode.json` | This is your risk tolerance. Loosen it as you build trust, tighten it if the model surprises you. |
| 9 | **Whether the implementer commits automatically** after each passing task (v1 default: yes, with an approval prompt) | `global\agents\implementer.md` | One commit per task makes rollback easy, but some people prefer to commit by hand. |
| 10 | **Point the UI repo `AGENTS.md` at your existing Playwright mock helpers** (fixtures, mock data folders, `page.route` utilities) | `C:\src\work\<ui-repo>\AGENTS.md` | Without this, the model invents a new mocking style per test. Consistency with existing tests matters more than any one test. |
| 11 | **Point each repo `AGENTS.md` at the architecture doc**, if one exists, and list Clean Architecture layer rules (what can reference what) | Each repo `AGENTS.md` | Layer violations are the most likely mistake in a Clean Architecture codebase, and the reviewer can only catch what is written down. |
| 12 | **Adjust the PR template** if your team expects specific sections | `global\templates\pr.md` | Default is deliberately short: title, what changed, how it was tested, work item link. Keep it short. |

### Optional, anytime

| # | What | Where | Why |
|---|---|---|---|
| 13 | Personal coding preferences (naming, patterns you like or hate) | `global\AGENTS.md`, "House rules" section | Applies to every session. Keep it generic, since it is committed here. |
| 14 | Per-agent model override (for example, a faster model for `planner`) | Agent frontmatter `model:` field, or your work opencode config | Only if your work setup offers more than one model. Leave unset to inherit the default. |
| 15 | Task size limits | `global\templates\tasks.md` | v1 caps tasks at 3 files. Lower it if tasks fail often, raise it if the model handles more. |

### Never do

- Put company names, URLs, code, or work item content in this repo.
- Put the PAT in any file.
- Let an agent push, merge, or deploy.
- Skip reviewing `spec.md`, `plan.md`, or a generated repo `AGENTS.md`. Those three files drive everything downstream.

---

## Assumptions to verify at work

These are educated guesses. Check each one on day one and update this README if any are wrong.

| Assumption | How to check | If wrong |
|---|---|---|
| opencode's global config folder on Windows is `%USERPROFILE%\.config\opencode` | Look for an existing `opencode.json` there or in `%APPDATA%\opencode` | Re-run `install.ps1 -Target <correct path>` |
| opencode runs shell commands in PowerShell on your machine | Ask opencode to run `$PSVersionTable.PSVersion` | Adjust script calls in commands to match the shell it uses |
| Per-repo `AGENTS.md` is not auto-loaded when launching from the workspace root | Launch from `C:\src\work\` and ask "what is in api-repo's AGENTS.md?" without telling it to read the file | If it already knows, the explicit read step is harmless; leave it |
| ADO Server supports REST api-version `6.0` | Run `Get-WorkItem.ps1` against a known work item | Lower `apiVersion` in `config.json` (for example `5.1`) |
| Angular unit tests run with a single headless command | Check `angular.json` and `package.json` test scripts | Record the right command in the UI repo `AGENTS.md` |
| The model reliably follows commands without subagents | Run the bug lane on a small bug | No change needed. v1 does not depend on subagents. |

---

## Example: one feature, start to finish

```
cd C:\src\work
opencode

/start 12345 feature
  -> pulls #12345, creates .work\12345-export-retry\
  -> asks: which repos? you answer: api-repo
  -> creates dev/feature/12345-export-retry in api-repo

/spec 12345
  -> asks 3 to 6 questions, one at a time
  -> writes spec.md. You edit or approve.

/plan 12345
  -> writes plan.md. You approve.

/tasks 12345
  -> writes tasks.md with 5 tasks

(new session) /do-task 12345 1
(new session) /do-task 12345 2
  ... through 5

/review 12345
  -> review.md: 1 spec gap, 2 nits. You fix the gap with one more /do-task.

/pr 12345
  -> pr.md. You push the branch and open the PR in ADO.
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
| Plans touch the wrong repo | Fix the workspace `AGENTS.md` repo map. |

---

## v1 build checklist

- [ ] `global\AGENTS.md`
- [ ] `global\opencode.json` (permissions)
- [ ] 5 agents
- [ ] 12 commands
- [ ] 10 templates
- [ ] `scripts\ado\Get-WorkItem.ps1` and `config.example.json`
- [ ] `install.ps1`
- [ ] `workspace-template\AGENTS.md`
- [ ] `docs\pipeline.md` and `docs\setup-at-work.md`
- [ ] Day-one verification at work (see [Assumptions](#assumptions-to-verify-at-work))
