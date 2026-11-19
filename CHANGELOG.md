# Changelog

Core has one version (`core/VERSION`). `update.ps1` reads this file to show what is new. Until Core 2.11.0 the dashboard had its own version; its `## Dashboard` entries below are history.

Format: one `## Core <version> (<date>)` heading per release, newest first, with one `- ` line per change. Bump the version in the same pull request.

## Core 4.11.0 (2026-11-19)

Cloudflare through Workshop (Workshop 1.11.0, its Cloudflare connector). Agents never hold a token: Workshop does, in this computer's secret store. Nothing breaks for items in progress.
- `/cloudflare <what you want>`: reads your account through Workshop, writes `.work/cf-<name>/plan.md` and a change set (DNS records, a Worker on a custom domain, Pages projects, domains and variables, rollbacks, build retries), checks it, and proposes it. You apply it in Workshop (Settings, Cloudflare; Needs you links there). `/cloudflare why <worker or project>` reads the failed build's log and says the probable cause and the fix; `/cloudflare cf-<name> check` confirms what was applied. Runs as the investigator: it changes no code and applies nothing.
- `scripts/workshop/Invoke-WorkshopTool.ps1`: runs one of Workshop's tools for agents (`/api/tools`, read actions a connector marks for agents) with Workshop's agent token, and prints JSON or a `NOWORKSHOP`, `NOTOOL`, `REFUSED` or `FAILED` line. `-Arg name=value,...` avoids JSON quoting in Windows PowerShell; `-ArgsFile` for change sets. `Test-WorkshopTool.ps1` checks it against a fake Workshop, in CI.
- Guards: every agent asks before reading a secret store (`security`, `secret-tool`, `CredRead`, `Get-StoredCredential`) or Workshop's agent token and secret list, and is refused Workshop's per-install token. `opencode.json` asks before reading anything in `~/.workshop`. The hub and chat agents deny all of these.

## Core 4.10.0 (2026-11-19)

Epics hand off to builds, and products onboard themselves (Workshop project doc `claude/loom-floor-v1-plan.md`, Loom 6.5.0). Nothing breaks for items in progress.
- Approve the breakdown once: `/backlog scope-<name> local` gives each story's `workitem.md` its epic, story number, the local ids it waits for (`- Depends on:`), its repos and areas, and `- Breakdown: approved`. `milestones.md`'s builder notes gain an `Areas:` line, which `/slice` fills.
- Hold by exception: the new `scripts/work/Test-StoryDrift.ps1` checks a story's plan against its breakdown (task file cap, new dependency, migration, auth or security code, files outside its areas or repos). `/approve <id> spec auto` approves a story's spec and plan only when it prints `CLEAN` and the draft is unedited with no open questions; otherwise it holds the plan for the engineer with the reasons.
- `/start <L id> [lane] auto`: for autopilot, asks nothing, takes the repos from `workitem.md`'s `- Repos:` line.
- `/spec` keeps a story's plan inside its breakdown's areas and says why under Risks when it cannot.
- The new `/onboard-product <product>`: drafts missing repo guides and the product note, logs what it cannot find as gaps (Teach) instead of asking, and creates a trial run (a local Quick change with `- Trial:` that adds one test). Each step is recorded in `.work/_onboarding/<product>.md` by the new `scripts/work/Set-Onboarding.ps1`, for Loom's onboarding view.
- `New-LocalWorkItem.ps1` takes `-Epic`, `-Story`, `-DependsOn`, `-Repos`, `-Areas`, `-BreakdownApproved` and `-Trial`.

## Core 4.9.0 (2026-11-18)

