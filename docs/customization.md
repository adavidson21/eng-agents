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
| [`core/permissions/`](../core/permissions/) | `guards.json`: the shell commands every agent asks about or never runs ([Permissions](#permissions)) |
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
| Stop being asked about a shell command | Set it to `allow` in `personal/permissions/guards.json` ([Permissions](#permissions)) |
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
| Company-specific command that should ask or never run (for example an internal deploy CLI) | `overlay\permissions\guards.json` |
| Work items live in more than one ADO collection | One entry per collection under `connections` in `config.json`, plus `paths` ([ADO setup](onboarding-company.md#3-connect-to-ado)) |
| A rule the agents keep forgetting | `/memory <rule>` (one repo) or `/memory -global <rule>` |

| After editing | Do this |
|---|---|
| Anything in `overlay\` | Re-run `install.ps1` |
| Repo map or a repo `AGENTS.md` | Start a new opencode session |
| `config.json` | Nothing. Check a mapping with `-ShowConnection` ([ADO setup](onboarding-company.md#3-connect-to-ado)). |
| `ADO_PAT` (or a connection's `patEnv` variable) | Reopen PowerShell |

## Agents

Override an agent by copying its file from `core/agents/` into your layer. Keep its `"*": allow` and `{{BASH:guards}}` lines and its agent-specific rules. Every agent may run any shell command except what [`guards`](#permissions) asks about or denies; the table lists what differs per agent.

| Agent | Runs | Can edit | Shell, beyond `guards` |
|---|---|---|---|
| `planner` | `/start`, `/spec`, `/plan`, `/tasks`, `/approve`, `/status`, `/standup`, `/pause`, `/resume` | `.work/` only | Can commit (WIP commits from `/pause`) |
| `implementer` | `/do-task` | Code and tests. Repo guides, `CLAUDE.md`, and opencode config ask. | Can commit |
| `reviewer` | `/review`, `/check-docs` | `.work/` only | Cannot `git add` or `git commit` |
| `investigator` | `/bug`, `/spike`, `/onboard-repo` | `.work/`. A repo guide and `.git/info/exclude` ask. | Cannot `git add` or `git commit` |
| `writer` | `/pr`, `/docs`, `/tsd`, `/publish`, `/memory` | Any `*.md` file, `docs/`, `.work/`, the global memory file. opencode config asks. | Cannot `git add` or `git commit` |

Lanes are kept by what each agent can **edit** and **commit**, not by which shell commands it may run.

## Permissions

The goal: an agent only stops for something you would actually care about. Shell commands, reads, and file access outside the workspace are **allowed by default**. The exceptions live in one shared tier, [`guards`](../core/permissions/guards.json), copied into every agent at install:

| | What |
|---|---|
| **Ask** | `git push`, `npm publish`, `dotnet nuget push`, `docker push`. Deleting a file. Git that rewrites or moves history or branches (`merge`, `rebase`, `pull`, `reset`, `cherry-pick`, `revert`, deleting or renaming branches, `stash drop`/`clear`, creating tags, changing `git config` or remotes). Secrets (`.env` files, env var listings, `~/.ssh`, `~/.azure`, `~/.aws`, `.npmrc`, `.git-credentials`, `dotnet user-secrets`, `cmdkey`). Network and remote machines (web requests, `ssh`, PowerShell remoting, `az`). `Invoke-Expression` and encoded commands. Machine-wide changes (global npm and dotnet tools, `winget`/`choco`/`brew`, `Install-Module`, `sudo`/RunAs, execution policy, registry, persistent env vars, services, killing processes, scheduled tasks, firewall, Defender, ACLs). `sqlcmd`, Docker removals. |
| **Deny** | Anything with `--force`, plus force pushes (`push -f`, `+branch`) and `branch -f`/`tag -f`. `reset --hard`, `clean`, `restore`, `checkout --`/`.`/`-f`, `switch -f`/`--discard-changes`, history rewrites (`filter-branch`, `reflog expire`). Recursive deletes. `dotnet ef database`, `dotnet ef migrations remove`. Unpublishing or deleting packages (`npm unpublish`, `npm deprecate`, `dotnet nuget delete`). Disk formatting, shutdown, restart. Anything naming `ADO_PAT`. |

Other settings in [`core/opencode.json`](../core/opencode.json):

- `external_directory` allows everything except the secret folders above (`~/.ssh`, `~/.azure`, Windows credential stores, ...), so agents work across sibling repos and the shared repo without prompts.
- `edit` denies `.git` internals and `.env` files, and asks before changing opencode's own config (`~/.config/opencode`, any `opencode.json`), so an agent cannot rewrite its own permissions.
- `webfetch` is allowed. Repeated identical tool calls (`doom_loop`) ask.

How it fits together:

- opencode splits a command line into its separate commands (each side of `|`, `;`, `&&`) and checks each one. One guarded command anywhere in the line triggers the ask or deny.
- Rules are checked top to bottom and the **last match wins**. Each agent lists `"*": allow`, then `guards`, then its own rules (such as the `git add` and `git commit` denials).
- Agent rules are merged with the global `opencode.json` and **win over it**. Add shared rules to `guards`, not only to `opencode.json`.
- To stop being asked about a guarded command, change its value in a `guards.json` in your Personal or Company layer (for example `"Stop-Process *": "allow"`) and re-run `install.ps1`. A later layer changes the value in place, so order is kept.
- To be asked about something new, add it to that `guards.json` with `"ask"`. Patterns match one command, so start them with the command name (`"terraform apply*": "ask"`). Use a leading `*` only to catch the command when it is wrapped (`"*rm -rf*"`).
- Older setups had `read.json` and `build.json` allowlists. They are no longer needed and install ignores what they would add.

## Customizing templates

Templates set the **format** of what agents write. Commands say "start from `templates/<name>.md`", so whichever layer provides that file decides the format.

- Team or company format: `overlay\templates\`. Only you: `personal/templates/`.
- Templates replace, they do not merge. If both Personal and Company provide `pr.md`, Company wins. To add your taste on top of a team format, use a rule in `personal/AGENTS.md` (for example "In PR descriptions, list the test evidence first").

To change one: copy the Core file into your layer, edit it, re-run `install.ps1`, and run the command on a real item. Keep the parts commands and the dashboard depend on:

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
| `workitem.md`, `repos.md`, `progress.md`, `findings.md`, `repo-agents.md` | Work item text, lane and branches, log entries, spike answer, repo guide shape | Section headings. The dashboard also reads the `# Work item <id>: <title>` heading and `Type`, `State`, `ADO`, `Link` lines in `workitem.md`; the `Lane:` line and repo table in `repos.md`; and the `## <date> \| /<command> \| <agent>` headings with `Did`, `Verify`, `Notes`, `Next` lines in `progress.md`. |

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
- [ ] Shell permission changes for everyone go in `core/permissions/`. Changes for one agent go in that agent file, after its `{{BASH:guards}}` line.
- [ ] `Status: DRAFT` lines in the `spec`, `plan`, `bug`, and `tsd` templates, `Status: PAUSED` in `paused`, and `## [ ] Task N:` headings in `tasks` are unchanged.
- [ ] If you changed the next-command rules in `core/commands/status.md`, `Get-NextStep` in `core/scripts/dashboard/New-Dashboard.ps1` matches them (the static and live dashboards both use it).
- [ ] Docs that describe the behavior are updated.
- [ ] The version is bumped: `core/VERSION` for Core, `core/scripts/dashboard/VERSION` for the dashboard (major for breaking changes, minor for features, patch for fixes), with a `## Core <version> (<date>)` or `## Dashboard <version> (<date>)` entry at the top of `CHANGELOG.md`. `update.ps1` and the live dashboard show these entries.
- [ ] `pwsh ./install.ps1 -DryRun` runs cleanly.
- [ ] For a notable release, tag it (`core-v2.1.0`, `dashboard-v1.2.0`) and tell teammates to `git fetch upstream` and `git merge upstream/main` in their forks, then run `.\update.ps1`.

## Never

- Company names, URLs, code, or work item content in `core/` or `personal/`
- A pull request to eng-agents that includes a `personal/` folder
- The PAT in any file
- An agent that can push without asking, merge, or deploy
