# Customization guide

How the three layers combine, which files you can add or override, and how to change templates. For step-by-step setup, see [Personal onboarding](onboarding-personal.md) and [Company onboarding](onboarding-company.md).

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

### Where does a change go?

Ask in order and stop at the first yes:

1. Does it name or describe a company repo, server, product, team, customer, or work item? **Company** (overlay or a repo `AGENTS.md`).
2. Is it your preference rather than something everyone needs? **Personal.**
3. Otherwise it would help anyone: **Core** (see [Contributing](../CONTRIBUTING.md)), then merge it into your fork.

Use the lightest option that works. A rule in `AGENTS.md` keeps you on Core updates; an override file replaces the Core file and stops updates for it.

## Personal layer

Lives in `personal/` in your fork. No company names.

| File | Use |
|---|---|
| `personal/AGENTS.md` | Your rules for every session: tone, code taste, workflow, writing style |
| `personal/commands/<name>.md` | Extra commands (for example `/standup`), or a replacement for a Core command |
| `personal/agents/<name>.md` | Replacement for a Core agent, for example to set a model or temperature |
| `personal/templates/<name>.md` | Replacement for a Core template |
| `personal/opencode.json` | Permission entries merged over Core |

| Goal | Do this |
|---|---|
| Shorter or more detailed answers, words to avoid | Rule in `personal/AGENTS.md` |
| Change how one agent works | Rules under `## When you are the <agent>` in `personal/AGENTS.md` ([ideas](../personal/TODO.md#rules-for-one-agent)) |
| Commit by hand | Rule: "Never commit. Stage the files and tell me the commit message." |
| Bigger or smaller tasks (Core cap: 3 files) | Rule: "A task changes at most N files." |
| Different model for one agent | Copy `core/agents/<agent>.md` to `personal/agents/` and add `model:` |
| A new command | New file in `personal/commands/` |

## Company layer

Lives on the work PC only. Never committed anywhere.

| File | Use | Loaded | After editing |
|---|---|---|---|
| `overlay\AGENTS.md` | Rules for every repo at work: data never to log, required patterns, where standards live, conventions that differ from Core | Every session, last section | Reinstall |
| `overlay\templates\<name>.md` | Team formats, for example PR sections | By the command that uses the template | Reinstall |
| `overlay\commands\`, `overlay\agents\` | Company-specific commands or agent changes | Like Core | Reinstall |
| `overlay\opencode.json` | Permissions for company tools | Merged over Core and Personal | Reinstall |
| `config.json` (next to `overlay\`) | ADO server, collection, project, api-version, auth | By the ADO script in `/start` | Nothing |
| `ADO_PAT` environment variable | ADO token | By the ADO script | Reopen PowerShell |
| `C:\src\work\AGENTS.md` | Repo map: repos, products, glossary, dependencies, change order | Every session started from `C:\src\work` | New session |
| `C:\src\work\<repo>\AGENTS.md` | Per-repo guide: commands, architecture rules, patterns to follow, test helpers | Read by each command before touching that repo | New session |

| Symptom or goal | Do this |
|---|---|
| Plans pick the wrong repos or order | Fix the repo map |
| Wrong build or test command | Fix that repo's `AGENTS.md` |
| Agent breaks an architecture rule | Add the rule to that repo's `AGENTS.md` |
| A rule applies to every repo | Add it to `overlay\AGENTS.md` |
| Base branch or PR target is not `main` | Rule under "Team conventions" in `overlay\AGENTS.md` |
| Team PR or spec format | `overlay\templates\pr.md` or `spec.md` |

## Overriding Core files

Any Core agent, command, or template can be replaced from Personal or Company by a file with the same name in the same subfolder. Agents and commands are listed in the [reference](reference.md). When you override an agent, keep its destructive-command denials.

## Customizing templates

Templates set the **format** of what agents write. Commands say "start from `templates/<name>.md`", so whichever layer provides that file decides the format.

- Team or company format: `overlay\templates\`. Only you: `personal/templates/`.
- Templates replace, they do not merge. If both Personal and Company provide `pr.md`, Company wins. To add your taste on top of a team format, use a rule in `personal/AGENTS.md` instead (for example "In PR descriptions, list the test evidence first").

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

## Never

- Company names, URLs, code, or work item content in `core/` or `personal/`
- A pull request to eng-agents that includes your `personal/` folder
- The PAT in any file
- An agent that can push, merge, or deploy
