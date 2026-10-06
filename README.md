# eng-agents

opencode agents that take an Azure DevOps work item to a ready-to-open pull request, in small steps you approve along the way. Built for slower, less forgiving models.

## How it works

```
/start → /spec → /plan → /tasks → /do-task (repeat) → /review → /pr
```

- **Five narrow agents** (planner, implementer, reviewer, investigator, writer), each with only the permissions it needs.
- **You approve** the spec and the plan by changing one line to `Status: APPROVED`.
- **Tiny tasks**, each with a command that proves it is done. Strict TDD for .NET.
- **Files are the memory.** Everything is saved in `.work/`, so any new session picks up where the last one stopped.
- **You push.** No agent can push, merge, or deploy.

## Install

| Step | Guide |
|---|---|
| 1. Fork this repo and add your preferences | [Personal onboarding](docs/onboarding-personal.md) |
| 2. Set up your work PC: ADO, company rules, repo map | [Company onboarding](docs/onboarding-company.md) |
| 3. Install | `.\install.ps1 -DryRun`, then `.\install.ps1` |
| 4. Smoke test one small bug | [Company onboarding, step 6](docs/onboarding-company.md#6-verify-and-smoke-test) |

## Use

Open opencode in your workspace folder and run:

| Work | Commands |
|---|---|
| Feature | `/start <id> feature` → `/spec` → `/plan` → `/tasks` → `/do-task <id> <n>` → `/review` → `/pr` |
| Bug | `/start <id> bug` → `/bug` → `/do-task` → `/review` → `/pr` |
| Question | `/spike <id or topic>` (no code changes) |
| Docs | `/docs <target>`, then `/check-docs <path>` |
| Where was I? | `/status [id]` |

Start a new session (`/new`) before every `/do-task`.

## Docs

| Doc | For |
|---|---|
| [Field guide](docs/field-guide.md) | A short overview: layers, a day of use, getting set up |
| [Personal onboarding](docs/onboarding-personal.md) | Creating your fork and filling in `personal/` |
| [Company onboarding](docs/onboarding-company.md) | Setting up the work PC |
| [Setup at work](docs/setup-at-work.md) | Exact first-day commands and verification checks |
| [Reference](docs/reference.md) | Everything else: agents, permissions, layers, file layout, what `install.ps1` does |
| [Pipeline](docs/pipeline.md) | Design rationale, gates, and recovering from problems |
| [Review tracker](REVIEW.md) | Review status of the shared files (maintainers) |
