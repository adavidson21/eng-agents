# Company onboarding

Set up the Company layer on the work PC. Everything here is created on the work PC and **never committed** to eng-agents or your fork. Do the steps in order. Full commands and the day-one checks are in [setup-at-work.md](setup-at-work.md).

What each file is for and when it is loaded: [customization guide](customization.md#company-layer).

First, finish [Personal onboarding](onboarding-personal.md), then clone your fork (with `personal/`) to `C:\tools\eng-agents` on the work PC.

## Files

| File | What it does |
|---|---|
| `ADO_PAT` (environment variable) | Lets `/start` pull work items |
| `%USERPROFILE%\.config\eng-agents\config.json` | Which ADO server to call |
| `%USERPROFILE%\.config\eng-agents\overlay\AGENTS.md` | Rules for every repo at work |
| `C:\src\work\AGENTS.md` | Repo map: what each repo is and how they connect. **Most important file.** |
| `C:\src\work\<repo>\AGENTS.md` | Build, test, and architecture guide per repo |

## 1. Connect to ADO

Create a PAT in ADO (profile, Security, Personal access tokens) with **Work Items: Read** and **Code: Read**. Then:

```powershell
[Environment]::SetEnvironmentVariable("ADO_PAT", "<token>", "User")
mkdir "$env:USERPROFILE\.config\eng-agents\overlay" -Force
Copy-Item C:\tools\eng-agents\core\scripts\ado\config.example.json "$env:USERPROFILE\.config\eng-agents\config.json"
notepad "$env:USERPROFILE\.config\eng-agents\config.json"
```

| Key | Value |
|---|---|
| `serverUrl` | Up to, not including, the collection (often ends in `/tfs`) |
| `collection` | Often `DefaultCollection`. Check the URL you use in the browser. |
| `apiVersion` | Start with `6.0`. Fall back to `5.1` if it errors. |
| `auth` | `pat`, or `windows` to use your Windows login and skip the PAT |

Reopen PowerShell after setting the variable.

## 2. Write company-wide rules

`%USERPROFILE%\.config\eng-agents\overlay\AGENTS.md`. Only rules that are true in **every** repo. Repo-specific rules go in step 5.

```markdown
## Company-wide engineering rules
- Never log personal, health, or financial data. Log IDs, not values.
- Every new API endpoint needs an authorization attribute.
  Copy the style from other endpoints in the same controller.
- Config values come from the existing options classes.
  Never hard-code URLs, keys, or environment names.

## Team conventions that differ from Core
- Base branch and PR target: <branch>
```

Questions to answer:

- What data must never be logged or put in test fixtures?
- Is there a standards doc the agent should read first? Point to it.
- Does your base branch, PR target, or commit format differ from Core (`main`, short summary)?
- Does the team expect PR sections? Put them in `overlay\templates\pr.md`.

## 3. Install

Use a normal PowerShell window, not "Run as administrator".

```powershell
cd C:\tools\eng-agents
.\install.ps1 -DryRun
.\install.ps1
```

- `Layers :` shows Core, Personal, Company
- Both ADO checks say `[ok]`
- If your opencode config is not in `%USERPROFILE%\.config\opencode`, add `-Target <path>`
- After the first opencode launch, ask it to run `whoami`. It must print your normal username.

## 4. Build the workspace and repo map

Clone every repo directly into `C:\src\work`, side by side. Clone shared repos once. Then write `C:\src\work\AGENTS.md`:

```markdown
# Workspace repo map

## Repos
| Folder | What it is | Stack | Shared? |
|---|---|---|---|
| shared-lib | (example) Libraries used by several products | .NET, TypeScript | Yes |

## How the repos depend on each other
All cross-repo references are relative paths, so every repo stays cloned directly in this folder.
| Repo | Depends on | How | Example reference |
|---|---|---|---|
| orders-api | shared-lib | ProjectReference | (example) ..\..\shared-lib\src\Lib\Lib.csproj |

Rule: change a shared repo first, then run the tests of every dependent repo the work item touches.

## Which repos for which kind of work
| If the work item is about... | Usually involves |
|---|---|

## Glossary
| Term | Meaning | Where it shows up in code |
|---|---|---|

## Local environment notes
- All tests run without a database. Never point anything at a shared or production environment.
```

Replace the example rows. Questions to answer:

- What does each repo do, in one line?
- Which repos reference the shared repo, and what is one exact relative path for each?
- Which repos usually change together for a typical work item?
- Which domain words show up in work items, and what are they called in code?
- Is there anything an agent must never touch (generated code, shared environments)?

A wrong map produces wrong plans. Keep it short and accurate.

## 5. Onboard each repo

```
cd C:\src\work
opencode
/onboard-repo <shared-repo>
/new
/onboard-repo <next-repo>
```

Shared repos first, a new session between repos. Review each generated `<repo>\AGENTS.md`:

- [ ] Build and test commands work when you run them yourself
- [ ] Clean Architecture reference rules match reality
- [ ] "Pattern to follow" files are good examples, not legacy code
- [ ] UI repos point at existing Playwright mock helpers
- [ ] Every `(inferred, verify)` fixed, every `TODO(you)` filled or deleted
- [ ] `AGENTS.md` appears in the repo's `.git\info\exclude`

## 6. Verify and smoke test

- Run the 7 day-one checks in [setup-at-work.md](setup-at-work.md#9-day-one-verification).
- Take one small, low-risk bug through `/start`, `/bug`, `/do-task`, `/review`, `/pr`.

## Keeping it current

- The model makes a company-specific mistake: add a rule to that repo's guide (one repo) or the overlay (every repo).
- Overlay changes need `.\install.ps1` again. The repo map and repo guides only need a new opencode session.
- Never put the PAT in a file, and never commit any of this.