The software factory (Workshop project doc `claude/software-factory-v1-plan.md`): you approve the plan and publish the PR, everything between runs on its own with lighter checks. Nothing breaks for items in progress.
- Factory settings: commands read `.work/factory.json` (written by Workshop's Settings, Factory; defaults when missing): task size cap, quick lane task cap, retries, which review findings become fix tasks, review rounds, UI checks, worktrees. See the pipeline guide.
- Lighter checks: a task may change 6 files and test files do not count (was 3, tests counted); the quick lane allows 3 tasks (was 2), and `/approve <id> quick auto` approves up to 3; `/do-task` runs only its verify command and a full check on the last task (`/review` runs the full build and tests once for the item and reads `baseline.md`).
- `/review auto` also turns Should fix findings into fix tasks (factory `autoFix`, default `should-fix`); Nits are never tasks. Later rounds read only what changed since the `Reviewed at:` commit.
- Catch up with the base: `/review` and `/pr` rebase each branch on its base first (never force, never push). A conflict becomes a `conflict` Blocker with a fix task; at `/pr` it stops with "Needs you".
- UI checks: the new `scripts/ui/Test-Ui.ps1` starts the app from the repo guide's new `## UI checks` table, screenshots its pages at two widths in headless Chromium (Playwright), checks load errors, console errors, failed requests and simple accessibility, compares with the `before` run `/start` takes, and stops the app. `/review` runs it when a change touches UI files; problems are `ui` Blockers. It skips (never fails) when the app cannot start locally or Playwright is missing. `/onboard-repo` fills the table.
- Knowledge gaps: core rule 3 logs missing knowledge with the new `scripts/work/Add-Gap.ps1` (`.work/gaps.md`) instead of asking, and keeps going on a safe assumption. The new `/teach G<n> <answer>` (Workshop's Teach card) writes the answer where it belongs and closes the gap with `Close-Gap.ps1`.
- Run retro: `/pr` runs the new `scripts/work/Find-Repeats.ps1`, which suggests a fix once for a review finding (same repo and category) or a gap (same kind and product) that comes back in 3 items, in Folio's review list.
- Core rule 6: the retry limit comes from the factory settings; in `auto` mode Workshop gives a failed step one fresh session before it waits for you.
- `/start` puts every repo of a build in its own worktree by default (factory `worktrees: always`), so several projects build side by side.
- Local items: only an item linked to ADO (`- ADO item: <n>`, or a numbered item not marked unlinked) gets `AB#<n>` in commits and PR text; a local item gets its id.

## Core 4.8.0 (2026-11-18)

Ideas from Diraigent (Workshop project doc `claude/diraigent-ideas-v1-plan.md`). Nothing breaks for items in progress.
- Observations: core rule 5 now logs what an agent notices out of scope with the new `scripts/work/Add-Observation.ps1` (into `.work/observations.md`, at most 3 per command, duplicates skipped), instead of burying it in progress notes. Workshop's Loom shows them in its Inbox (Noticed).
- Decisions: `/approve` writes the engineer's lasting answers from spec.md's Decisions table to the product note's `Decisions` section (at most 3, through `Set-ProductNote.ps1`), so the next item does not argue them again.
- Review by exception: `/approve <id> quick auto` approves a clean quick plan (unedited draft, no open questions, at most 3 assumptions, at most 2 tasks) and otherwise leaves it with "Needs you: <why>". Workshop's autopilot runs it only when hands-off Quick changes are on.
- Worktrees: `/start` and `/resume` never switch a busy repo. They make a git worktree with the new `scripts/work/New-Worktree.ps1` (`.worktrees/<work folder>/<repo>`) and write it in repos.md's new **Path** column; every command then works there. Two items on one repo can build at once.
- `scripts/work/Test-WorkScripts.ps1` checks both scripts, in CI.

## Core 4.7.0 (2026-11-17)

For Workshop's Knowledge base V1 (Workshop `docs/knowledge.md`): one home for each fact, read in one call.
- `scripts/notes/Get-Knowledge.ps1 -Product <name>` prints a product's Settings fields (repos, change order, entry points, external systems, processes, docs folder), its owners from People, its glossary words, its product note and the team handbook, ending with a Sources line. `-Handbook` prints the handbook alone. The core rules (Product notes) use it instead of reading the map block and then the note.
- `Set-ProductNote.ps1 -Note team/handbook.md | tandem/changes.md` writes the team handbook and Tandem's change log (made from built-in templates on the first line; the log keeps its newest 100 lines). `-Flag "<line>" -Reason <why> -Source <where>` marks a line the code contradicts with `(check: ...)`, which Folio shows as stale.
- `/memory` and `/retro` log every repo guide and global rule change to `tandem/changes.md`, so you review them in Folio with the notes.
- `/product-notes draft <product>` (Workshop's **Draft from sources**): reads the product's READMEs, docs and product docs folder and writes up to 15 note lines with sources, asking nothing.
- Owners live only in Workshop's People: the product template's `People` section is now `Who to ask`, and `/memory -product` sends owner facts to People.
- Writing as the engineer: `<dataDir>/settings/voice.md` (Workshop's Writing voice) wins over the Personal and Company writing rules.
- The hub and chat agents read the handbook and end answers with a `Sources:` list Workshop's Chat turns into links. pr-reviewer runs `Get-Knowledge.ps1`.
- `company/repo-map.template.md` says Workshop writes the repo map from Settings when you use it (Settings, Knowledge, Repo map imports a hand-written one).

## Core 4.6.0 (2026-11-17)

For Workshop's Loom lanes (Loom 5.x: Clarify, Plan, Work, Ready). Nothing breaks for items in progress.
- `/spike` writes `first-look.md` in its first few minutes, from the new `templates/first-look.md`: a quick answer, a confidence and what it will dig into, or for a log (`--log`) the product, environment, error and a first guess. Loom shows it on the card while the spike keeps going.
- `/spike` (question mode) gathers its sources before it writes anything, then asks one focus question with options only when the ask is broad, so the answer is aimed at what you need. Gather first, write after: cheaper models do better on a narrow prompt.
- `/review` runs the repo's UI tests whenever the change touches something a person sees (or records that the repo has none), and treats leftovers and missing docs as Blockers, so the fix tasks run before the PR: the PR goes out built, tested, documented and clean.
- `/pr` starts `pr.md` with a `## Checks` block (builds, unit tests, UI tests, docs, clean up, review verdict) from the recorded runs. Loom shows it at Ready.

## Core 4.5.0 (2026-11-16)

- Product notes follow Workshop's renamed Folio folder: `<dataDir>/folio/products/` (Workshop renames `notes/` to `folio/` on start). `ProductNotes.ps1`, `/hub` and the **chat** agent use `folio/`, or `notes/` while that is the only one there, so an older Workshop keeps working. Old snapshots go to `.trash/folio/history/`.

## Core 4.4.0 (2026-11-16)

- For Workshop's opencode connector 1.18.0, which keeps hub requests and 1:1 packets in the data folder's working folder (`<dataDir>/.scratch/opencode/`, removed after 7 days) instead of `~/.workshop`: the **hub** agent may write `route.json` and `answer.md` there, and **people-prep** may write `draft.md` and list its folder there. The old `_connectors` paths still work for older Workshops.

## Core 4.3.0 (2026-11-16)

- `/spike <folder> --log`: diagnose an error log. Reads `log.md` (Loom writes it from Fix a bug's **Error log**, with secrets masked), finds where it happens, checks the configuration before the code, and writes `findings.md` from the new `templates/diagnosis.md`: the probable root cause with a confidence, why (Confirmed and Suspected steps), and a solution with a `Fix type:` line. It prefers Configuration, then Data, then Infrastructure, then Code, gives the exact setting, where it is set and how to verify, and never copies or opens secrets. No `brief.html` in log mode.
- The static dashboard reads `fixType` and `fromLog` on a diagnosis, the way Workshop's parser does (Loom 4.11.0).

## Core 4.2.0 (2026-11-16)

For Workshop's Loom flow cards (Loom 4.10.0). Nothing breaks for items in progress.
- `/triage` writes a `Path:` line (`interview`, `brief` or `decline`), the next step it suggests; Loom marks it on its triage fork. `/shape triage-<name> brief` (Loom's Skip to the brief) writes the brief on the first run, with no round of questions.
- `/bug` reproduces the bug before the root cause (running the repro, a test, or a throwaway check in `.work`, never the repo) and records it on a new `Reproduced:` line in `bug.md`. High confidence needs a reproduction.
- `/spike --timebox 1h|2h|4h|1d` sets how far it digs (about 10, 15, 25 or 40 files) and says when the timebox ended.
- `/docs` starts `sources.md` with `Doc: <path>` and asks you to read the draft before the fact-check. `/publish docs-<name>` approves a doc where it lives (`Status: SAVED to <path> on <date>` in `sources.md`); you commit it.
- The static dashboard reads a spike closed at Loom's findings fork (`closed.md`) and a saved doc the way Workshop's parser does.
- docs/pipeline.md: a Flow cards section maps each Loom card to the commands.

## Core 4.1.0 (2026-11-15)

Evals become the test suite for all of Tandem (Workshop's Bench 2):
- Smarter runs: `-Affected` (only cases whose prompts changed, from `evals/commands.json` hashes), `-Release` (every case, 3 runs, exits 1 on a drop), `-Gate`, `-MaxRuns` (default 30), `-Models` (model matrix).
- 12 new cases, now 23 covering 17 of 36 commands: `bug-outcome` and `quick-outcome` lift cases with hidden outcome tests, `pr-draft`, `pause-item`, `status-readonly`, `standup-readonly`, `spike-findings`, `triage-words`, `check-docs-planted`, `tsd-draft`, `onboard-repo-guide`. New cases need no code: `Test-Expect` reads an `expect` block.
- Guard cases for all 11 agents with no model (`Test-AgentGuards.ps1`, `evals/guards/expected.json`), in CI.
- Writing judge: `-Judge <provider/model>` grades writing cases on yes/no rubrics (`evals/rubrics/`), free or paid; `Test-Judge.ps1 -Model` calibrates a judge on good and bad examples.
- Improve loop: `Suggest-Fix.ps1` (one prompt edit from failed runs, by a model you pick), `Suggest-Trim.ps1` (one experiment per section, no model), `-Overlay` runs an experiment on a scratch install, `Keep-Experiment.ps1` keeps or drops it.
- `Get-PromptSize.ps1` adds what a command reads while it runs; `-Write` saves `evals/commands.json`, checked in CI.
- Results `version: 4`: `models`, `kind`, `label`, `overlay`, `judge`, `compareTo`; per case `model` and `filesHash`.

## Core 4.0.1 (2026-11-15)

- The static dashboard (`New-Dashboard.ps1`) follows the one feature gate: when `spec.md` and `plan.md` are both drafts, the next step is `/approve <id>` at the plan stage ("Review spec.md, plan.md and tasks.md"), matching Workshop's rule 3a (docs/work-format.md, Loom 4.6.0).

## Core 4.0.0 (2026-11-15)

Breaking: the feature lane has one gate, and `/start` writes no brief unless asked. Items started before this keep working: `/plan` and `/tasks` still run on their own, and `/approve` approves a spec alone when there is no plan yet.

- One feature gate: `/spec` drafts `spec.md`, then `plan.md` and `tasks.md` from it in the same run (three `progress.md` entries, so `/stats` still counts each). One `/approve` approves the spec and the plan together, then `/do-task`. `/plan` and `/tasks` now redo a plan or tasks on their own; `/tasks auto` keeps tasks `/spec` already drafted. `/status` and docs follow. Evals: `feature-outcome` runs `/spec`, the one gate, then `/do-task`.
- `/spec` keeps clear acceptance criteria from the work item in its words, marked `(from work item)`; only new ones are Given / When / Then (the `spec-basic` grader allows both).
- `/approve` shows three lines first: what is approved, how many criteria, tasks and assumptions, and the one thing to watch.
- `/start`: the lane is optional (a Bug starts in `bug`, anything else in `feature`; `quick` is typed). No brief by default; `--brief` adds it (`--cold` is accepted and does nothing). A shorter final reply.
- Shorter `AGENTS.md` (about 2,900 to 2,100 tokens): the work folder files, gates, paused items and conventions move to `guides/pipeline.md`, read only by commands that use `.work/`. Chat, hub, people prep and PR review no longer load them. Rule 6 counts failed tries at the same step, even when the fix changes.
- Reviewer: a new `overbuild` category (abstractions, options or layers nobody asked for, `Should fix`), and a "Questions for you" section in `review.md` for things it is not sure are problems (not findings; the verdict ignores them). `/review` turns Blockers into fix tasks without asking and asks only about the rest.
- Implementer: may change the test file for a listed code file without stopping (still within the 3-file cap). A task whose Human interface is `none, covered by <test command>` gets `Covered by tests: <command>` instead of a manual checklist; the planner may write that line.
- Planner: prefers 4 to 6 tasks and suggests splitting past 8; calls out shared-repo impact at the top of a plan. Milestone architect and `/slice` size stories the same way.
- Product manager, `/scope`, `/refine`: 1 to 3 scenarios per story, and less pull toward V2 / Icebox. `/refine` adds a Release note section.
- Investigator: spikes give at most 3 options with effort and risk and end with one recommendation. `/spike` defaults to the leadership lens and may answer "None." for requester questions. `/bug` adds an Impact line for stakeholders and lists the same flaw elsewhere (not fixed).
- The engineer's voice: the writer follows Personal and Company writing rules for anything the engineer sends (PR text, handoffs, briefs); the PR reviewer drafts comments that way, often as questions; `/triage` adds a ready-to-paste message to the requester; `/one-on-one` and `/handoff` read as the manager wrote them. Chat is casual and pushes back when something simpler would do.
- `/pr`: leads with why, adds a screenshots placeholder for UI changes, and links with `AB#<id>` (ADO) or `Closes owner/repo#<n>` (GitHub). `/do-task` commits follow the convention unless a Personal or Company rule says otherwise (for example `AB#<id>`).
- `/retro` (now the writer) shows candidate rules as a checklist and saves the ones the engineer picks, the way `/memory` does; `auto` saves nothing (the `retro-repeat` eval uses it). `/memory` confirms the wording before saving. `/shutdown` asks about "tomorrow morning" and nudges a cross-item retro once a sprint.
- `/standup` adds Docket tasks done and planned for today (read only from Workshop's data folder) and spikes, shapes and scopes in progress. `/triage` suggests the owning area path and `/backlog` suggests area and iteration paths, from Workshop's products and teams.
- Fewer questions: `/shape` asks at most 3 per round with the brief by round 3; `/tsd` and `/docs` pick for themselves and show their picks; `/pause` always makes a WIP commit; `/onboard-repo` runs the build and test commands without asking; `/pr-review` reads at most 15 extra files; `/resume` replies in 5 lines or fewer.
- Stacks: `dotnet` checks for secrets and personal data in logs; `angular` checks OnPush and signals, logic in templates and accessibility basics.
- Names follow Workshop: Dispatch and Slate are Loom, the 1:1s app is Rapport. `/hub` `go` ids are Workshop's current app ids (`slate` for Loom; `agents` no longer exists).

## Core 3.3.0 (2026-11-15)

- GitHub issues: `/start owner/repo#12 <lane>` (or `/start #12 <lane> <repo folder>`) fetches the issue with the new `scripts/github/Get-GitHubIssue.ps1` and makes it a local work item (`L<n>`), so the rest of the pipeline and Dispatch work unchanged. `workitem.md` keeps the issue as `- GitHub: owner/repo#12` and its link, splits the body into Description, Acceptance criteria and Repro steps by their `##` headings, types it from its labels (`bug`, `story`, `feature`, `epic`, `task`), and lists its sub-issue parent (the Feature) and milestone (the Epic) under Parents. Starting the same issue twice says `ALREADY:`.
- GitHub pull requests: `/pr-review <GitHub PR link>` uses the new `scripts/github/Get-GitHubPullRequest.ps1`, which writes the same `context.md` and `threads.md` as the ADO script. It fetches `refs/pull/<n>/head` (forks too), lists the issues the PR closes as linked work items, and reads reviews, comments and line comments. Read-only: never posts.
- The GitHub token is `GITHUB_PAT` (the variable Workshop's GitHub connector uses), else `GH_TOKEN` or `GITHUB_TOKEN`, else `gh auth token`. `GITHUB_API_URL` points at GitHub Enterprise Server.
- New CI check `core/scripts/github/Test-GitHub.ps1`: the helpers, and an issue written as a local work item from a saved answer (no network).

## Core 3.2.0 (2026-11-15)

- Evals measure efficiency: the runner passes `--format json` to opencode and records each run's tokens, cost, tool calls, questions asked and failed verifies, per step too. Case entries add `meanTokens`, `meanCost`, `tokensPerPass`, `costPerPass`, `meanQuestions`, `meanToolCalls`, `meanVerifyFails` and `promptTokens`. Results files are `version: 3`; Workshop's Bench reads them from opencode connector 1.13.0.
- New `evals/Get-PromptSize.ps1`: what each command loads up front (command, agent, AGENTS.md) in estimated tokens, biggest first. No model; printed in CI.
- Fix: `meanSeconds` in results was always 0.

## Core 3.1.0 (2026-11-14)

- Evals can now show whether Tandem helps: `Invoke-Evals.ps1 -Arm both` runs each case with Tandem and as one plain prompt with Tandem left out (same model, same workspace), and adds a lift table (Tandem's pass rate minus the baseline's). `-Arm baseline` runs only the plain arm. The plain arm uses a config folder made for the run: your `opencode.json` without Tandem's `instructions`, `agent`, `command` and `mode`.
- New case `feature-outcome`: the whole feature lane in one workspace (`/spec`, `/plan`, `/tasks`, `/do-task` per task, gates approved by the script between them), graded on the outcome only, with behavior-only hidden tests (`fixtures/hidden-outcome/`). Cases can list `steps` (`approve` and `eachTask` included) and a `baseline.prompt`.
- Results files are `version: 2`: `arm`, `passAll` (every run passed), `meanSeconds`, and each run's `steps`. Workshop's Bench app (opencode connector 1.13.0) reads them; older files read as the tandem arm.
- New CI check `evals/Test-Harness.ps1`: the harness itself, with a fake opencode (`evals/selftest/fake-opencode`).

## Core 3.0.0 (2026-11-14)

Breaking: repo guides name their tech stacks. A guide without a `Stack:` line still works (agents read every stack file and say so once); run `/onboard-repo <repo>` to add it.

- Stack rules move out of Core's always-loaded rules. New `core/stacks/` (installed to `eng-agents/stacks/`): `dotnet.md`, `angular.md`, `playwright.md`, each with `## Testing` and `## Review checklist`. A repo guide's new `Stack:` line (repo guide template, filled by `/onboard-repo` from the repo's files) says which apply. `/plan`, `/tasks`, `/do-task`, `/review`, the implementer and the reviewer read them. The `/review` checklist keeps the stack-free items (architecture, consistency, correctness, security, tests, leftovers) and adds each stack's items. Personal and Company layers can add or replace stacks (`stacks/<name>.md`), for example a team's Python rules.
- A shorter `AGENTS.md` (146 to 116 lines), loaded in every session: the scope and PR review file tables move into `/scope`, `/slice`, `/backlog` and `/pr-review`; product note writing rules move to `guides/product-notes.md` (installed to `eng-agents/guides/`), read before an agent changes a note; Testing rules point to the stack files.
- `install.ps1` installs `stacks/` and `guides/` from every layer, like `templates/`.
- Evals: the sample repo guide has `Stack: dotnet`.

## Core 2.26.0 (2026-11-14)

- Workshop's Loom shows Tandem health (Health > Tandem: pipeline, learning loop, prompts, setup) from Workshop's opencode connector 1.12.0. It ports `Get-PipelineStats.ps1` and `Get-ReviewFindings.ps1`; the two meet at Workshop's `docs/tandem-health.md` and `docs/examples/work/expected-health.json`.
- New CI check `core/scripts/stats/Test-HealthFormat.ps1`: both scripts must read Workshop's example workspace exactly as `expected-health.json` says.
- `Get-PipelineStats.ps1`: an item with no `Lane:` line takes its lane from the work item's Type (`bug` if it says bug, else `feature`), as Workshop's parser does, instead of `unknown`. Medians and rates round half away from zero, so both sides agree.

## Core 2.25.0 (2026-11-14)

- Quick lane for small work: `/start <id> quick`, then new `/quick <id> [auto]` (planner) writes `quick.md` (new template: goal, acceptance criteria, assumptions, files and pattern to follow, why it fits) and a normal `tasks.md` with at most 2 tasks. One approval (`/approve <id>`), then `/do-task`, `/review` and `/pr` as usual; they read the criteria from `quick.md`. The branch is `dev/feature/<id>-<name>`.
- `/quick` steps up to the feature lane by itself when the work needs more than 2 tasks, a second or shared repo, a schema, migration or API contract change, or criteria it cannot pin down: it sets `Lane: feature` in `repos.md`, writes what it found under Notes, logs `escalated=1`, and points to `/spec`.
- `/status`, `/pause`, `/resume`, `/approve` (`quick` file name), `/do-task` (gate), `/review`, `/pr` and the reviewer know the lane. `New-Dashboard.ps1` gives quick items a `quick` stage (`/quick`, then "Review quick.md and tasks.md") and the static page a Start, Quick plan, Build, Review, PR track. `/stats` counts the `quick` gate and how many quick items stepped up.
- Evals: `small-lane` and `small-lane-escalate` cases, with goldens.
- Workshop's Dispatch reads the lane from Workshop's next release; until then it shows quick items as feature items.

## Core 2.24.0 (2026-11-14)

- Evals: new `evals/` folder. `Invoke-Evals.ps1` builds a made-up workspace per run (a repo map and `sample-api`, a small .NET order pricing library), runs a command with a real model through `opencode run --command`, grades what the agent left behind with file and git checks, and saves `evals/results/<version>-<time>.json` with a comparison against the previous run. First 8 cases: `spec-basic`, `plan-paths`, `tasks-shape`, `do-task` (with hidden acceptance tests), `review-planted` (an off-by-one the branch's own tests miss), `review-clean`, `bug-lane`, `retro-repeat`. See `evals/README.md`.
- CI checks the graders and fixtures without a model: `evals/Test-Graders.ps1` (every hand-written good output passes its grader, every bad one fails; pwsh and Windows PowerShell 5.1) and `evals/Test-Fixtures.ps1` (with dotnet: the fixtures build, the planted bug is real, the do-task grader works end to end).
- `auto` mode for `/spec`, `/plan`, `/tasks`, `/bug` and `/do-task` (like `/review <id> auto`): never ask or wait. Planning commands write would-be questions as assumptions; `/do-task` stops and logs the task as blocked instead of asking.
- `docs/pipeline.md`: use `opencode run --command <name> "<arguments>"` for scripting.

## Core 2.23.0 (2026-11-14)

- New `/retro <id>` (planner): reads every review round, blocked and failed entries, and edited gates, and writes `retro.md` (new template) with what caused rework and at most 5 candidate rules. Each rule names the finding it would have prevented and comes with the exact `/memory` line to save it; `/retro` never writes memory itself. Existing rules that were broken are listed instead of repeated. `/retro --since <date>` finds patterns across items (same repo and category in 2+ items) and writes `.work/_retro/<date>.md`.
- New `core/scripts/stats/Get-ReviewFindings.ps1` (`-Since`, `-Id`, `-AsJson`): every finding from `review.md` and `history/review-*.md`, grouped by repo and category. Older tables without a category read as `uncategorized`. Tested in `Test-PipelineStats.ps1`.
- Review findings have a category. The findings table in `review.md` gets a `Category` column (the `/review` checklist word, or `spec`, `scope`, `checklist`, `tdd`), and Pass 1 problems go in the same table. `/review` copies an earlier round to `history/review-<date>-<n>.md` before writing a new one. `/stats` shows findings by category and how many items that reached `/pr` have a retro.
- Checkable TDD: `/do-task` puts the failing run under `Red run` and the passing run under `Green run` in `progress.md` (template updated), with `red=<test>` on the Stats line. The reviewer checks the Red run shows the new test failing for the expected reason; missing or wrong is `Should fix` (category `tdd`), or a Blocker through a Personal or Company rule.
- `/pr` ends with a reminder to run `/retro` after merge; `/shutdown` adds an open loop for items that reached `/pr` today without a retro.

## Core 2.22.0 (2026-11-14)

- Measure the pipeline. New `/stats [--since yyyy-MM-dd]` (planner, read-only) and `core/scripts/stats/Get-PipelineStats.ps1` (`-AsJson` for Workshop): days from `/start` to `/pr`, review rounds, items needing a second review, questions versus assumptions, `/do-task` verify failures, full-suite failures caught, tasks added after `/tasks`, review findings by severity (and by category when `review.md` has one), and per gate how often you approve the draft as written. Local and read-only; older items show `n/a` where data was never written. Self-test `Test-PipelineStats.ps1`, run in CI.
- Draft hashes. `/spec`, `/plan`, `/bug`, `/scope`, `/slice` and `/refine` finish by running new `core/scripts/work/Set-DraftHash.ps1`, which adds a `Draft-hash:` line under `Status:`. `/approve` runs `Test-DraftHash.ps1` first (new Step 3) and logs `gate=unchanged`, `gate=edited` or `gate=no-hash`. It never blocks approval. Its later steps are renumbered (open questions is Step 4).
- `progress.md` entries can carry a `- Stats:` line of `key=value` pairs. `/spec`, `/plan`, `/bug`, `/scope`, `/slice`, `/refine` (questions, assumptions), `/tasks` (tasks), `/do-task` (verify, full, attempts), `/review` (findings and verdict) and `/approve` (gate, file) write one. Dispatch and the static dashboard ignore it.
- `/do-task` checks nothing else broke before it commits (new Step 5b): it runs the repo's Build, then its new optional **Pre-commit check** command or All unit tests. A failure listed in the new `baseline.md` (written by `/start` Step 7b right after branching, before any change; skip with `--no-baseline`) is noted, not chased. A new failure counts toward the 3-attempt limit and blocks the commit. The repo guide template has the new optional Commands row.
- Guards: every `git -C` rule now has a `git -c *=*` twin, so `git -c key=value push` and the like ask or are denied as intended. Shell wrappers that hide a command (`pwsh -c`/`-Command`, `powershell -c`/`-Command`, `cmd /c`, `bash -c`, `sh -c`, `Start-Process`) ask. Secrets rules also match Windows `\` paths, and reading env vars with `Get-Content env:`, `gc env:`, `cat env:`, `type env:` and `Select-String` asks.
- The read-only hub and chat agents allowed `Get-Content`, `Get-ChildItem` and similar on any path, which included env vars, `.env` files and `~/.ssh`. They now deny those.
- `webfetch` is `ask` for the implementer and reviewer (pr-reviewer, hub, chat and people-prep already deny it).
- New CI check `tests/Test-Guards.ps1`: installs Core and resolves a list of risky and everyday commands against `opencode.json` and every agent, last match wins.

## Core 2.21.0 (2026-11-12)

- `/spike` answers vague asks ("how hard would it be to add X?") as a brief with three readers. `findings.md` (new template) has header lines `Asked by`, `Size`, `Effort` (a range), `Confidence`, `Lenses` and `Default lens`, sections The ask, Short answer, Questions for the requester, Current state, Options, Risks and dependencies, Recommendation, Next step and Sources, and `### For business`, `### For engineering` and `### For leadership` blocks inside them. `/spike <topic> --for leadership` picks the lens the brief opens on.
- New `core/scripts/briefs/Export-Brief.ps1`: turns `findings.md` into `brief.html` next to it, one self-contained page to share outside Workshop (email, Teams, SharePoint, Save as PDF). No web requests and no script: the lens switch is plain HTML and CSS, and printing prints the open lens. Older findings without `Lenses:` still export, without the switch. `/spike` runs it as its last step. Self-test `Test-ExportBrief.ps1`, run in CI.

## Core 2.20.1 (2026-11-12)

- New CI check `core/scripts/dashboard/Test-WorkFormat.ps1`: `New-Dashboard.ps1 -AsJson` must read Workshop's example `.work` workspace the way Workshop's `docs/work-format.md` says. Workshop's Dispatch has its own parser; the `.work` format is the one thing the two repos share. README: "What Workshop relies on".
- Fixes `/dashboard static` failing in Windows PowerShell 5.1 with a parse error in `New-Dashboard.ps1`: one regex had a non-ASCII arrow, which 5.1 misreads in a file without a byte order mark. It is now `\u2192`. Found by the new check.

## Core 2.20.0 (2026-11-11)

- Lighter features and stories, so engineering decides the implementation. A feature's description is two or three sentences of what and why, and each feature gets a `#### Release note`: one or two business-friendly sentences (at most 255 characters). Stories keep the "As a ..." line with at most two sentences of context and 2 to 5 outcome-only Gherkin scenarios (no button labels, layouts, field names or data shapes unless asked). `/scope`, `/slice`, `/refine`, product-manager and milestone-architect follow this.
- `/backlog`: a story's code mapping is now "Notes for the builder" and stays local (only `local` items include it); ADO and the CSV get the story without it or the "Part of" block. Release notes go to their own field: set `releaseNoteField` (reference name, for `ado`; a connection may override it) and `releaseNoteColumn` (display name, for `csv`) in `config.json`. When unset they are left out and the output says so. `Export-Backlog.ps1 -Check` now requires a feature description (at most 600 characters) and a release note, and still reads older "Work item" headings. `/spec` reads a story's builder notes from its scope through `published.md`, as hints.
- New self-test `core/scripts/ado/Test-ExportBacklog.ps1`, run in CI.

## Core 2.19.1 (2026-11-09)

- Fixes `/pr-review` failing with "Agent not found: pr-reviewer" even after restarting opencode. pr-reviewer's own `git push*` rules repeated keys from the shared guard rules, and opencode skips an agent whose frontmatter repeats a key. `install.ps1` now leaves out a guard rule when the agent writes the same key itself (the agent's rule wins, as in `opencode.json`). A new check installs Core and fails on any repeated frontmatter key.

## Core 2.19.0 (2026-11-08)

- `/dashboard` and the static page's Dispatch link no longer name Workshop's website. They use the site Workshop's agent reports (`GET /api/health`, agent 1.5.0), else the first https site in Workshop's `config.json`, else Workshop on this computer. `"dispatch": { "url" }` in `config.json` and work mode work as before.

## Core 2.18.0 (2026-11-07)

- Triage: `/triage <ADO id> <note>` keeps the note. Anything after the id (who asked, why it matters, a deadline) goes in `.work/triage-<id>/note.md`, dated, and counts as part of the request; a re-triage reads it too. Workshop's Slate sends the note you typed with `#1234 <note>` in quick capture (Slate 2.3.0).

## Core 2.17.0 (2026-11-06)

- The static dashboard matches Workshop again: its theme block is Workshop's current Light and Dark (the old seven themes map to the closer of the two), and its fonts are Workshop's Figtree and DM Mono, inlined so the page still works offline with no web requests.

## Core 2.16.0 (2026-11-06)

- Shape: `/shape <idea>` (product-manager) interviews you about an idea before it is defined, one round per run and never in the chat. Its questions go in a file the engineer asked for, so core rule 3's 3-question cap does not apply; it still asks at most 5 per round, never asks what the files answer, and writes safe guesses as assumptions. Each round writes up to 5 questions with options and a recommendation to `.work/shape-<name>/questions.md` (new `templates/shape-questions.md`, with `Status: ASKING | READY` and `Round:` lines Workshop's Slate reads) and keeps a running `understanding.md` (`templates/shape-understanding.md`; your edits win). Your answers go in `answers.md`. When the idea is understood, or with `/shape shape-<name> brief`, it writes `brief.md` (`templates/shape-brief.md`) with a `Level:` and `Size:`. `/shape triage-<name>` starts from a triage; `/shape shape-<name> more` asks another round. product-manager may now also write `.work/shape-*/`.
- `/scope shape-<name>` and `/refine shape-<name>` start from a brief: they write `.work/scope-<name>/` or `.work/refine-<name>/` and ask only what the brief leaves open.

## Core 2.15.0 (2026-11-06)

- Agents ask fewer questions and avoid over-engineering, so Dispatch runs and chats do not keep piling up questions. Core rule 3 now says: check the files and earlier decisions first, ask only when a wrong guess would change what gets built or be hard to undo, otherwise assume the recommended answer and record it under "Assumptions"; at most 3 questions per command. New core rule 8, Simple but built to maintain: smallest thing that meets the acceptance criteria and is easy to change later (values likely to change go in existing config, follow the repo's extension points, clear seams), without speculative features, unrequested options or single-use layers.
- `/spec` asks at most 3 questions (was 6) and writes the rest as assumptions; the spec template has an "Assumptions" section.
- `planner` caps questions at 3 per command, never re-asks what the spec decided, and plans the simplest maintainable design. `product-manager` skips questions it can safely assume. `chat` answers first and asks at most one question per reply.

## Core 2.14.0 (2026-11-06)

- New read-only `chat` agent for conversations from Workshop's Dispatch (hub follow-ups and the Chat tab, Dispatch 1.7.0). It reads the repo map, repo guides, product notes, code, git history and `.work`, runs only the hub's read-only commands, and cannot write any file. Workshop names it on every message it sends, so a reply never goes to an agent that can edit.

## Core 2.13.2 (2026-11-06)

- `/hub`: `route.json` must be the bare JSON object (no code fence or text around it), with `version` as the number `1` and no extra fields. For a question the final reply now carries a short version of the answer, so Workshop's Dispatch can show it when it cannot read the files (Dispatch 1.6.1 shows what the session said).

## Core 2.13.1 (2026-11-06)

- `update.ps1` no longer stops with a git error on Windows PowerShell 5.1 when a git call it expects might fail (for example `git show` of a file the tag does not have). Its git helper now returns the failure, as it says it does.

## Core 2.13.0 (2026-11-05)

- Product notes: one note per product in Workshop's Notes app (`<Workshop data folder>/notes/products/<slug>.md`, Notes 2.1.0 or later), for what the code cannot tell agents. The core rules (Product notes) say when to read one and when to add to it, and the split rule: product facts go in the note, code facts stay in the repo guide.
- New `scripts/notes/Get-ProductNote.ps1` (read one, or `-List`) and `Set-ProductNote.ps1` (add or replace one line with its date and source, or `-Create` a note from Notes' `templates/product.md`). The setter follows Notes' contract: it writes only `products/` and `history/`, keeps the earlier version in Notes' history format first (Notes, History restores it), writes atomically, and sets `tandem-changed` so Notes shows **Changed by Tandem** until you mark it reviewed. Both skip product notes when Workshop is not installed or Notes is switched off.
- `/memory -product <product> <fact>` saves a product fact; `/memory` offers it when a rule sounds like one. New `/product-notes move` moves product facts from repo guides' `## Remembered` into product notes after you approve the list; `/product-notes list` lists the notes.
- `/onboard-repo` creates a missing product note for the products the repo belongs to. `/triage`, `/refine`, `/scope`, `/handoff` and the hub read product notes; pr-reviewer reads them and suggests lines in `review.md` instead of writing.
- The repo map template has an optional `Note:` line per product.
- First CI for eng-agents: `.github/workflows/checks.yml` runs `scripts/notes/Test-ProductNotes.ps1` on PowerShell 7 (Linux and Windows) and Windows PowerShell 5.1.

## Core 2.12.0 (2026-11-05)

- Triage: `/triage <ADO id or the request in words>` (investigator) takes a first look at an enhancement request before any work starts. It fetches the item and its comments into `.work/triage-<id>/`, reads the repo map, guides and code, and writes `triage.md` from the new `templates/triage.md`: a summary, products and repos, related items, questions for the requester, a `Route:` (delegate, myself, undecided) and a `Size:`. Run it again after the requester answers. It never posts to ADO.
- Refine: `/refine <title>` (product-manager) defines one story or bug: at most 2 questions, then `.work/refine-<name>/refine.md` from the new `templates/refine.md` with a Description and Gherkin Acceptance criteria. `/approve refine-<name>` approves it; `/refine refine-<name>` revises a draft. product-manager may now also write `.work/refine-*/`.
- Handoff: `/handoff <ADO id> <name>` (writer) writes a brief for the person the work is delegated to, in `.work/handoff-<id>/handoff.md` from the new `templates/handoff.md`. It posts nothing.
- These three are the steps behind Slate, Workshop's request-to-decision app, which runs them from buttons. They work the same from the terminal.

## Core 2.11.0 (2026-11-05)

- The live dashboard moved to Dispatch, the Agents app in Workshop (adavidson21/workshop, with its opencode connector). Dispatch is now the one live UI for Tandem's agents, and the live dashboard server is removed: `scripts/dashboard/live-server.mjs`, `server/` and its tests, `Start-LiveDashboard.ps1`, its update checks, and the shell API for showing the page inside another app (`shellOrigins`, the page token, `docs/shell-api.md`). eng-agents no longer needs Node.
- `/dashboard` opens Dispatch in your browser, and `/dashboard <id>` opens it at that item (new `scripts/dashboard/Open-Dispatch.ps1`). It starts nothing: if Workshop is not running, it says to start it (`workshop up`) and stops. It opens Workshop's site, or Workshop on this computer in work mode; `"dispatch": { "url": "..." }` in `config.json` sets another address.
- `/dashboard static` and `/status` are unchanged. The static page drops its live-mode code, and its top bar links to Dispatch instead of checking for the live dashboard on port 4300. Nothing rewrites `.work/dashboard.html` in the background any more: `/dashboard static` rebuilds it. `New-Dashboard.ps1 -AsJson` stays the `.work` parser that Workshop's connector copies.
- What replaces each command: `/dashboard` (start the live dashboard) is now `/dashboard` (open Dispatch; start Workshop with `workshop up`). `Start-LiveDashboard.ps1` and `Start-LiveDashboard.ps1 -Detach` are now `workshop up`. `update.ps1 -Component dashboard` and `install.ps1 -Component dashboard` still run but update everything. `update.ps1 -Check -Json` is removed; use `update.ps1 -Check`.
- What replaces each live dashboard button: Run, Approve, Resume, the agent panel, prompts and questions, Push, Abandon and Remove, alerts, Open in terminal, and Autopilot (**Approve and build**, **Build with autopilot**) are in Dispatch. The code review API and its revision runner are Dispatch's review screen. **Update available** is gone: run `.\update.ps1` (Workshop's `workshop update --latest` prints the line when eng-agents is behind).
- One version: `core/scripts/dashboard/VERSION` (last Dashboard 1.10.1) is removed, `install.ps1` records only Core in `manifest.json`, and the static page shows Core's version.

## Core 2.10.0 (2026-11-05)

- Hub: Docket task captures name people and groups by their directory ids (`who`), copied from the request's People section, instead of names (`people`). People lines now carry an `@handle`, and groups (`g_...` ids) are listed with their members; a group is assigned like a person (Workshop `docs/people.md` v2).
- Hub: the `go` app ids match Workshop today: Rapport (`receipts`) holds 1:1s; Queue and the separate 1:1s app are gone.

## Core 2.9.0 (2026-11-03)

- Hub: `/hub <path to request.md>` (new **hub** agent) handles one message from the hub on Workshop's Dispatch page. It writes `route.json` next to the request: a capture (Docket task, receipt or note, as proposals the engineer accepts in Dispatch), a question, a place to go, a suggested action, or a clarifying question (Workshop `docs/hub.md`, `docs/schemas/hub-route.schema.json`). For a question it goes on to answer from the repo map, repo guides, code and `.work`, and writes `answer.md` from the new `templates/hub-answer.md` (Confirmed and Suspected lines with sources).
- The request lives in Workshop's own folder, not the workspace. The hub agent may write only `route.json` and `answer.md` there, runs only read-only commands (`git log`, `git show`, `git grep`, `git ls-files`, `rg`, listing and reading files), cannot fetch web pages, and never assigns, creates or changes anything. A suggested action is a button the engineer clicks in Dispatch.

## Core 2.8.1 (2026-11-03)

- `update.ps1 -Tag <tag>` fetches tags, checks that release tag out (detached) and reinstalls from it. It refuses when the clone has local changes. Without `-Tag` it pulls the branch as before and prints a line saying to pass `-Tag` on a work laptop.
- Docs name release tags `core-v<core version>` (for example `core-v2.8.1`).
- `company/repo-map.template.md` uses neutral examples (orders, catalog, notifications, a reporting job).
- README and `docs/pipeline.md` say that Dispatch in Workshop is the main UI and the static dashboard remains for terminal-only use.

## Core 2.8.0 (2026-11-03)

- 1:1 prep: `/one-on-one <path to packet.md>` (new **people-prep** agent) reads a prep packet from Workshop's 1:1s app and writes `draft.md` next to it: wins to recognize, follow-ups from last time, blockers to ask about, growth topics, and 3 questions to ask (new `templates/one-on-one.md`). It drafts only: it never rates, ranks or judges the person, and uses only facts in the packet.
- The packet lives in Workshop's own folder, not the workspace. people-prep may edit only that `draft.md`, may run no shell command except listing that folder, and cannot fetch web pages.

## Dashboard 1.10.1 (2026-11-02)

- `brief.md` (written by `/start`, Core 2.7.0) is listed right after `workitem.md` in an item's files.

## Core 2.7.0 (2026-11-02)

- Warm start: `/start` ends by writing `.work/<id>-<name>/brief.md` from the new `templates/brief.md`, and prints it. It has the goal, the acceptance criteria as a checklist, where the item fits (parent Feature and Epic), the last 5 comments, the repos and branch, up to 10 likely files, and the first tiny step. Likely files are guesses from file names and commit messages only; no file is opened. `/start <id> <lane> --cold` skips it.
- `Get-WorkItem.ps1 -Parents` adds a "Parents" section to `workitem.md`: id, type and title of each parent up the hierarchy. If a parent cannot be fetched, the section says "Parents unknown" and the script still succeeds. Without the switch, `workitem.md` is unchanged. `/start` passes `-Parents` and `-IncludeComments`.
- `/resume` prints the brief (if there is one) and the last `progress.md` entry before it restores the repos.

## Core 2.6.0 (2026-11-02)

- First-pass PR reviews for your team's pull requests: `/pr-review <PR link or number>` (new **pr-reviewer** agent) checks the PR against its linked work items' acceptance criteria, then for real problems, and writes numbered draft comments (file, line, severity, why, the comment itself) to `.work/pr-<id>/review.md`. It never posts, votes, or approves; you post the ones you agree with.
- `scripts/ado/Get-PullRequest.ps1` reads the PR, linked work items, and existing comments (GET only) and fetches the PR's branches into private refs (`refs/eng-agents/pr/<id>/`) in your existing clone. Nothing is checked out. PRs from forks are read from ADO's merge ref. Re-running after new pushes moves the old review to `history/`.
- The ADO connection logic shared by the scripts moved to `scripts/ado/AdoConnection.ps1`. `Get-WorkItem.ps1` uses it; behavior is unchanged.

## Dashboard 1.10.0 (2026-11-02)

- `pr-<id>` folders show as PR review cards: the recommendation and comment count, a link to the PR, and a Run button when the review is unfinished or out of date. `-AsJson` carries the parsed review (`items[].prReview`: recommendation, risk, comments, questions) for Workshop's Dispatch.

## Dashboard 1.9.0 (2026-11-02)

- Revision runner: request changes sends the feedback to the agent as one revision task on the same branch, then returns the review as the next revision once the agent writes its response file. A run that ends without a valid response, or that rewrote history, stays in revising with the reason shown.
- Code review API for Dispatch's review screen, on the shell API: `GET /api/shell/code-review/<id>?repo=`, `GET .../file`, `POST .../submit`. One review per work item and repo, served from git in the workspace. Approve only records the verdict; nothing is pushed. Request changes saves the feedback, sets the review to `revising`, and signals the revision runner. Round 2 adds the agent's responses, the files changed since the last review, and a `prev` side for file content. Reviews are stored in `.work/<folder>/code-review/<repo>/`. See [docs/shell-api.md](docs/shell-api.md#code-review). Restart the live dashboard after updating.

## Dashboard 1.8.1 (2026-11-02)

- A published TSD (`Status: PUBLISHED to <path> on <date>`, written by `/publish`) shows as Published. Before, that line read as UNKNOWN and the TSD showed as a draft.
- `sync-themes.mjs` is removed. The static dashboard keeps its own themes; Workshop's Dispatch is the live front end.
- The repo now has an MIT `LICENSE`, like Workshop.

## Core 2.5.0 (2026-11-02)

- Manual validation checklist: every passing `/do-task` ends with 3 to 5 physical steps (exact URL, exact click or command, exact result), saved in `progress.md` and printed last.
- Tasks carry a "Human interface" line (page, button, endpoint, or command) so the checklist is built from real routes, not guesses. Set by `/tasks` and `/bug`.
- `/review` marks a missing or vague checklist as a Blocker and collects every task's checklist into a new "Manual validation" section of `review.md`. Checklist Blockers never become fix tasks (they change no code), so autopilot stops and asks you to add the missing checklist as a new `progress.md` entry.

## Core 2.4.0 (2026-11-02)

- Scoping before work items: `/scope <idea>` (new **product-manager** agent) turns an idea into an epic, MVP features, and user stories with Gherkin acceptance criteria. `/slice scope-<name>` (new **milestone-architect** agent) maps the stories to code and orders them into vertical-slice features and stories sized for one `/start` run each. Both are gated with `/approve scope-<name>`.
- `/backlog scope-<name> [csv|ado|local]` exports the result: an ADO import CSV (default), ADO items with parent links (dry run first, asks before pushing), or local `L<number>` items (`scripts/ado/Export-Backlog.ps1`).
- `New-LocalWorkItem.ps1` takes `-AcceptanceCriteria`.
- `/shutdown`: end-of-day command. Captures uncommitted work across repos and what is in your head, and writes `.work/runway.md` with tomorrow's first step and open loops. `/status` with no id shows the runway first.

## Dashboard 1.8.0 (2026-11-02)

- `scope-<name>` folders show as Scope cards with their stage and next step.

## Core 2.3.0 (2026-11-01)

- Repos whose main line is not `main` work: `/start` finds each repo's base (`origin/HEAD`, else `origin/main` or `origin/master`; for a repo with no remote, its local `main` or `master`) and records it in a new **Base** column in `repos.md`. `/review`, `/pr` and `/resume` compare against it (items started before this use `origin/main`). PR text targets the base, and says there is nothing to push for a repo with no remote.
- PR text and hand-offs name "your git host" instead of only ADO.
- Install output: Azure DevOps not being set up is one info line (it is optional), not two to-dos.

## Core 2.2.0 (2026-10-31)

- Work without a tracker item: `/start new <feature|bug>` asks you to describe the work and creates `.work/L<number>-<name>/` with a local id (`scripts/work/New-LocalWorkItem.ps1`). `/start L<number> <lane>` continues a local item created elsewhere (Workshop's Dispatch creates the folder, then runs it). Every other command takes the local id like a work item number.
- `/start` stops early with a clear message when the workspace has no repos, uses the only repo when there is one, and works without a repo map.
- `/start <number>` without ADO set up asks for the work item's details in chat and fills in `workitem.md` itself, instead of asking you to edit the file.

## Dashboard 1.7.0 (2026-10-31)

- Local work items (`L<number>-<name>` folders) show as work items, with no ADO link unless `workitem.md` has a `Link:` line.

## Dashboard 1.6.1 (2026-10-15)

- The shell app is now called Workshop (repo `adavidson21/workshop`). `sync-themes.mjs` reads its themes from there; docs updated.

## Dashboard 1.6.0 (2026-10-15)

- The live dashboard server is split into modules in `core/scripts/dashboard/server/` (one per concern); `live-server.mjs` is now just the HTTP server and startup. Same behavior. Restart the live dashboard after updating.
- Step wording ("Task 3: Add test", "Write the spec") is defined once, in `New-Dashboard.ps1`. Each next step carries `text`, and the page data carries `stepWords`.
- The shell API reports its contract version (`api: 1`). The contract is documented in [docs/shell-api.md](docs/shell-api.md).
- Themes now come from the EM Hub's `shared/themes.css` (the prioritizer repo, reorganized as the EM Hub). `sync-themes.mjs` reads the new path.

## Dashboard 1.5.1 (2026-10-15)

- The shell API (`/api/shell/status`) also sends each item's next step in plain words (`next.text`) and whether autopilot is running or needs you (`autopilot`), so Prioritizer can show them.

## Dashboard 1.5.0 (2026-10-15)

- `Start-LiveDashboard.ps1 -Detach`: starts the live dashboard in its own minimized window and returns once it answers, or opens it if it is already running.
- The live dashboard keeps `.work/dashboard.html` current, so after a restart that file shows where everything stood.
- The static page shows whether the live dashboard is running, with **Open live dashboard** or how to start it.

## Core 2.1.0 (2026-10-15)

- `/dashboard` opens the live dashboard, starting it if needed, and falls back to the static page. `/dashboard static` builds the static page.

## Dashboard 1.4.0 (2026-10-15)

- One main button per step. The Next line says the step in plain words ("Task 3: Update invoice totals") and offers **Approve and build** or **Build with autopilot** when autopilot can take over, otherwise **Run**, **Approve**, or **Resume**. The command is in the tooltip.
- The autopilot box only shows while autopilot is running or needs you.
- No terminal hints in the live dashboard ("then /approve", "After approval: /tasks", Copy buttons). The static page keeps them.
- Simpler header: one status pill, Update available only when there is one, and a More menu for Refresh, alerts, the TUI, the terminal command, and Check for updates.
- The group count chips only show when there are more than 8 items.

## Dashboard 1.3.0 (2026-10-15)

- Push button on PR cards in the live dashboard: runs `git -C <repo> push -u origin <branch>` for the branch named in `pr.md`. The click is the approval, so there is no separate prompt. It never pushes `main`, `master`, `develop`, `dev`, or the PR's target branch, and never force pushes. Git errors (for example, a sign-in failure) show in the toast and the server log.

## Dashboard 1.2.1 (2026-10-14)

- The item in Pick up here is no longer shown again as a full card in its group. The group shows a one-line pointer to it instead.
- Pick up here has its own Abandon button.

## Dashboard 1.2.0 (2026-10-14)

- Abandon or remove an item from the live dashboard: type the item id to confirm, and its `.work` folder, sessions, and autopilot state are deleted. Repos and branches are left alone; the dialog lists work still in them and the commands to delete the branches.
- Ready to ship items show the PR text from `pr.md` per repo, with copy buttons for the title and description, a Create PR in ADO button, and the push command when a branch is not pushed yet.
- Recent activity is one line per item per day ("Did 3 tasks, reviewed, wrote PR text") instead of every log entry.
- Clearer track: finished stages are checked, the current stage is a filled label with what is happening under it, later stages are faint.

## Dashboard 1.1.0 (2026-10-13)

- Shows inside a shell app: sites listed in `config.json` under `dashboard.shellOrigins` can embed the live dashboard and read each work item's stage. Prioritizer uses this for its Dashboard view and task badges.
- `/api/shell/start` starts a work item (`/start <id> <lane>`) from a listed shell, in a new opencode session.
- The page can only be framed by itself and listed shells.
- Themes now come from Prioritizer's `themes.css` (`sync-themes.mjs`). Adds Solarized Light, Nord, and Dracula, and a warn color for each theme.
- `Start-LiveDashboard.ps1 -ShellOrigin <url>` for a one-off shell without editing `config.json`.

## Dashboard 1.0.0 (2026-10-13)

- First versioned release of the live dashboard.
- New look: Slate, Graphite, Ivory, and Rosé themes, or follow the system setting. Pick one from the theme button in the header.
- Update notice: the live dashboard checks for updates and shows "Update available" in the header. Update the dashboard from the page; it restarts itself.
- Shows the installed dashboard version in the header.

## Core 2.0.0 (2026-10-13)

- Versioned installs. `install.ps1` records the version, source repo, commit, and overridden files in the manifest.
- `update.ps1`: pulls, shows what is new, warns (with diffs) when Core changed a file you override, then reinstalls.
- `install.ps1 -Component dashboard` and `update.ps1 -Component dashboard` update only the dashboard.
