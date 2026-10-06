# Customization guide

Which files you own, how the layers combine, and how to change agents, templates, and Core. Step-by-step setup is in [Personal onboarding](onboarding-personal.md) and [Company onboarding](onboarding-company.md).

## Files to review

### Files you write

Review these when you set up, and again whenever the agents get something wrong.

| # | File | Layer | Needed | Check that |
|---|---|---|---|---|
| 1 | `personal/AGENTS.md` | Personal | Yes | Rules are short instructions, one idea per bullet. No company names. |
| 2 | `%USERPROFILE%\.config\eng-agents\config.json` | Company | To fetch from ADO | `serverUrl`, `collection`, `apiVersion`, and `auth` match your server. |
| 3 | `%USERPROFILE%\.config\eng-agents\overlay\AGENTS.md` | Company | Yes | Only rules true in every repo. Base branch and PR target stated if not `main`. |
| 4 | `C:\src\work\AGENTS.md` (repo map) | Company | Yes | No `TODO(you)` or `(example)` rows left. Products, glossary, dependencies, and change order are correct. |
| 5 | `C:\src\work\<repo>\AGENTS.md` (one per repo) | Company | Yes | Build and test commands work. Architecture rules match reality. Pattern files are good examples. No `(inferred, verify)` or `TODO(you)` left. Listed in `.git\info\exclude`. |
| 6 | `overlay\templates\pr.md` | Company | Only if your team has a PR format | Keeps nothing required; any format works. |

### Core defaults to know

Read these once so you know what you are overriding. Change them through your own `AGENTS.md` or an override file, not by editing Core.

| File | What it sets |
|---|---|
| [`core/AGENTS.md`](../core/AGENTS.md) | Conventions (base branch, branch names, commit format, 3-file task cap), shell rules, testing rules |
| [`core/templates/`](../core/templates/) | The format of every file the agents write, especially `spec.md`, `plan.md`, and `pr.md` |
| [`core/opencode.json`](../core/opencode.json) | The permission tiers every agent shares |

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
| `opencode.json` | **Merged.** A later layer's entry for the same permission key wins. |

Nothing else in a layer folder is installed (for example `TODO.md`). Re-run `install.ps1` after changing Personal or the overlay.

<details>
<summary>What install.ps1 writes, and its flags</summary>

| Writes to the opencode config folder | Content |
|---|---|
| `agents\`, `commands\` | Layered files |
| `AGENTS.md` | One section per layer between `eng-agents:begin` / `eng-agents:end` markers. Your text outside the markers is kept. HTML comments are stripped. |
| `opencode.json` | Layer permissions merged in. Provider and model settings are kept. An `opencode.jsonc` or unparseable file is left alone and the permissions go to `opencode.eng-agents.json` for you to merge. |
| `eng-agents\templates\`, `eng-agents\scripts\` | Templates and scripts. Commands find them through the `{{ENG_HOME}}` token. |
| `eng-agents\manifest.json`, `eng-agents\backup\<time>\` | What was installed (so removed files are cleaned up) and copies of anything overwritten |

| Flag | Effect |
|---|---|
| `-DryRun` | Preview, write nothing |
| `-CoreOnly` | Skip Personal and Company |
| `-Target <path>` | opencode config folder (default `~/.config/opencode`, which is `%USERPROFILE%\.config\opencode` on Windows) |
| `-Personal <path>`, `-Company <path>` | Other locations for those layers |

A layer with none of `AGENTS.md`, `opencode.json`, `agents/`, `commands/`, `templates/`, or `scripts/` is skipped. Install warns if a Personal or Company `AGENTS.md` still contains `TODO(you)`, refuses to run as root, and ends with two ADO checks.

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
| Company-specific command, agent, or permission | `overlay\commands\`, `overlay\agents\`, `overlay\opencode.json` |

| After editing | Do this |
|---|---|
| Anything in `overlay\` | Re-run `install.ps1` |
| Repo map or a repo `AGENTS.md` | Start a new opencode session |
| `config.json` | Nothing |
| `ADO_PAT` | Reopen PowerShell |

## Agents

Override an agent by copying its file from `core/agents/` into your layer. Keep its destructive-command denials. Every agent may run read-only commands (file reads, search, read-only `git`, version checks); the table lists what else it can do.

| Agent | Runs | Can edit | Extra shell commands |
|---|---|---|---|
| `planner` | `/start`, `/spec`, `/plan`, `/tasks`, `/status`, `/pause`, `/resume` | `.work/` only | `git fetch origin`, branch creation, the ADO script. Switching branches and WIP commits ask. |
| `implementer` | `/do-task` | Code and tests. `AGENTS.md` asks. | Build, test, lint, `dotnet format`, `npm install` / `ci`, `git add`. `git commit` asks. |
| `reviewer` | `/review`, `/check-docs` | `.work/` only | Build, test, lint |
| `investigator` | `/bug`, `/spike`, `/onboard-repo` | `.work/`. A repo `AGENTS.md` and `.git/info/exclude` ask. | Build, test, lint |
| `writer` | `/pr`, `/docs` | Any `*.md` file, `docs/`, `.work/` | None |

Unlisted commands ask. Denied for every agent: `git push`, `git reset --hard`, `git clean`, `git restore`, `git checkout --`, recursive deletes, `dotnet ef database`, shutdown. Reviewer, investigator, and writer also cannot `git add` or `git commit`. Permission rules are evaluated top to bottom and the last match wins, so the denials at the bottom catch risky commands chained after allowed ones.

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

### What makes a template work well

- Show the exact shape with `<placeholders>`. Weaker models copy structure literally.
- Put instructions in `<!-- -->` comments inside the template: audience, tone, what to omit.
- Set limits: "under 70 characters", "at most 5 bullets".
- Keep it short. Every line is something the model has to fill.

## Changing Core

Open a pull request to eng-agents. Before merging:

- [ ] It would help **anyone**. No company names, no personal preferences.
- [ ] Permission changes are made in `core/opencode.json` **and** every agent file that repeats the same tier lists.
- [ ] `Status: DRAFT` lines in the `spec`, `plan`, and `bug` templates, `Status: PAUSED` in `paused`, and `## [ ] Task N:` headings in `tasks` are unchanged.
- [ ] Docs that describe the behavior are updated.
- [ ] `pwsh ./install.ps1 -DryRun` runs cleanly.
- [ ] For a notable release, tag it (`core-v2`, ...) and tell teammates to `git fetch upstream` and `git merge upstream/main` in their forks.

## Never

- Company names, URLs, code, or work item content in `core/` or `personal/`
- A pull request to eng-agents that includes a `personal/` folder
- The PAT in any file
- An agent that can push, merge, or deploy
