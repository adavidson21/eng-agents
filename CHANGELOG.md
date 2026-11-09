# Changelog

Core has one version (`core/VERSION`). `update.ps1` reads this file to show what is new. Until Core 2.11.0 the dashboard had its own version; its `## Dashboard` entries below are history.

Format: one `## Core <version> (<date>)` heading per release, newest first, with one `- ` line per change. Bump the version in the same pull request.

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
