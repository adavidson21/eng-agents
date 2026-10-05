# Core review tracker

Every shared file in this base repo, what it does, and its review status. This tracks the **shared** files only. Your own setup progress lives in `personal/CHECKLIST.md` in your fork (copied from `personal-template/CHECKLIST.md`).

Maintainers: check a box when a file has been reviewed, and commit this file in the base repo. Forks should not edit it.

**Effort labels**

- **Fill in:** contains SAMPLE or `TODO(you)` content. You must edit it before it is useful.
- **Decide:** works as-is, but contains a default you should consciously accept or change.
- **Read:** generic prompt or template. Read it once to make sure it matches how you want the pipeline to behave.

**Layers:** Core = generic, team-shareable. Personal = each person's preferences (template here, real files in each fork). Company = work PC only (templates here, real files on the work PC).

All files below are **built**. Checked boxes are **reviewed**.

---

## Part 1: Needs your input (do these first)

- [ ] **`personal-template/AGENTS.md`** (Personal template, Decide)
  The starting point each person copies to `personal/` in their fork. Generic SAMPLE preferences and `TODO(you)` lines. No one's real preferences.
  Check: the SAMPLE lines are sensible defaults for anyone on the team.

- [ ] **`workspace-template/AGENTS.md`** (Company template, Fill in at work)
  The repo map. Copied to the workspace root at work. Tells the planner what each repo does, which are shared, how they reference each other by relative path, and which repos usually go together.
  Check: the sections are the ones you want. At work, replace every SAMPLE row with real repos. Do NOT put real content in this repo copy.

