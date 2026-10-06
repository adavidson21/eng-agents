# Customization guide

How the Personal and Company layers work, which files you can add or change, and what each one is for. For step-by-step setup, use [Personal onboarding](onboarding-personal.md) and [Company onboarding](onboarding-company.md).

## How layering works

`install.ps1` stacks three layers into your opencode config. Later layers win.

| Order | Layer | Source | Who edits it |
|---|---|---|---|
| 1 | Core | `core/` in eng-agents | Maintainers, through pull requests |
| 2 | Personal | `personal/` in your fork | You |
| 3 | Company | `%USERPROFILE%\.config\eng-agents\overlay\` on the work PC | You, on the work PC only |

How each kind of file combines:

| File | How layers combine |
|---|---|
| `AGENTS.md` | **Appended.** Each layer becomes its own section (Core, then Personal, then Company). When rules conflict, the later section wins. |
| `agents/<name>.md`, `commands/<name>.md`, `templates/<name>.md`, `scripts/...` | **Replaced.** A same-named file in a later layer replaces the earlier one. A new name adds a new file. |
| `opencode.json` | **Merged.** Permission entries are combined; a later layer's entry for the same key wins. |

Other files at the top of a layer folder (like `TODO.md`) are never installed. Re-run `install.ps1` after changing anything in Personal or the overlay.

### Which layer?

Ask in order and stop at the first yes:

1. Does it name or describe a company repo, server, product, team, customer, or work item? **Company.**
2. Is it true at any company, but it is your preference? **Personal.**
3. Would it help anyone using the pipeline? **Core** (open a pull request to eng-agents).

## Personal layer

Lives in `personal/` in your fork. Committed to your fork, never to eng-agents. No company names.

| File | Use | Change it when |
|---|---|---|
| `personal/AGENTS.md` | Your house rules for every session: tone, code taste, workflow, writing style | You want the agents to behave differently for you |
| `personal/commands/<name>.md` | Extra slash commands, or a replacement for a Core command | You repeat a task that is about your role (for example `/standup`) |
| `personal/agents/<name>.md` | A replacement for a Core agent | You need a different model or temperature for one agent |
| `personal/templates/<name>.md` | A replacement for a Core template | You want a different structure for a spec, plan, or PR |
| `personal/opencode.json` | Permission entries merged over Core | Prompts are too frequent, or you want something to ask that Core allows |

Common customizations:

| Goal | Do this |
|---|---|
| Shorter or more detailed answers | Rule in `personal/AGENTS.md` |
| Change how one agent works (for example the implementer) | Rules under `## When you are the implementer` in `personal/AGENTS.md`. Ideas in [personal/TODO.md](../personal/TODO.md#rules-for-one-agent). |
| Commit by hand instead of after each task | Rule: "Never commit. Stage the files and tell me the commit message." |
| Bigger or smaller tasks (Core: 3 files) | Rule: "A task changes at most N files." |
| Words or punctuation to avoid | Rule in `personal/AGENTS.md` |
| A different model for the implementer | Copy `core/agents/implementer.md` to `personal/agents/` and add `model:` |
| A weekly summary command | New file in `personal/commands/` |

## Company layer

Lives on the work PC only. Never committed to eng-agents or your fork.

