# eng-agents

opencode agents (Tandem) that take a piece of work to a ready-to-open pull request in small steps you approve. The work can be an Azure DevOps work item or something you just describe (no tracker needed). Built for slower models that need explicit, step-by-step procedures.

## Daily use

Open opencode from your workspace root (for example `C:\src\work`). In Workshop, Builds' **flow cards** run the same steps from buttons: Handle a request, Build a feature, Fix a bug, Investigate, Plan an epic, Hand to a person, Write docs (see [Flow cards](docs/pipeline.md#flow-cards)).

| Work | Run |
|---|---|
| Feature | `/start <id>` (lane from the work item type; `--brief` adds a short context brief) → `/spec <id>` (drafts spec, plan and tasks) → `/approve <id>` → `/do-task <id> <n>` (repeat) → `/review <id>` → `/pr <id>` |
| Work with no tracker item | `/start new <feature or bug>`: describe it in chat. It gets a local id like `L3`; use that id in the commands above. |
| Small change (one repo, 1 to 3 tasks) | `/start <id> quick` → `/quick <id>` → `/approve <id>` → `/do-task` → `/review` → `/pr`. One combined spec and plan, one approval. It steps up to the feature lane by itself when the work turns out bigger. |
| Bug | `/start <id> bug` → `/bug <id>` → `/approve <id>` → `/do-task <id> <n>` (repeat) → `/review <id>` → `/pr <id>` |
| Define the work first | `/scope <idea>` → `/approve scope-<name>` → `/slice scope-<name>` → `/approve scope-<name> milestones` → `/backlog scope-<name> [csv\|ado\|local]` → `/start <story id> feature` |
| Question or a vague ask, no code changes (writes a shareable `brief.html`) | `/spike <id or topic> [--for business\|engineering\|leadership] [--timebox 1h\|2h\|4h\|1d]` |
| Docs | `/docs <target>` → read the draft → new session → `/check-docs <doc path>` → fix → `/publish docs-<name>` (approves it in place; you commit it) |
| Where was I? | `/dashboard [id]` (opens Builds in Workshop, at the item when you give an id) or `/status [id]` |
| Switch to something urgent | `/pause <id> [reason]`, later `/resume <id>` |
| End of day | `/shutdown`: writes `.work/runway.md` with where you left off, tomorrow's first step, and open loops. Next morning, `/status` shows it first. |
| Remember a rule | `/memory <rule>` (one repo) or `/memory -global <rule>` (every repo). `/memory -list` shows them. |
| Remember a product fact | `/product-notes add <product> <fact>` writes it to the product's note in Workshop's Notes app (`notes/products/<product>.md`), where you review it. Agents read the note when they work on that product and add facts they confirm. `/product-notes move` moves product facts out of repo guides; `/product-notes list` lists the notes. |
| Update eng-agents | `.\update.ps1` in your clone (see [Updating](docs/onboarding-company.md#updating)) |

Every other command (triage, shaping, PR reviews, handoffs, TSDs, retros, stats, onboarding, Cloudflare and more) is in [More commands](docs/pipeline.md#more-commands).

- **Approve** a spec, plan, or bug analysis with `/approve <id>` (it picks the current draft; add `spec`, `plan`, or `bug` to choose). Edit the file first if anything is wrong. Changing `Status: DRAFT` to `Status: APPROVED` by hand still works.
- **Publish** a finished document with `/publish <folder>`, for example `/publish tsd-orders` (approves it and moves it to the product docs folder) or `/publish docs-run-gateway` (approves a doc where it lives). You commit it.
- **New session** (`/new`) before every `/do-task`.
- **Review findings** you accept become new tasks. Run `/do-task` for each, then `/review` again.
- **You approve every push** and open the PR. No agent can merge or deploy. Outside changes (Cloudflare change sets, MCP tools that change something) are only ever asked for; you approve them in Workshop's Approvals, and Workshop's Activity lists every call.
- Every command ends with the next command to run. If lost, run `/dashboard` (Builds in Workshop) or `/status <id>`.

Something went wrong? See [Recovering from problems](docs/pipeline.md#recovering-from-problems).

## Setup

Running on a model you host (Ollama, LM Studio, llama.cpp, vLLM or your company's own server)? Read Workshop's [Local and self-hosted models](https://github.com/adavidson21/workshop/blob/main/docs/local-models.md) first. The model's context window must be at least 32K tokens, set on the server itself: each command loads about 3.5K to 7.5K tokens (`./evals/Get-PromptSize.ps1`) on top of opencode's own prompt and the repo map.


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
| [Pipeline](docs/pipeline.md) | Every other command, how each phase works, gates, lanes, work files, the dashboard, repo guides and memory, pausing, recovery, tuning |

## What Workshop relies on

Builds' Health > Tandem reads the same numbers as `/stats` with its own port of `Get-PipelineStats.ps1` and `Get-ReviewFindings.ps1`, checked against Workshop's `docs/examples/work/expected-health.json` by `core/scripts/stats/Test-HealthFormat.ps1` in CI.

Workshop's Builds reads `.work` with its own parser. The two repos meet only at the `.work` format, written down in Workshop's [docs/work-format.md](https://github.com/adavidson21/workshop/blob/main/docs/work-format.md), and at the command names Builds runs. Change the format, or the next-step rules in `core/commands/status.md`, in Workshop too.

## License

[PolyForm Shield 1.0.0](https://polyformproject.org/licenses/shield/1.0.0), see `LICENSE`. Free to use, change and share, including at work; not for building a product that competes with it. Versions up to November 5, 2026 were MIT and stay MIT.
