# personal/

This folder is your **Personal layer**: how *you* like to work. It is empty in the base repo. Fill it in your own copy (your fork), never in the base repo.

`install.ps1` layers it on top of Core and under your Company overlay. This `TODO.md` is never installed.

## What belongs here

Only things that would be true at any company and reflect your own taste. Nothing that names your employer, its repos, servers, products, or work items (that goes in the Company layer, see `company/TODO.md`).

| Create | Effect | Required? |
|---|---|---|
| `AGENTS.md` | Appended after the Core section in every session. Your house rules. | Recommended |
| `commands/<name>.md` | Adds a slash command, or replaces a Core command with the same name. | Optional |
| `agents/<name>.md` | Adds an agent, or replaces a Core agent with the same name (for example to set `model:`). | Optional |
| `templates/<name>.md` | Replaces a Core template with the same name. | Optional |
| `opencode.json` | Permission entries merged over Core (looser or tighter shell rules). | Optional |

Other files at the top of this folder (like this one) are not installed.

## What to put in AGENTS.md

Short bullet rules under a few headings. Ideas to keep, change, or skip:

- **How to talk to me:** concise or detailed, say when you are unsure, ask before guessing, words or punctuation to avoid.
- **Code preferences:** naming, comments only for *why*, early returns, no new packages without asking.
- **Workflow:** whether the implementer commits after each task (Core default: yes, with your approval) or only stages files; task size cap (Core default: 3 files).
- **Writing:** PR description length, tone for anything a reviewer reads.

Write rules as instructions to the model ("Never...", "Prefer..."). HTML comments (`<!-- -->`) are stripped by install, so use them for notes to yourself.

## Command ideas

- `/standup [days]`: drafts Yesterday / Today / Blockers from every `.work/*/progress.md`. Run as the `planner` agent, read-only.
- Anything you repeat often that is about *your* role, not the pipeline.

## Set up checklist

- [ ] Create `personal/AGENTS.md` with your rules
- [ ] Add any personal commands, agents, templates, or `opencode.json`
- [ ] Run `pwsh ./install.ps1 -DryRun` and confirm it shows a Personal section
- [ ] Commit `personal/` to **your copy only**. Never send it to the base repo.

Leave this file in place. If you delete it and the base repo later edits it, git reports a conflict that you resolve by deleting it again.