| File | Use | Loaded | Reinstall? |
|---|---|---|---|
| `overlay\AGENTS.md` | Rules for every repo at work: data that must never be logged, required patterns, where standards live, conventions that differ from Core | Every session, last section | Yes |
| `overlay\templates\pr.md` | Team PR sections, if your team expects any | By `/pr` | Yes |
| `overlay\commands\`, `overlay\agents\` | Company-specific commands or agent changes | Like Core | Yes |
| `overlay\opencode.json` | Permissions for company tools | Merged over Core and Personal | Yes |
| `config.json` (next to `overlay\`) | ADO server, collection, api-version, auth | By the ADO script in `/start` | No |
| `ADO_PAT` environment variable | ADO token | By the ADO script | No |
| `C:\src\work\AGENTS.md` | Repo map: what each repo is, how they depend on each other, which go together, glossary | Every session started from `C:\src\work` | No, new session |
| `C:\src\work\<repo>\AGENTS.md` | Per-repo guide: build and test commands, architecture rules, patterns to follow, test helpers | Read by each command before touching that repo | No, new session |

Common customizations:

| Goal | Do this |
|---|---|
| Plans pick the wrong repos or order | Fix the repo map |
| Agent uses the wrong build or test command | Fix that repo's `AGENTS.md` |
| Agent breaks an architecture rule | Add the rule to that repo's `AGENTS.md` |
| A rule applies to every repo | Add it to `overlay\AGENTS.md` |
| Different base branch or PR target than `main` | Rule under "Team conventions" in `overlay\AGENTS.md` |
| Team-specific PR format | `overlay\templates\pr.md` |
| Team feature spec format | `overlay\templates\spec.md` (see [Customizing templates](#customizing-templates)) |
| Release notes in the team's format | `overlay\commands\release-notes.md` and `overlay\templates\release-notes.md` (see [Customizing templates](#add-a-new-kind-of-document-release-notes-feature-announcements)) |

## Core files you can override

Any of these can be replaced from Personal or Company by a file with the same name in the same subfolder. Prefer a rule in `AGENTS.md` first: an override replaces the whole file, so you stop getting Core updates for it.

### Agents (`agents/`)

| File | Use |
|---|---|
| `planner.md` | Writes specs, plans, and tasks. Reads code, writes only in `.work/`. |
| `implementer.md` | The only agent that edits code. One task at a time, TDD for .NET, commits with your approval. |
| `reviewer.md` | Two-pass review: spec compliance, then code quality. Runs tests, cannot edit code. |
| `investigator.md` | Bugs, spikes, and repo onboarding. Reads and runs code, cannot change it. |
| `writer.md` | Docs and PR text. Edits markdown only. |

Each agent file lists its own permissions. When you override one, keep the destructive-command denials at the bottom.

### Commands (`commands/`)

| File | Command | Use |
|---|---|---|
| `start.md` | `/start <id> <feature\|bug>` | Pull the work item, create `.work/<id>-<name>/`, create branches |
| `spec.md` | `/spec <id>` | Clarifying questions, then `spec.md` |
| `plan.md` | `/plan <id>` | `plan.md` from an approved spec |
| `tasks.md` | `/tasks <id>` | Small tasks with verify commands |
| `do-task.md` | `/do-task <id> <n>` | Do one task |
| `review.md` | `/review <id>` | Review the diff |
| `pr.md` | `/pr <id>` | PR title and description |
| `bug.md` | `/bug <id>` | Root cause and up to 3 fix tasks |
| `spike.md` | `/spike <topic>` | Read-only investigation |
| `docs.md` | `/docs <target>` | Write or update docs |
| `check-docs.md` | `/check-docs <path>` | Fact-check a doc against the code |
| `onboard-repo.md` | `/onboard-repo <folder>` | Draft a repo `AGENTS.md` |
| `status.md` | `/status [id]` | Where an item is and what to run next |
| `pause.md` | `/pause <id> [reason]` | Put an item on hold with a summary to pick it up later |
| `resume.md` | `/resume <id>` | Restore branches and pick a paused item back up |

### Templates (`templates/`)

| File | Use |
|---|---|
| `workitem.md` | Work item text |
| `repos.md` | Lane, repos in order, branches |
| `spec.md` | Goal, acceptance criteria, non-goals, open questions |
| `plan.md` | Approach, changes per repo, test plan, risks |
| `tasks.md` | Task format and coverage check |
| `progress.md` | Log entry format |
| `review.md` | Review findings |
| `pr.md` | PR title and description per repo |
| `bug.md` | Bug root cause and fix tasks |
| `findings.md` | Spike answer and recommendation |
| `paused.md` | Where a paused item stands and how to resume |
| `repo-agents.md` | Shape of every repo `AGENTS.md` |

To change any of these, see [Customizing templates](#customizing-templates).

## Customizing templates

Templates set the **format** of what the agents write. Commands say "start from `templates/<name>.md`", so whichever layer provides that file decides the format.

### Which layer?

| The format is decided by | Put the template in |
|---|---|
| Your team or company (PR sections reviewers expect, feature spec format, release note format) | `overlay\templates\` on the work PC |
| Only you | `personal/templates/` in your fork |

Templates **replace**, they do not merge. If both Personal and Company provide `pr.md`, the Company one wins and yours is ignored. To add your own taste on top of a team format, write a rule in `personal/AGENTS.md` instead, for example "In PR descriptions, list the test evidence first."

### Change an existing template

1. Copy the Core file into your layer, for example `core/templates/pr.md` to `overlay\templates\pr.md`.
2. Edit the copy. Keep the parts other commands depend on (below).
3. Re-run `install.ps1`.
4. Run the command on a real item and check the output.

| Template | Keep | Free to change |
|---|---|---|
| `spec.md` | `Status: DRAFT` line; an "Acceptance criteria" section numbered `AC-1`, `AC-2` | Everything else. Add sections like "Rollout" or "Telemetry". |
| `plan.md` | `Status: DRAFT` line; one section per repo; a test plan | Everything else |
| `bug.md` | `Status: DRAFT` line; root cause; tasks | Everything else |
| `tasks.md` | `## [ ] Task N:` headings, and each task's repo, files, and verify command | Layout of the coverage check |
| `review.md` | A verdict line that can say `READY`; each criterion marked `Met` or not | Layout |
| `pr.md` | Nothing | Everything |
| `paused.md` | `Status: PAUSED` line, the Repos table, and "To resume" | Wording and extra sections |
| Others | Section headings | Wording and extra sections |

### Add a new kind of document (release notes, feature announcements)

A template on its own does nothing: a **command** decides what gets written. Add both, with matching names, in the layer that owns the format:

```
<layer>/commands/release-notes.md
<layer>/templates/release-notes.md
```

The command (copy and adjust):

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

## Changed
- <behavior users will notice> (#<id>)
```

A good split for a team: the command goes in Core (it would help anyone), each company's format goes in its overlay `templates\`, and each person's taste goes in `personal/AGENTS.md`.

### What makes a template work well

- **Show the exact shape** with `<placeholders>`. A weaker model copies structure literally.
- **Put instructions in `<!-- -->` comments** inside the template: audience, tone, what to leave out. Core templates do this.
- **Set limits**: "under 70 characters", "one sentence", "at most 5 bullets".
- **Say what to omit**, including empty sections.
- **Keep it short.** Every line is something the model has to fill.

## Never

- Company names, URLs, code, or work item content in `core/` or `personal/`
- A pull request to eng-agents that includes your `personal/` folder
- The PAT in any file
- An agent that can push, merge, or deploy
