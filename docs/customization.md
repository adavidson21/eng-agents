# Customization guide

Which files you own, how the layers combine, and how to change agents, templates, and Core. Step-by-step setup is in [Personal onboarding](onboarding-personal.md) and [Company onboarding](onboarding-company.md).

## Files to review

### Files you write

Review these when you set up, and again whenever the agents get something wrong.

| # | File | Layer | Needed | Check that |
|---|---|---|---|---|
| 1 | `personal/AGENTS.md` | Personal | Yes | Rules are short instructions, one idea per bullet. No company names. |
| 2 | `%USERPROFILE%\.config\eng-agents\config.json` | Company | To fetch from ADO | One entry under `connections` per collection you work in. `default` and `paths` pick the right one ([ADO setup](onboarding-company.md#3-connect-to-ado)). |
| 3 | `%USERPROFILE%\.config\eng-agents\overlay\AGENTS.md` | Company | Yes | Only rules true in every repo. Base branch and PR target stated if not `main`. |
| 4 | `C:\src\work\AGENTS.md` (repo map) | Company | Yes | No `TODO(you)` or `(example)` rows left. Products, glossary, dependencies, and change order are correct. |
| 5 | Repo guide, one per repo: `C:\src\work\<repo>\AGENTS.md`, or `AGENTS.local.md` when the team committed its own `AGENTS.md` | Company | Yes | Build and test commands work. Architecture rules match reality. Pattern files are good examples. Team guides (committed `CLAUDE.md` files) have the mode you want. No `(inferred, verify)` or `TODO(you)` left. Listed in `.git\info\exclude`. |
| 6 | `overlay\templates\pr.md` | Company | Only if your team has a PR format | Keeps nothing required; any format works. |
| 7 | Product docs (`product-docs\` or `_docs\`) | Company | Recommended | One folder per product, in markdown, linked from each product block in the repo map ([layout](onboarding-company.md#product-docs)). |
| 8 | `%USERPROFILE%\.config\eng-agents\memory.md` and each repo guide's `## Remembered` section | Company | Written by `/memory` | Every line is still true. Merge or delete old lines when the list gets long. |

### Core defaults to know

Read these once so you know what you are overriding. Change them through your own `AGENTS.md` or an override file, not by editing Core.

| File | What it sets |
|---|---|
| [`core/AGENTS.md`](../core/AGENTS.md) | Conventions (base branch, branch names, commit format, 3-file task cap), shell rules, testing rules |
| [`core/templates/`](../core/templates/) | The format of every file the agents write, especially `spec.md`, `plan.md`, and `pr.md` |
| [`core/permissions/`](../core/permissions/) | The shell permission tiers every agent shares: `read`, `build`, `guards` ([Permissions](#permissions)) |
| [`core/opencode.json`](../core/opencode.json) | Global permissions, the global memory file in `instructions` |

## How layering works

`install.ps1` stacks three layers into your opencode config. Later layers win.

| Order | Layer | Source | Who edits it |
|---|---|---|---|
| 1 | Core | `core/` in eng-agents | Maintainers, through pull requests |
| 2 | Personal | `personal/` in your fork | You |
| 3 | Company | `%USERPROFILE%\.config\eng-agents\overlay\` (work PC only) | You, on the work PC |

| File | How layers combine |
|---|---|
| `AGENTS.md` | **Appended.** One section per layer (Core, Personal, Company). When rules conflict, the later section wins. |
| `agents/`, `commands/`, `templates/`, `scripts/` | **Replaced.** A same-named file in a later layer replaces the earlier one. A new name adds a file. |
| `permissions/<tier>.json` | **Merged per tier.** A later layer adds rules or changes a rule's value. Every agent and `opencode.json` that uses the tier gets the result. |
| `opencode.json` | **Merged.** A later layer's entry for the same key wins. Lists such as `instructions` are combined. |

Nothing else in a layer folder is installed (for example `TODO.md`). Re-run `install.ps1` after changing Personal or the overlay.

<details>
<summary>What install.ps1 writes, and its flags</summary>

| Writes to the opencode config folder | Content |
|---|---|
| `agents\`, `commands\` | Layered files |
| `AGENTS.md` | One section per layer between `eng-agents:begin` / `eng-agents:end` markers. Your text outside the markers is kept. HTML comments are stripped. |
| `opencode.json` | Layer settings merged in. Provider and model settings are kept. Shell rules are rewritten as one block in layer order; shell rules you typed into the file yourself are kept, placed right after `"*"` so eng-agents asks and denies still win. An `opencode.jsonc` or unparseable file is left alone and the settings go to `opencode.eng-agents.json` for you to merge. |
| `eng-agents\templates\`, `eng-agents\scripts\` | Templates and scripts. Commands find them through the `{{ENG_HOME}}` token. |
| `eng-agents\manifest.json`, `eng-agents\backup\<time>\` | What was installed (files and shell rules, so removed ones are cleaned up) and copies of anything overwritten |

| Flag | Effect |
|---|---|
| `-DryRun` | Preview, write nothing |
| `-CoreOnly` | Skip Personal and Company |
| `-Target <path>` | opencode config folder (default `~/.config/opencode`, which is `%USERPROFILE%\.config\opencode` on Windows) |
| `-Personal <path>`, `-Company <path>` | Other locations for those layers |

A layer with none of `AGENTS.md`, `opencode.json`, `agents/`, `commands/`, `templates/`, `scripts/`, or `permissions/` is skipped. Install warns if a Personal or Company `AGENTS.md` still contains `TODO(you)`, refuses to run as root, and ends with ADO and memory checks.

Tokens replaced in installed `.md` and `.json` files: `{{ENG_HOME}}` (the installed `eng-agents` folder), `{{ENG_CONFIG}}` (`~/.config/eng-agents`), `{{PS}}` (`powershell` or `pwsh`), and `"{{BASH:<tier>}}": include` lines (the tier's rules).

</details>

## Where does a change go?

Ask in order and stop at the first yes:

1. Does it name or describe a company repo, server, product, team, customer, or work item? **Company** (overlay or a repo `AGENTS.md`).
2. Is it your preference rather than something everyone needs? **Personal.**
3. Otherwise it would help anyone: **Core** (see [Changing Core](#changing-core)), then merge it into your fork.

Use the lightest option that works. A rule in `AGENTS.md` keeps you on Core updates. An override file replaces the Core file and stops updates for it.

### Personal

| Goal | Do this |
|---|---|
| Shorter or more detailed answers, words to avoid | Rule in `personal/AGENTS.md` |
| Change how one agent works | Rules under `## When you are the <agent>` in `personal/AGENTS.md` ([ideas](../personal/TODO.md#rules-for-one-agent)) |
| Commit by hand | Rule: "Never commit. Stage the files and tell me the commit message." |
| Bigger or smaller tasks (Core cap: 3 files) | Rule: "A task changes at most N files." |
| Stop being asked about a shell command | Add it to `personal/permissions/read.json` (read-only) or `build.json` ([Permissions](#permissions)) |
| Different model for one agent | Copy `core/agents/<agent>.md` to `personal/agents/` and add `model:` |
| A new command | New file in `personal/commands/` |

### Company

| Symptom or goal | Do this |
|---|---|
| Plans pick the wrong repos or order | Fix the repo map |
| Wrong build or test command | Fix that repo's `AGENTS.md` |
| Agent breaks an architecture rule | Add the rule to that repo's `AGENTS.md` |
| A rule applies to every repo | Add it to `overlay\AGENTS.md` |
| Base branch or PR target is not `main` | Rule under "Team conventions" in `overlay\AGENTS.md` |
| Team PR or spec format | `overlay\templates\pr.md` or `spec.md` |
| Team TSD format or diagram colors | `overlay\templates\tsd.md` or `tsd-diagrams.md` |
| Company-specific command or agent | `overlay\commands\`, `overlay\agents\` |
| Company-specific shell command (for example an internal CLI) | `overlay\permissions\read.json` or `build.json` |
| Work items live in more than one ADO collection | One entry per collection under `connections` in `config.json`, plus `paths` ([ADO setup](onboarding-company.md#3-connect-to-ado)) |
| A rule the agents keep forgetting | `/memory <rule>` (one repo) or `/memory -global <rule>` |

| After editing | Do this |
|---|---|
| Anything in `overlay\` | Re-run `install.ps1` |
| Repo map or a repo `AGENTS.md` | Start a new opencode session |
| `config.json` | Nothing. Check a mapping with `-ShowConnection` ([ADO setup](onboarding-company.md#3-connect-to-ado)). |
| `ADO_PAT` (or a connection's `patEnv` variable) | Reopen PowerShell |

## Agents

Override an agent by copying its file from `core/agents/` into your layer. Keep its `{{BASH:...}}` lines and its agent-specific denials. Every agent may run the `read` tier (file reads, search, read-only `git` including `fetch`, version checks); the table lists what else it can do.

| Agent | Runs | Can edit | Extra shell commands |
|---|---|---|---|
| `planner` | `/start`, `/spec`, `/plan`, `/tasks`, `/approve`, `/status`, `/pause`, `/resume` | `.work/` only | Branch creation, the ADO script. Switching branches and WIP commits ask. |
| `implementer` | `/do-task` | Code and tests. Repo guides and `CLAUDE.md` ask. | `build` tier, `dotnet format`, `npm install` / `ci`, `git add`. `git commit` asks. |
| `reviewer` | `/review`, `/check-docs` | `.work/` only | `build` tier, the diagram check script |
| `investigator` | `/bug`, `/spike`, `/onboard-repo` | `.work/`. A repo guide and `.git/info/exclude` ask. | `build` tier |
| `writer` | `/pr`, `/docs`, `/tsd`, `/publish`, `/memory` | Any `*.md` file, `docs/`, `.work/`, the global memory file | The diagram check script (`Test-Mermaid.ps1`) |

Unlisted commands ask. Reviewer, investigator, and writer cannot `git add` or `git commit`.

## Permissions

The goal: an agent never stops to ask about something its command needs, and never runs something risky without asking. Shell rules live in three **tiers**, written once and copied into every agent at install:

| Tier | Contains | Used by |
|---|---|---|
| [`read`](../core/permissions/read.json) | Read-only commands: `Get-Content`, `Select-String`, `rg`, `Select-Object`, `Measure-Object`, read-only `git` (`status`, `diff`, `log`, `show`, `fetch`, `grep`, `merge-base`, `worktree list`, ...), version and list commands for `dotnet`, `node`, `npm` | Every agent and `opencode.json` |
| [`build`](../core/permissions/build.json) | `dotnet restore` / `build` / `test`, `dotnet format --verify-no-changes`, npm `test` / `lint` / `build` / `e2e` scripts, `ng`, Playwright, Jest, ESLint, Prettier check, `tsc --noEmit` | Implementer, reviewer, investigator, `opencode.json` |
| [`guards`](../core/permissions/guards.json) | **Ask:** file writes and deletes, web requests, `Start-Process`, `Invoke-Expression`, `cmd /c`, chained commands (`&&`, `\|\|`), environment variables (`env:`), `.env` files, deleting or renaming branches. **Deny:** `git push`, `reset --hard`, `clean`, `restore`, `checkout --`, recursive deletes, `dotnet ef database`, shutdown, anything naming `ADO_PAT`. | Every agent and `opencode.json`, always last |

Other settings in [`core/opencode.json`](../core/opencode.json): templates, scripts, and `~/.config/eng-agents` (global memory) are readable without an external-directory prompt; `webfetch` and repeated identical tool calls (`doom_loop`) ask.

How it fits together:

- Rules are checked top to bottom and the **last match wins**. Each agent lists `"*": ask`, then its tiers, then its own extras, then `guards`. So an allowed command with a risky one chained after it (`dotnet test && git push`) still hits the guard.
- Agent rules are merged with the global `opencode.json` and **win over it**. Because every agent starts with `"*": ask`, a rule added only to `opencode.json` does not reach the eng-agents agents. Add it to a tier instead.
- To stop being asked about a command: add it to `read.json` (read-only) or `build.json` in your Personal or Company layer, re-run `install.ps1`. Keep allows narrow (`npx playwright show-report*`, not `npx *`).
- To change what one agent may do: override that agent and edit its extra lines.
- Day-one check: after installing, run a normal feature through `/start`, `/spec`, `/do-task`, and `/review`. Every prompt you approve with "always" is a candidate for a tier. Add it there so it survives reinstalls.

## Customizing templates

Templates set the **format** of what agents write. Commands say "start from `templates/<name>.md`", so whichever layer provides that file decides the format.

- Team or company format: `overlay\templates\`. Only you: `personal/templates/`.
- Templates replace, they do not merge. If both Personal and Company provide `pr.md`, Company wins. To add your taste on top of a team format, use a rule in `personal/AGENTS.md` (for example "In PR descriptions, list the test evidence first").

To change one: copy the Core file into your layer, edit it, re-run `install.ps1`, and run the command on a real item. Keep the parts commands depend on:

| Template | Used for | Must keep |
|---|---|---|
| `spec.md` | Goal, acceptance criteria, non-goals, decisions, open questions | `Status: DRAFT` line; acceptance criteria numbered `AC-1`, `AC-2` |
| `plan.md` | Approach, changes per repo, test plan, risks | `Status: DRAFT` line; one section per repo; a test plan |
| `bug.md` | Symptom, code path, root cause, fix tasks | `Status: DRAFT` line; root cause; tasks |
| `tasks.md` | Numbered tasks and coverage check | `## [ ] Task N:` headings; each task's repo, files, and verify command |
| `review.md` | Findings and verdict | A verdict line that can say `READY`; each criterion marked `Met` or not |
| `paused.md` | Where a paused item stands | `Status: PAUSED` line, the Repos table, "To resume" |
| `pr.md` | PR title and description per repo | Nothing |
| `tsd.md` | Technical spec sections | `Status: DRAFT` line; `<Diagram: ...>` placeholders, the table under each diagram, "Open questions" |
| `tsd-diagrams.md` | The diagram cookbook `/tsd` copies from | Only `flowchart`, `sequenceDiagram`, `erDiagram`; the "Common errors" and "Check before you finish" sections |
| `tsd-inventory.md` | Facts every TSD diagram is drawn from | A Source column in every table |
| `workitem.md`, `repos.md`, `progress.md`, `findings.md`, `repo-agents.md` | Work item text, lane and branches, log entries, spike answer, repo guide shape | Section headings |

### Add a new kind of document

A template alone does nothing; a **command** decides what gets written. Add both, with matching names, in the layer that owns the format:

```
<layer>/commands/release-notes.md
<layer>/templates/release-notes.md
```

The command:

```markdown
---
description: "Draft release notes. Usage: /release-notes <id> [<id> ...]"
agent: writer
---

Draft release notes for work items: **$ARGUMENTS**. Do not change any code.

1. For each id, read `.work/<id>-*/spec.md` (or `bug.md`), `pr.md`, and `review.md`.
2. Start from `{{ENG_HOME}}/templates/release-notes.md`.
3. Write the result to `.work/release-notes.md`.
4. Tell the engineer the file path.
```

The template (replace with your team's format):

```markdown
# Release notes: <version or date>

<!-- Audience: customers and support. Plain language. No file names, class names, or internal jargon. Leave out any empty section. -->

## New
- **<feature name>:** <what users can do now, in one sentence> (#<id>)

## Fixed
- <what was wrong, from the user's point of view> (#<id>)
```

To have `/publish` move the new document out of `.work` when it is finished, add a row to the table in Step 1 of `commands/publish.md` (override the file in your layer): the file name, its kind, its default destination, and its file name there.

### What makes a template work well

- Show the exact shape with `<placeholders>`. Weaker models copy structure literally.
- Put instructions in `<!-- -->` comments inside the template: audience, tone, what to omit.
- Set limits: "under 70 characters", "at most 5 bullets".
- Keep it short. Every line is something the model has to fill.

## Changing Core

Open a pull request to eng-agents. Before merging:

- [ ] It would help **anyone**. No company names, no personal preferences.
- [ ] Shell permission changes for everyone go in `core/permissions/`. Changes for one agent go in that agent file, before its `{{BASH:guards}}` line.
- [ ] `Status: DRAFT` lines in the `spec`, `plan`, `bug`, and `tsd` templates, `Status: PAUSED` in `paused`, and `## [ ] Task N:` headings in `tasks` are unchanged.
- [ ] Docs that describe the behavior are updated.
- [ ] `pwsh ./install.ps1 -DryRun` runs cleanly.
- [ ] For a notable release, tag it (`core-v2`, ...) and tell teammates to `git fetch upstream` and `git merge upstream/main` in their forks.

## Never

- Company names, URLs, code, or work item content in `core/` or `personal/`
- A pull request to eng-agents that includes a `personal/` folder
- The PAT in any file
- An agent that can push, merge, or deploy
