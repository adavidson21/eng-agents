# eng-agents

opencode agents (Tandem) that take a piece of work to a ready-to-open pull request in small steps you approve. The work can be an Azure DevOps work item or something you just describe (no tracker needed). Built for slower models that need explicit, step-by-step procedures.

## Daily use

Open opencode from your workspace root (for example `C:\src\work`).

| Work | Run |
|---|---|
| Feature | `/start <id> feature` (ends with `brief.md`, a short context brief; `--cold` skips it) → `/spec <id>` → `/approve <id>` → `/plan <id>` → `/approve <id>` → `/tasks <id>` → `/do-task <id> <n>` (repeat) → `/review <id>` → `/pr <id>` |
| Work with no tracker item | `/start new <feature or bug>`: describe it in chat. It gets a local id like `L3`; use that id in the commands above. |
| Define the work first | `/scope <idea>` → `/approve scope-<name>` → `/slice scope-<name>` → `/approve scope-<name> milestones` → `/backlog scope-<name> [csv\|ado\|local]` → `/start <story id> feature` |
| Bug | `/start <id> bug` → `/bug <id>` → `/approve <id>` → `/do-task <id> <n>` (repeat) → `/review <id>` → `/pr <id>` |
| Shape an idea with you first | `/shape <idea>` (or `/shape triage-<name>` after a triage): rounds of up to 5 questions in `.work/shape-<name>/questions.md`, a running `understanding.md`, then `brief.md`. Answer in Slate (or `answers.md`) and run `/shape shape-<name>` again; `/shape shape-<name> brief` writes the brief now. Then `/scope shape-<name>` or `/refine shape-<name>`. |
| Triage a request before work starts | `/triage <ADO id or the request in words>`: writes `.work/triage-<id>/triage.md` with a summary, what it touches, questions for the requester, a size and a suggested route (delegate or do it yourself). Never posts. Slate in Workshop runs it from a button. |
| Define one story or bug | `/refine <title>` → `/approve refine-<name>`. Writes `refine.md` with a description and Gherkin acceptance criteria, ready to publish (Slate publishes it to ADO). For anything epic-sized, use `/scope`. |
| Hand work to a teammate | `/handoff <ADO id> <name>`: a brief with context, acceptance criteria, where to start and what to watch. Posts nothing. |
| Question, no code changes | `/spike <id or topic>` |
| First pass on a teammate's PR | `/pr-review <PR link>` (or **PR reviews** in Dispatch). Drafts comments in `.work/pr-<id>/review.md`; you post the ones you agree with. Never checks out the PR or posts anything. |
| Ask or capture from Workshop | Type in the hub on Workshop's Dispatch page. It runs `/hub <request>`: captures become proposals you accept, questions are answered from your repo map, repo guides and code, with sources. It writes nothing but its own two files and never changes ADO or git. |
| Prep a 1:1 | **Draft talking points** in Workshop's 1:1s app runs `/one-on-one <packet>`. It drafts wins, follow-ups, blockers, growth topics and 3 questions from the app's packet; it never rates or judges anyone. |
| Docs | `/docs <target>`, new session, `/check-docs <doc path>` |
| Technical spec with diagrams | `/tsd <product or repo> [repo ...]` → new session → `/check-docs .work/tsd-<name>/tsd.md` → revise → `/publish tsd-<name>` |
| Where was I? | `/dashboard [id]` (opens Dispatch in Workshop, at the item when you give an id) or `/status [id]` |
| Drive it from the browser | Dispatch in [Workshop](https://github.com/adavidson21/workshop): it runs each step in opencode (see [Dashboard](docs/pipeline.md#dashboard)) |
| Hands-off build after the plan | Dispatch: **Approve and build**. It runs tasks, review, and PR text, each step in a new session, and stops only when it needs you (see [Autopilot](docs/pipeline.md#autopilot)) |
| End of day | `/shutdown`: writes `.work/runway.md` with where you left off, tomorrow's first step, and open loops. Next morning, `/status` shows it first. |
| Standup update | `/standup [days back]` (default 1, or 3 on a Monday) |
| Switch to something urgent | `/pause <id> [reason]`, later `/resume <id>` |
| New repo in the workspace | `/onboard-repo <folder>` |
| Remember a rule | `/memory <rule>` (one repo) or `/memory -global <rule>` (every repo). `/memory -list` shows them. |
| Remember a product fact | `/memory -product <product> <fact>` writes it to the product's note in Workshop's Notes app (`notes/products/<product>.md`), where you review it. Agents read the note when they work on that product and add facts they confirm. `/product-notes move` moves product facts out of repo guides; `/product-notes list` lists the notes. |
| Work item in another ADO collection | `/start <id> <lane> <repo folder or connection>` |
| Update eng-agents | `.\update.ps1` in your clone (see [Updating](docs/onboarding-company.md#updating)) |

- **Approve** a spec, plan, or bug analysis with `/approve <id>` (it picks the current draft; add `spec`, `plan`, or `bug` to choose). Edit the file first if anything is wrong. Changing `Status: DRAFT` to `Status: APPROVED` by hand still works.
- **Publish** a finished document with `/publish <folder>`, for example `/publish tsd-orders`. It approves it, moves it to the product docs folder, and you commit it.
- **New session** (`/new`) before every `/do-task`.
- **Review findings** you accept become new tasks. Run `/do-task` for each, then `/review` again.
- **You approve every push** and open the PR. No agent can merge or deploy.
- Every command ends with the next command to run. If lost, run `/dashboard` or `/status <id>`.
- Dispatch in Workshop is the live UI; `/dashboard` opens it and says to start Workshop if it is not running. The static dashboard (`.work\dashboard.html`, `/dashboard static`) remains for terminal-only use.
- **After a restart**, open `.work\dashboard.html` (bookmark it) to see where you were, or start Workshop and run `/dashboard` (see [Dashboard](docs/pipeline.md#dashboard)).

Something went wrong? See [Recovering from problems](docs/pipeline.md#recovering-from-problems).

## Setup

1. [Personal onboarding](docs/onboarding-personal.md): create your fork and fill in `personal/`.
2. [Company onboarding](docs/onboarding-company.md): set up the work PC, install, and smoke test.
3. Later: `.\update.ps1` pulls and reinstalls. You install once; updates never need a fresh setup. What changed is in [CHANGELOG.md](CHANGELOG.md).

## Docs

| Doc | Read it for |
|---|---|
| [Personal onboarding](docs/onboarding-personal.md) | Your fork and your `personal/` rules |
| [Company onboarding](docs/onboarding-company.md) | Work PC setup, day-one checks, [updating](docs/onboarding-company.md#updating) |
| [Changelog](CHANGELOG.md) | What is new in each Core version |
| [Customization](docs/customization.md) | Files to review, how layers combine, agents, permissions, templates, changing Core |
| [Pipeline](docs/pipeline.md) | How each phase works, gates, lanes, work files, the dashboard, repo guides and memory, pausing, recovery, tuning |

## License

[PolyForm Shield 1.0.0](https://polyformproject.org/licenses/shield/1.0.0), see `LICENSE`. Free to use, change and share, including at work; not for building a product that competes with it. Versions up to November 5, 2026 were MIT and stay MIT.
