# Company onboarding

Set up the Company layer on the work PC, install, and verify. Everything you create here stays on the work PC and is **never committed** to eng-agents or your fork. Run commands in a normal PowerShell window (not "Run as administrator"). Paths are examples; change them if you like, but keep them consistent.

Finish [Personal onboarding](onboarding-personal.md) first.

| File | What it does |
|---|---|
| `ADO_PAT` (user environment variable) | Lets `/start` fetch work items |
| `%USERPROFILE%\.config\eng-agents\config.json` | Which ADO server to call |
| `%USERPROFILE%\.config\eng-agents\overlay\AGENTS.md` | Rules for every repo at work |
| `C:\src\work\AGENTS.md` | Repo map: what each repo is and how they connect. **Most important file.** |
| `C:\src\work\<repo>\AGENTS.md` | Build, test, and architecture guide per repo |

What to check in each file, and what else you can add: [customization guide](customization.md#files-to-review).

## 1. Clone your fork

Clone **your fork** (with `personal/`), not the base repo, outside the workspace:

```powershell
mkdir C:\tools -Force
git clone <your fork url> C:\tools\eng-agents
```

If GitHub is blocked at work, download your fork as a zip at home and copy it over. Never send company content the other way.

## 2. Find your opencode config folder

```powershell
Test-Path "$env:USERPROFILE\.config\opencode"
Test-Path "$env:APPDATA\opencode"
```

Use whichever exists or holds your current `opencode.json`. If it is not `%USERPROFILE%\.config\opencode`, pass `-Target <path>` to `install.ps1` every time. Install keeps your provider and model settings, merges only the `permission` block, and backs the file up first.

## 3. Connect to ADO

Create a PAT in ADO (profile, Security, Personal access tokens) with **Work Items: Read** and **Code: Read**. Then:

```powershell
[Environment]::SetEnvironmentVariable("ADO_PAT", "<token>", "User")
mkdir "$env:USERPROFILE\.config\eng-agents\overlay" -Force
Copy-Item C:\tools\eng-agents\core\scripts\ado\config.example.json "$env:USERPROFILE\.config\eng-agents\config.json"
notepad "$env:USERPROFILE\.config\eng-agents\config.json"
```

Close and reopen PowerShell so the variable is visible.

| Key | Value |
|---|---|
| `serverUrl` | Up to, not including, the collection (often ends in `/tfs`) |
| `collection` | Often `DefaultCollection`. Check the URL you use in the browser. |
| `project` | Project name. Used only when fetching comments. |
| `apiVersion` | Start with `6.0`. Use `5.1` if requests fail with a version error. |
| `auth` | `pat` (uses `ADO_PAT`), or `windows` to use your Windows login instead |

Without ADO access, `/start` still works in offline mode: you paste the title and details.

## 4. Write company-wide rules

`%USERPROFILE%\.config\eng-agents\overlay\AGENTS.md`. Only rules true in **every** repo. Repo-specific rules go in step 8.

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
- Do your base branch, PR target, or commit format differ from Core (`main`, short summary)?
- Does the team expect PR sections? Put them in `overlay\templates\pr.md` (see [Customizing templates](customization.md#customizing-templates)).

## 5. Install

```powershell
cd C:\tools\eng-agents
.\install.ps1 -DryRun
.\install.ps1
```

- `Layers :` shows Core, Personal, Company.
- Both ADO checks at the end say `[ok]`.
- If PowerShell blocks the script: `powershell -ExecutionPolicy Bypass -File .\install.ps1`.
- Never start opencode from an elevated window. After the first launch, ask it to run `whoami`: it must print your normal username.

## 6. Test the ADO script

```powershell
mkdir C:\src\work -Force
cd C:\src\work
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.config\opencode\eng-agents\scripts\ado\Get-WorkItem.ps1" -Id <id> -WorkRoot .work
```

Adjust the path if you used `-Target`. It should print a folder path and create `workitem.md`. Check the description is readable, then delete the test folder.

## 7. Build the workspace and repo map

`C:\src\work` is not a git repo; always launch opencode from it. Clone every repo **directly** into it, side by side, with no per-project subfolders. Clone shared repos once. Folder names must match the relative paths other repos use. Then write the repo map:

```powershell
cd C:\src\work
git clone <each repo url>
Copy-Item C:\tools\eng-agents\company\repo-map.template.md C:\src\work\AGENTS.md
notepad C:\src\work\AGENTS.md
```

Replace every `TODO(you)` and `(example)` row. Questions to answer:

- What does each repo do, in one line?
- Which repos reference the shared repo, and what is one exact relative path for each?
- Which products exist, and which repos does each one span?
- Which repos usually change together, and in what order?
- Which work item words map to different names in code?
- Is there anything an agent must never touch (generated code, shared environments)?

A wrong map produces wrong plans. Keep it short and accurate.

### Product docs

Agents read anything inside `C:\src\work` without a prompt, so keep product docs there, in markdown, and point to them from the repo map. Split docs by what they describe:

- **Product docs** (user guides, overviews, release notes) span several repos, so keep them in one docs repo with a folder per product. If your team has an ADO Wiki, clone it and use that.
- **Repo docs** (architecture, build, internals) go in that repo's `docs/` folder.
- **Shared repos** document only themselves: what they provide and which products use them. Never a product's user guide.

```
C:\src\work\
  AGENTS.md              repo map: each product block links to its docs folder
  product-docs\          docs repo or ADO Wiki clone
    AGENTS.md            short guide for agents (run /onboard-repo product-docs)
    <product-a>\
      overview.md        what it does, which repos it spans
      user-guide.md
      release-notes.md
    <product-b>\
  <shared-repo>\docs\    what it provides, which products use it
  <product-repo>\docs\   architecture and internals for that repo
```

If docs cannot be checked in anywhere yet, use a local `C:\src\work\_docs\` folder with the same per-product layout (no `AGENTS.md` needed, since it is not a repo). Moving it to a docs repo later is a straight copy.

## 8. Onboard each repo

```
cd C:\src\work
opencode
/onboard-repo <shared-repo>
/new
/onboard-repo <next-repo>
```

Shared repos first, a new session between repos. Review each generated `<repo>\AGENTS.md`:

- [ ] Build and test commands work when you run them yourself
- [ ] Architecture reference rules match reality
- [ ] "Pattern to follow" files are good examples, not legacy code
- [ ] UI repos point at existing Playwright mock helpers
- [ ] Every `(inferred, verify)` fixed, every `TODO(you)` filled or deleted
- [ ] `AGENTS.md` is listed in the repo's `.git\info\exclude`

## 9. Day-one checks

Run these in a scratch opencode session. Each confirms an assumption the setup depends on.

| # | Check | How | If it fails |
|---|---|---|---|
| 1 | Agents and commands loaded | Type `/`: you see `start`, `spec`, `do-task`, and the rest. Press Tab: you see `planner`, `implementer`, and the others. | Wrong config folder. Reinstall with `-Target`. |
| 2 | Shell is PowerShell | Ask: "Run `$PSVersionTable.PSVersion` and show the output." | Tell the agents which shell in your overlay `AGENTS.md`. |
| 3 | Planner can write to `.work` | As `planner`, ask: "Create `.work/_test/hello.md` with the word hi." No prompt. | The edit path pattern did not match on Windows. Change `edit` to `ask` in the planner, reviewer, investigator, and writer agents, reinstall, and report it. |
| 4 | Planner cannot edit code | Ask `planner` to add a comment to any `.cs` file. Denied. | Same as check 3. |
| 5 | Templates are readable | Ask `planner`: "Read the spec template in the eng-agents templates folder and show its first line." No external directory prompt. | Approve once with "always", or add the path to `external_directory` in your overlay `opencode.json`. |
| 6 | Push is blocked | As `implementer`, ask it to run `git -C <repo> push`. Denied. | Check the `permission` block in the installed `opencode.json`. |
| 7 | Repo `AGENTS.md` is read when needed | Ask `planner` for a repo's test command without naming the file. | It may not know until it reads the file. Commands always read it, so this is fine. |

Then delete the test folder yourself (agents cannot delete recursively): `Remove-Item C:\src\work\.work\_test -Recurse`. Keep `.work`.

## 10. Smoke test

Take one small, low-risk bug through the bug lane:

```
/start <id> bug
/bug <id>
(approve bug.md)
/new
/do-task <id> 1
/new
/do-task <id> 2
/review <id>
/pr <id>
```

Write down every place the model stumbled. Generic problems are Core fixes; company-specific ones go in your overlay or a repo guide.

## Keeping it current

| Change | Then |
|---|---|
| Model makes a company-specific mistake | Add a rule to that repo's `AGENTS.md` (one repo) or `overlay\AGENTS.md` (every repo) |
| Edited the overlay | Run `.\install.ps1` again |
| Edited the repo map or a repo `AGENTS.md` | Start a new opencode session |
| Base repo changed | At home: `git fetch upstream`, `git merge upstream/main`, `git push`. At work: `git pull`, then `.\install.ps1` |

Updates never touch your overlay, config, workspace, or repo `AGENTS.md` files. Never put the PAT in a file, and never commit any of this.

## Mac or Linux

Never run `install.ps1` or `opencode` with `sudo`. If opencode reports permission errors, make sure its background service is not running as root:

```bash
ps -o user,command -A | grep -i '[o]pencode'   # serve --service must not show root
sudo opencode service stop && opencode service start
sudo chown -R $(whoami) ~/.config ~/.local ~/.cache
```