- [ ] **`workspace-template/company-overlay/AGENTS.md`** (Company template, Fill in at work)
  Company-wide rules that override Core and Personal. Copied to `%USERPROFILE%\.config\eng-agents\overlay\` at work.
  Check: the SAMPLE rules give the right idea. At work, replace them with real standards.

- [ ] **`core/scripts/ado/config.example.json`** (Core, Fill in at work)
  Placeholder ADO connection settings. At work you copy it to `%USERPROFILE%\.config\eng-agents\config.json` and fill in the real server, collection, and project.
  Check: nothing to change here. The real copy is a work-PC task (see `personal-template/CHECKLIST.md`).

- [x] **`core/opencode.json`** (Core, Decide) *Reviewed 2026-10-05: switched to tiered permissions.*
  Global permission baseline merged into your work `opencode.json`. Read and inspect commands and build/test/lint are allowed. Anything that changes state asks. Destructive commands (push, hard reset, clean, recursive delete, database updates) are denied. Edits are allowed except `.git` internals and `.env` files. See "Permission tiers" in the README.
  Check: nothing further. Revisit after a week of real use.

- [x] **`core/AGENTS.md`** (Core, Decide) *Reviewed 2026-10-05: approved as-is.*
  The rules every session follows: one step at a time, files are memory, ask when unsure, prove it, stay in scope, stop after 3 failures. Also conventions (branch names, commit style, 3-file task cap), PowerShell rules, and testing rules.
  Check: the Conventions table and Testing rules table match how your team works.

- [x] **`core/agents/implementer.md`** (Core, Decide) *Reviewed 2026-10-05: npm install allowed.*
  The only agent that edits code. Read, build, test, lint, `npm install`, `dotnet format`, and `git add` run without asking. `git commit` asks you each time. Cannot edit `.git` or `.env` files.
  Check: nothing further.

---

## Part 2: Read once (Core prompts and templates)

### Agents

- [ ] **`core/agents/planner.md`**: writes spec, plan, tasks. Reads code, writes only in `.work/`, can create branches and run the ADO script.
- [ ] **`core/agents/reviewer.md`**: two-pass review (spec, then quality). Runs tests and lint, cannot edit code or commit.
- [ ] **`core/agents/investigator.md`**: bugs, spikes, repo onboarding. Reads and runs code, cannot change it. Can write a repo `AGENTS.md` with your approval.
- [ ] **`core/agents/writer.md`**: docs and PR text. Edits markdown and `docs/` only.

### Commands

- [ ] **`core/commands/start.md`**: `/start <id> <feature|bug>`. Fetches the work item (or offline mode), creates the `.work` folder, confirms repos with you, creates branches from `origin/main`.
- [ ] **`core/commands/spec.md`**: `/spec <id>`. Up to 6 clarifying questions, one at a time, then `spec.md` as DRAFT.
- [ ] **`core/commands/plan.md`**: `/plan <id>`. Requires approved spec. Writes `plan.md` with files per repo, a pattern-to-follow file, and a test plan.
- [ ] **`core/commands/tasks.md`**: `/tasks <id>`. Requires approved plan. Tasks of at most 3 files with exact verify commands and a coverage table.
- [ ] **`core/commands/do-task.md`**: `/do-task <id> <n>`. One task, fresh session, strict TDD for .NET, lint, record output, commit.
- [ ] **`core/commands/review.md`**: `/review <id>`. Runs tests, reads the diff, pass 1 spec and pass 2 quality checklist, turns accepted findings into tasks.
- [ ] **`core/commands/pr.md`**: `/pr <id>`. Short title and description per repo. You push.
- [ ] **`core/commands/bug.md`**: `/bug <id>`. Traces the code path, root cause with confidence, `bug.md` plus up to 3 tasks (task 1 is a failing test).
- [ ] **`core/commands/spike.md`**: `/spike <id or topic>`. Read-only investigation, `findings.md` with options and a recommendation.
- [ ] **`core/commands/docs.md`**: `/docs <what>`. Clarifies audience, outlines, writes, saves a sources list.
- [ ] **`core/commands/check-docs.md`**: `/check-docs <path>`. Reviewer fact-checks every claim in a doc against the code.
- [ ] **`core/commands/onboard-repo.md`**: `/onboard-repo <folder>`. Drafts a repo `AGENTS.md` from the code and git-excludes it.
- [ ] **`core/commands/status.md`**: `/status [id]`. Where an item is and the exact next command.

### Templates

- [ ] **`core/templates/workitem.md`**: work item text (fetched or pasted).
- [ ] **`core/templates/repos.md`**: lane, repos in order, branches.
- [ ] **`core/templates/spec.md`**: goal, current behavior, Given/When/Then criteria, non-goals, decisions, open questions. Has the Status gate.
- [ ] **`core/templates/plan.md`**: approach, changes per repo with pattern-to-follow, test plan, risks. Has the Status gate.
- [ ] **`core/templates/tasks.md`**: task format and coverage table.
- [ ] **`core/templates/progress.md`**: log entry format.
- [ ] **`core/templates/review.md`**: test results, pass 1 and 2 tables, proposed fix tasks.
- [ ] **`core/templates/pr.md`**: per-repo title and short description.
- [ ] **`core/templates/bug.md`**: symptom, code path, root cause and confidence, fix approach. Has the Status gate.
- [ ] **`core/templates/findings.md`**: spike answer, evidence, options, recommendation.
- [ ] **`core/templates/repo-agents.md`**: the shape of every repo `AGENTS.md`: commands, Clean Architecture reference rules, patterns to follow, testing, EF Core, cross-repo references.

### Personal template extras

- [ ] **`personal-template/commands/standup.md`**: `/standup [days]`. Drafts Yesterday / Today / Blockers from all `.work` progress logs. An optional example command; each person keeps or deletes it in their fork.
- [ ] **`personal-template/README.md`** and **`personal-template/CHECKLIST.md`**: how to set up a personal layer, and a per-person setup checklist.

### Scripts and docs

- [ ] **`install.ps1`**: layers Core, Personal, Company into your opencode config. Keeps your provider and model settings, backs up anything it changes, cleans up files it previously installed. Tested with PowerShell 7 on Linux; written to also run on Windows PowerShell 5.1.
- [ ] **`core/scripts/ado/Get-WorkItem.ps1`**: fetches a work item over REST (PAT or Windows auth) and creates the `.work` folder, or creates it offline from a title. Tested against a mock server, not a real ADO Server.
- [ ] **`docs/setup-at-work.md`**: first-day steps and the verification checklist.
- [ ] **`docs/pipeline.md`**: design rationale, gates, lanes, and recovery steps.
- [ ] **`README.md`**: overview.
