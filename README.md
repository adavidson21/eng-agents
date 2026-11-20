# eng-agents

opencode agents (Tandem) that take a piece of work to a ready-to-open pull request in small steps you approve. The work can be an Azure DevOps work item or something you just describe (no tracker needed). Built for slower models that need explicit, step-by-step procedures.

## Daily use

Open opencode from your workspace root (for example `C:\src\work`). In Workshop, Loom's **flow cards** run the same steps from buttons: Handle a request, Build a feature, Fix a bug, Investigate, Plan an epic, Hand to a person, Write docs (see [Flow cards](docs/pipeline.md#flow-cards)).

| Work | Run |
|---|---|
| Feature | `/start <id>` (lane from the work item type; `--brief` adds a short context brief) → `/spec <id>` (drafts spec, plan and tasks) → `/approve <id>` → `/do-task <id> <n>` (repeat) → `/review <id>` → `/pr <id>` |
| Work with no tracker item | `/start new <feature or bug>`: describe it in chat. It gets a local id like `L3`; use that id in the commands above. |
| Define the work first | `/scope <idea>` → `/approve scope-<name>` → `/slice scope-<name>` → `/approve scope-<name> milestones` → `/backlog scope-<name> [csv\|ado\|local]` → `/start <story id> feature` |
| Bug | `/start <id> bug` → `/bug <id>` → `/approve <id>` → `/do-task <id> <n>` (repeat) → `/review <id>` → `/pr <id>` |
| Shape an idea with you first | `/shape <idea>` (or `/shape triage-<name>` after a triage): rounds of up to 5 questions in `.work/shape-<name>/questions.md`, a running `understanding.md`, then `brief.md`. Answer in Slate (or `answers.md`) and run `/shape shape-<name>` again; `/shape shape-<name> brief` writes the brief now. Then `/scope shape-<name>` or `/refine shape-<name>`. |
| Triage a request before work starts | `/triage <ADO id> [note]` or `/triage <the request in words>`: writes `.work/triage-<id>/triage.md` with a summary, what it touches, questions for the requester, a size, a suggested route (delegate or do it yourself) and a suggested path (interview, brief or decline). Never posts. Then `/shape triage-<name>` (interview) or `/shape triage-<name> brief` (skip to the brief). Loom in Workshop runs it from a button. |
| Define one story or bug | `/refine <title>` → `/approve refine-<name>`. Writes `refine.md` with a description and Gherkin acceptance criteria, ready to publish (Slate publishes it to ADO). For anything epic-sized, use `/scope`. |
| Hand work to a teammate | `/handoff <ADO id> <name>`: a brief with context, acceptance criteria, where to start and what to watch. Posts nothing. |
| An error log: probable root cause, why, and a fix | Paste it on Fix a bug in Loom (**Error log**), or put it in `.work/spike-log-<name>/log.md` and run `/spike spike-log-<name> --log`. It checks the configuration before the code and prefers a fix that changes no code. Changes nothing. |
| Question or a vague ask, no code changes (writes a shareable `brief.html`) | `/spike <id or topic> [--for business\|engineering\|leadership] [--timebox 1h\|2h\|4h\|1d]` |
| First pass on a teammate's PR | `/pr-review <PR link>` (or **PR reviews** in Loom). Drafts comments in `.work/pr-<id>/review.md`; you post the ones you agree with. Never checks out the PR or posts anything. |
| Ask or capture from Workshop | Type in the hub in Workshop's Loom (Chat tab). It runs `/hub <request>`: captures become proposals you accept, questions are answered from your repo map, repo guides and code, with sources. It writes nothing but its own two files and never changes ADO or git. |
| Prep a 1:1 | **Draft talking points** in Workshop's 1:1s app runs `/one-on-one <packet>`. It drafts wins, follow-ups, blockers, growth topics and 3 questions from the app's packet; it never rates or judges anyone. |
| Docs | `/docs <target>` → read the draft → new session → `/check-docs <doc path>` → fix → `/publish docs-<name>` (approves it in place; you commit it) |
| Technical spec with diagrams | `/tsd <product or repo> [repo ...]` → new session → `/check-docs .work/tsd-<name>/tsd.md` → revise → `/publish tsd-<name>` |
| Where was I? | `/dashboard [id]` (opens Loom in Workshop, at the item when you give an id) or `/status [id]` |
| Drive it from the browser | Loom in [Workshop](https://github.com/adavidson21/workshop): it runs each step in opencode (see [Dashboard](docs/pipeline.md#dashboard)) |
| Hands-off build after the plan | Loom: **Approve and build**. It runs tasks, review, and PR text, each step in a new session, and stops only when it needs you (see [Autopilot](docs/pipeline.md#autopilot)) |
| End of day | `/shutdown`: writes `.work/runway.md` with where you left off, tomorrow's first step, and open loops. Next morning, `/status` shows it first. |
| Is the pipeline helping? | `/stats [--since yyyy-MM-dd]`: days to PR, review rounds, rework, and which gates you approve as written (see [Measuring the pipeline](docs/pipeline.md#measuring-the-pipeline)) |
| Small change (one repo, 1 to 3 tasks) | `/start <id> quick` → `/quick <id>` → `/approve <id>` → `/do-task` → `/review` → `/pr`. One combined spec and plan, one approval. It steps up to the feature lane by itself when the work turns out bigger. |
| Learn from an item | `/retro <id>` after review: what caused rework and up to 5 rules; tick the ones to save. `/retro --since <date>` finds mistakes that repeat across items. |
| Standup update | `/standup [days back]` (default 1, or 3 on a Monday) |
| Cloudflare (your own computer, with Workshop's Cloudflare connector on) | `/cloudflare <what you want>` proposes a change set (DNS, a Worker on a custom domain, Pages projects and variables, rollbacks) that you approve in Workshop's Approvals; `/cloudflare why <worker or project>` reads a failed build's log; `/cloudflare cf-<name> check` confirms what was applied. Agents never hold the token and never apply anything. |
| Switch to something urgent | `/pause <id> [reason]`, later `/resume <id>` |
| New repo in the workspace | `/onboard-repo <folder>` |
| New product, ready for its first build | `/onboard-product <product>` (repo guides, product note, gaps to answer, a trial run) |
| Regression tests for a product that has few | `/cover <product> [-- <area>]` (one hands-off Quick change per UI repo that adds end-to-end tests) |
| Your code review comments (Send back in Workshop) | `/revise <id>`: each comment becomes a fix task, an answer or a declined note; comments marked as rules are remembered. Workshop runs it, then the build comes back to Publish as the next revision. |
| A published PR's CI failed, or it conflicts with its base | `/pr-fix <id> ci` or `/pr-fix <id> conflict`: fixes it on the branch (a merge of the base for a conflict) and never pushes. Workshop runs it after Publish and shows **Push fix**. |
| Remember a rule | `/memory <rule>` (one repo) or `/memory -global <rule>` (every repo). `/memory -list` shows them. |
| Remember a product fact | `/memory -product <product> <fact>` writes it to the product's note in Workshop's Notes app (`notes/products/<product>.md`), where you review it. Agents read the note when they work on that product and add facts they confirm. `/product-notes move` moves product facts out of repo guides; `/product-notes list` lists the notes. |
| Work item in another ADO collection | `/start <id> <lane> <repo folder or connection>` |
| Update eng-agents | `.\update.ps1` in your clone (see [Updating](docs/onboarding-company.md#updating)) |

- **Approve** a spec, plan, or bug analysis with `/approve <id>` (it picks the current draft; add `spec`, `plan`, or `bug` to choose). Edit the file first if anything is wrong. Changing `Status: DRAFT` to `Status: APPROVED` by hand still works.
- **Publish** a finished document with `/publish <folder>`, for example `/publish tsd-orders` (approves it and moves it to the product docs folder) or `/publish docs-run-gateway` (approves a doc where it lives). You commit it.
- **New session** (`/new`) before every `/do-task`.
- **Review findings** you accept become new tasks. Run `/do-task` for each, then `/review` again.
- **You approve every push** and open the PR. No agent can merge or deploy. Outside changes (Cloudflare change sets, MCP tools that change something) are only ever asked for; you approve them in Workshop's Approvals, and Workshop's Activity lists every call.
- **Workshop holds the tokens.** With Workshop installed and started once, `install.ps1` adds Workshop to opencode as an MCP server (`workshop`): its tools for agents, the tools of MCP servers you add in Workshop, and approval status. The GitHub scripts read through Workshop when no token is set here, so a GitHub token can live in the Mac Keychain.
- Every command ends with the next command to run. If lost, run `/dashboard` or `/status <id>`.
- Loom in Workshop is the live UI; `/dashboard` opens it and says to start Workshop if it is not running. The static dashboard (`.work\dashboard.html`, `/dashboard static`) remains for terminal-only use.
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

## What Workshop relies on

Loom's Health > Tandem reads the same numbers as `/stats` with its own port of `Get-PipelineStats.ps1` and `Get-ReviewFindings.ps1`, checked against Workshop's `docs/examples/work/expected-health.json` by `core/scripts/stats/Test-HealthFormat.ps1` in CI.

Workshop's Loom reads `.work` with its own parser. The two repos meet only at the `.work` format, written down in Workshop's [docs/work-format.md](https://github.com/adavidson21/workshop/blob/main/docs/work-format.md) with a synthetic example workspace, and at the command names Loom runs. CI runs `core/scripts/dashboard/Test-WorkFormat.ps1` against a checkout of Workshop, so a change to how Tandem writes `.work` that Workshop would read differently fails here. Change the format in Workshop's doc first.

## License

[PolyForm Shield 1.0.0](https://polyformproject.org/licenses/shield/1.0.0), see `LICENSE`. Free to use, change and share, including at work; not for building a product that competes with it. Versions up to November 5, 2026 were MIT and stay MIT.
