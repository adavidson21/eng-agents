# eng-agents

opencode agents that take an Azure DevOps work item to a ready-to-open pull request in small steps you approve. Built for slower models that need explicit, step-by-step procedures.

## Daily use

Open opencode from your workspace root (for example `C:\src\work`).

| Work | Run |
|---|---|
| Feature | `/start <id> feature` → `/spec <id>` → approve → `/plan <id>` → approve → `/tasks <id>` → `/do-task <id> <n>` (repeat) → `/review <id>` → `/pr <id>` |
| Bug | `/start <id> bug` → `/bug <id>` → approve → `/do-task <id> <n>` (repeat) → `/review <id>` → `/pr <id>` |
| Question, no code changes | `/spike <id or topic>` |
| Docs | `/docs <target>`, new session, `/check-docs <doc path>` |
| Where was I? | `/status [id]` |
| Switch to something urgent | `/pause <id> [reason]`, later `/resume <id>` |
| New repo in the workspace | `/onboard-repo <folder>` |

- **Approve** `spec.md`, `plan.md`, or `bug.md` by changing `Status: DRAFT` to `Status: APPROVED`. Edit the file first if anything is wrong.
- **New session** (`/new`) before every `/do-task`.
- **Review findings** you accept become new tasks. Run `/do-task` for each, then `/review` again.
- **You push** and open the PR. No agent can push, merge, or deploy.
- Every command ends with the next command to run. If lost, run `/status <id>`.

Something went wrong? See [Recovering from problems](docs/pipeline.md#recovering-from-problems).

## Setup

1. [Personal onboarding](docs/onboarding-personal.md): create your fork and fill in `personal/`.
2. [Company onboarding](docs/onboarding-company.md): set up the work PC, install, and smoke test.

## Docs

| Doc | Read it for |
|---|---|
| [Personal onboarding](docs/onboarding-personal.md) | Your fork and your `personal/` rules |
| [Company onboarding](docs/onboarding-company.md) | Work PC setup, day-one checks, updating |
| [Customization](docs/customization.md) | Files to review, how layers combine, agents and permissions, templates, changing Core |
| [Pipeline](docs/pipeline.md) | How each phase works, gates, lanes, work files, pausing, recovery, tuning |
