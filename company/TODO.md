# company/

This folder is a placeholder for the **Company layer**: anything that names or describes your employer, its code, or its systems. It stays **empty in every repo**. The real files live on the work PC only, in the places listed below. `.gitignore` blocks anything else dropped in here.

Worked examples on made-up repos: `practice/overlay/AGENTS.md` (an overlay) and `practice/workspace/AGENTS.md` (a repo map).

## What you create on the work PC

| What | Where | Purpose |
|---|---|---|
| Company overlay | `%USERPROFILE%\.config\eng-agents\overlay\` | Company-wide rules. Overrides Core and Personal. |
| ADO connection | `%USERPROFILE%\.config\eng-agents\config.json` | Server URL, collection, project, api-version. Copy from `core\scripts\ado\config.example.json`. |
| ADO token | User environment variable `ADO_PAT` | Work Items (Read) and Code (Read). Never in a file. |
| Repo map | `C:\src\work\AGENTS.md` | Tells the planner what each repo is and how they connect. **The most important file you write.** |
| Repo guides | `C:\src\work\<repo>\AGENTS.md` | Build, test, architecture rules per repo. Drafted by `/onboard-repo`, reviewed by you. |

Step-by-step commands are in `docs/setup-at-work.md`.

## 1. Company overlay

Same shape as `core/`. Everything is optional except `AGENTS.md`.

| File | Effect |
|---|---|
| `AGENTS.md` | Appended as the last section of every session. |
| `templates/pr.md` | Replaces the Core PR template (if your team expects specific PR sections). |
| `commands/<name>.md`, `agents/<name>.md` | Add or replace commands and agents. |
| `opencode.json` | Permission entries merged over Core and Personal. |

`AGENTS.md` should hold rules that apply to **every** repo at work, for example:

- Data that must never be logged
- Required patterns (authorization on every endpoint, options classes for config, logging style)
- Where the coding standards live ("Read `<repo>/docs/standards.md` before writing code")
- Team conventions that differ from Core (base branch, PR target, commit message format)

Repo-specific rules go in that repo's guide, not here.

## 2. Repo map (`C:\src\work\AGENTS.md`)

Use these sections. Keep each table short and accurate; a wrong map produces wrong plans.

```markdown
# Workspace repo map

## Repos
| Folder | What it is | Stack | Shared? |

## How the repos depend on each other
All cross-repo references are relative paths, so every repo stays cloned directly in this folder.
| Repo | Depends on | How | Example reference |

Rule: change a shared repo first, then run the tests of every dependent repo the work item touches.

## Which repos for which kind of work
| If the work item is about... | Usually involves |

## Glossary
| Term | Meaning | Where it shows up in code |

## Local environment notes
- All tests run without a database. Never point anything at a shared or production environment.
```

## 3. Repo guides

Run `/onboard-repo <folder>` for each repo, shared repos first. Then open each generated `AGENTS.md`, fix every `(inferred, verify)` item, and fill or delete every `TODO(you)`. Point the UI repo guide at existing Playwright mock helpers. The shape comes from `core/templates/repo-agents.md`.

## Work PC checklist

- [ ] Clone your copy (with `personal/`) to `C:\tools\eng-agents`
- [ ] Confirm the opencode config folder path
- [ ] Create the overlay folder and write its `AGENTS.md`
- [ ] Create a PAT and set `ADO_PAT`
- [ ] Create and fill in `config.json`
- [ ] Run `install.ps1 -DryRun`, then `install.ps1`
- [ ] Test `Get-WorkItem.ps1` against a real work item
- [ ] Clone all repos flat into `C:\src\work`
- [ ] Write the repo map
- [ ] `/onboard-repo` each repo, shared repos first, and review each guide
- [ ] Day-one verification checks 1 to 7
- [ ] Smoke test: one small bug through the bug lane

## Never

- Commit any of the above to the base repo or your copy.
- Put the PAT in a file.
