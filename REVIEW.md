# Maintainer review

For the owner and maintainers of eng-agents: what has been reviewed, what is left before rollout, and how to change Core safely. Forks should not edit this file. Engineers customizing their own setup want the [customization guide](docs/customization.md) instead.

## Status

| | |
|---|---|
| Core version | v1 (tag `core-v1`) |
| Dry run | Done on made-up repos. Two rounds of fixes applied. Practice files removed. |
| Real work | Not yet run at work |

## Part 1: Decisions made

- [x] **`core/opencode.json`**: tiered permissions. Read and inspect, build, test, and lint are allowed; anything that changes state asks; destructive commands are denied. *Reviewed 2026-10-05. Revisit after a week of real use.*
- [x] **`core/AGENTS.md`**: session rules, conventions (branch names, commit style, 3-file task cap), PowerShell and testing rules. *Reviewed 2026-10-05.*
- [x] **`core/agents/implementer.md`**: only agent that edits code. `npm install`, `dotnet format`, `git add` allowed; `git commit` asks. *Reviewed 2026-10-05.*
- [x] **Layer folders**: `personal/` and `company/` hold only a `TODO.md` pointer; `company/` is gitignored. *Decided 2026-10-06.*

## Part 2: Before rollout

- [ ] Read the setup docs as a new teammate would: [field guide](docs/field-guide.md), [personal onboarding](docs/onboarding-personal.md), [company onboarding](docs/onboarding-company.md), [customization guide](docs/customization.md)
- [ ] Set up your own work PC and confirm every item in [Assumptions to verify at work](docs/reference.md#assumptions-to-verify-at-work)
- [ ] Run real work items through every lane: feature, bug, spike, docs
- [ ] Fold generic fixes into Core and tag `core-v2`
- [ ] Decide where the base repo lives for the team (GitHub or a company ADO mirror)
- [ ] Update the status above

## Part 3: Read once

Each file was exercised in the dry run. Check it off once you have read it and agree with how it behaves.

**Agents**

- [ ] `core/agents/planner.md`: specs, plans, tasks. Writes only in `.work/`.
- [ ] `core/agents/reviewer.md`: two-pass review. Runs tests, cannot edit code.
- [ ] `core/agents/investigator.md`: bugs, spikes, onboarding. Cannot change code.
- [ ] `core/agents/writer.md`: docs and PR text. Markdown only.

**Commands**

- [ ] `core/commands/start.md`: work item, `.work` folder, branches. Asks before switching a repo that is on another item's branch.
- [ ] `core/commands/spec.md`: up to 6 questions, one at a time, then `spec.md` as DRAFT.
- [ ] `core/commands/plan.md`: requires approved spec; files per repo, pattern to follow, test plan.
- [ ] `core/commands/tasks.md`: requires approved plan; tasks of at most 3 files with verify commands.
- [ ] `core/commands/do-task.md`: one task, TDD for .NET, record output, commit.
- [ ] `core/commands/review.md`: spec pass, quality pass, accepted findings become tasks.
- [ ] `core/commands/pr.md`: short title and description per repo.
- [ ] `core/commands/bug.md`: root cause with confidence, up to 3 tasks, task 1 is a failing test.
- [ ] `core/commands/spike.md`: read-only investigation, options and a recommendation.
- [ ] `core/commands/docs.md` and `check-docs.md`: write docs, then fact-check every claim.
- [ ] `core/commands/onboard-repo.md`: draft a repo `AGENTS.md` and git-exclude it.
- [ ] `core/commands/status.md`: where an item is and the next command.
- [ ] `core/commands/pause.md` and `resume.md`: put an item on hold with a summary (optional WIP commit), then restore branches and pick it back up. *New, not yet tested.*

**Templates**

- [ ] `core/templates/` (12 files): `workitem`, `repos`, `spec`, `plan`, `tasks`, `progress`, `review`, `pr`, `bug`, `findings`, `repo-agents`, `paused`

**Scripts and docs**

- [ ] `install.ps1`: layers Core, Personal, Company. Tested with PowerShell 7 on Linux and Mac, not yet on Windows PowerShell 5.1.
- [ ] `core/scripts/ado/Get-WorkItem.ps1` and `config.example.json`: tested against a mock server, not a real ADO Server.
- [ ] `README.md`, `docs/reference.md`, `docs/pipeline.md`, `docs/setup-at-work.md`

## Changing Core

Before you merge a change to `core/`:

- [ ] It would help **anyone**. No company names, no personal preferences.
- [ ] Permission changes are made in `core/opencode.json` **and** every agent file that repeats the same tier lists.
- [ ] `Status: DRAFT` lines in the `spec`, `plan`, and `bug` templates and `## [ ] Task N:` headings in `tasks` are unchanged (commands depend on them).
- [ ] Docs that describe the behavior are updated (`docs/reference.md`, `docs/customization.md`, the guides).
- [ ] `pwsh ./install.ps1 -DryRun` runs cleanly.
- [ ] For a notable release, tag it (`core-v2`, ...) and tell teammates to run `git fetch upstream` and `git merge upstream/main` in their forks.

When reviewing a teammate's pull request, reject anything that includes a `personal/` folder or company content.
