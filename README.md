# eng-agents

opencode agents that take an Azure DevOps work item to a ready-to-open pull request in small steps you approve. Built for slower models that need explicit, step-by-step procedures.

## Daily use

Open opencode from your workspace root (for example `C:\src\work`).

| Work | Run |
|---|---|
| Feature | `/start <id> feature` → `/spec <id>` → `/approve <id>` → `/plan <id>` → `/approve <id>` → `/tasks <id>` → `/do-task <id> <n>` (repeat) → `/review <id>` → `/pr <id>` |
| Bug | `/start <id> bug` → `/bug <id>` → `/approve <id>` → `/do-task <id> <n>` (repeat) → `/review <id>` → `/pr <id>` |
| Question, no code changes | `/spike <id or topic>` |
| Docs | `/docs <target>`, new session, `/check-docs <doc path>` |
| Technical spec with diagrams | `/tsd <product or repo> [repo ...]` → new session → `/check-docs .work/tsd-<name>/tsd.md` → revise → `/publish tsd-<name>` |
| Where was I? | `/dashboard` (every item and repo, in your browser) or `/status [id]` |
| Switch to something urgent | `/pause <id> [reason]`, later `/resume <id>` |
| New repo in the workspace | `/onboard-repo <folder>` |
| Remember a rule | `/memory <rule>` (one repo) or `/memory -global <rule>` (every repo). `/memory -list` shows them. |
| Work item in another ADO collection | `/start <id> <lane> <repo folder or connection>` |

- **Approve** a spec, plan, or bug analysis with `/approve <id>` (it picks the current draft; add `spec`, `plan`, or `bug` to choose). Edit the file first if anything is wrong. Changing `Status: DRAFT` to `Status: APPROVED` by hand still works.
- **Publish** a finished document with `/publish <folder>`, for example `/publish tsd-orders`. It approves it, moves it to the product docs folder, and you commit it.
- **New session** (`/new`) before every `/do-task`.
- **Review findings** you accept become new tasks. Run `/do-task` for each, then `/review` again.
- **You push** and open the PR. No agent can push, merge, or deploy.
- Every command ends with the next command to run. If lost, run `/dashboard` or `/status <id>`.
- **After a restart**, you don't need opencode to see where you were. Open `.work\dashboard.html`, or rebuild it from any terminal (see [Dashboard](docs/pipeline.md#dashboard)).

Something went wrong? See [Recovering from problems](docs/pipeline.md#recovering-from-problems).

## Setup

1. [Personal onboarding](docs/onboarding-personal.md): create your fork and fill in `personal/`.
2. [Company onboarding](docs/onboarding-company.md): set up the work PC, install, and smoke test.

## Docs

| Doc | Read it for |
|---|---|
| [Personal onboarding](docs/onboarding-personal.md) | Your fork and your `personal/` rules |
| [Company onboarding](docs/onboarding-company.md) | Work PC setup, day-one checks, updating |
| [Customization](docs/customization.md) | Files to review, how layers combine, agents, permission tiers, templates, changing Core |
| [Pipeline](docs/pipeline.md) | How each phase works, gates, lanes, work files, the dashboard, repo guides and memory, pausing, recovery, tuning |
