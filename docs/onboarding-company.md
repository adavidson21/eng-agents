# Company onboarding

Set up the Company layer on the work PC, install, and verify. Everything you create here stays on the work PC and is **never committed** to eng-agents or your fork. Run commands in a normal PowerShell window (not "Run as administrator"). Paths are examples; change them if you like, but keep them consistent.

Finish [Personal onboarding](onboarding-personal.md) first.

| File | What it does |
|---|---|
| `ADO_PAT` (user environment variable) | Lets `/start` fetch work items |
| `%USERPROFILE%\.config\eng-agents\config.json` | Which ADO servers and collections to call |
| `%USERPROFILE%\.config\eng-agents\overlay\AGENTS.md` | Rules for every repo at work |
| `C:\src\work\AGENTS.md` | Repo map: what each repo is and how they connect. **Most important file.** |
| `C:\src\work\<repo>\AGENTS.md` (or `AGENTS.local.md`) | Repo guide: build, test, and architecture per repo |
| `%USERPROFILE%\.config\eng-agents\memory.md` | Global memory, written by `/memory -global`. Loaded in every session. |

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

Add one entry under `connections` for each project collection (or server) you get work items from. The names (`main`, `second`) are yours to pick.

```json
{
  "apiVersion": "6.0",
  "auth": "pat",
  "default": "main",
  "connections": {
    "main":   { "serverUrl": "https://ado.example.local/tfs", "collection": "DefaultCollection", "project": "ExampleProject" },
    "second": { "serverUrl": "https://ado.example.local/tfs", "collection": "SecondCollection", "project": "OtherProject", "patEnv": "ADO_PAT_SECOND" }
  },
  "paths": {
    "C:/src/work/legacy-*": "second"
  }
}
```

| Key | Value |
|---|---|
| `serverUrl` | Up to, not including, the collection (often ends in `/tfs`) |
| `collection` | The project collection. Check the URL you use in the browser. |
| `project` | Project name. Used only when fetching comments. |
| `apiVersion` | Start with `6.0`. Use `5.1` if requests fail with a version error. Can be set per connection. |
| `auth` | `pat`, or `windows` to use your Windows login instead. Can be set per connection. |
| `patEnv` | Environment variable holding the PAT. Default `ADO_PAT`. Set it per connection if one PAT does not work for every collection. |
| `default` | Connection to use when nothing else decides. Optional. |
| `paths` | Folder pattern to connection. `*` matches anything, including `\`. The longest matching pattern wins. Optional. |

`/start` picks the connection in this order:

1. The third argument, if it is a connection name: `/start 123 bug second`
2. The third argument, if it is a repo folder: `/start 123 bug orders-api`. A `paths` pattern matching the repo's folder wins; otherwise the collection in the repo's `origin` URL decides, so most repos need no mapping at all.
3. A `paths` pattern matching the folder opencode was started from (useful if you keep one workspace per collection)
4. `default`
5. The only connection, if there is one

If none of these decide, the planner asks you which connection. Check a mapping without fetching anything:

```powershell
cd C:\src\work
powershell -NoProfile -File "$env:USERPROFILE\.config\opencode\eng-agents\scripts\ado\Get-WorkItem.ps1" -Id 0 -From orders-api -ShowConnection
```

It prints the connection, why it was chosen, the URL, and whether its PAT variable is set. A config with `serverUrl` and `collection` at the top level (the old format) still works as a single connection.

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

Shared repos first, a new session between repos.

**Committed agent guides.** `/onboard-repo` looks for guides the team already committed (`CLAUDE.md` at any depth, `.claude/*.md`, a committed `AGENTS.md`, `.github/copilot-instructions.md`, Cursor rules) and asks how to use each one:

| Mode | What happens | Pick it when |
|---|---|---|
| **link** (recommended) | The repo guide lists the file. Agents read it every time they work in its folder, so it never goes stale. The repo guide adds only what it is missing. | The team keeps it current |
| **copy** | Its rules are copied into the repo guide, with the commit it was copied at. Agents warn you when the file changes; re-run `/onboard-repo` to refresh. | You want to edit or trim the rules |
| **ignore** | Not read | It is wrong or for another stack |

opencode does not load a repo's `CLAUDE.md` on its own here, because you start it from the workspace root, so linking is what makes agents see it. If the team committed its own `AGENTS.md`, `/onboard-repo` leaves it alone, links it, and writes your guide to `AGENTS.local.md` instead. Agents read `AGENTS.local.md` first.

Review each generated repo guide:

- [ ] Build and test commands work when you run them yourself
- [ ] Architecture reference rules match reality
- [ ] "Pattern to follow" files are good examples, not legacy code
- [ ] UI repos point at existing Playwright mock helpers
- [ ] Every `(inferred, verify)` fixed, every `TODO(you)` filled or deleted
- [ ] Every team guide disagreement under "Gotchas" is resolved
- [ ] The guide file (`AGENTS.md` or `AGENTS.local.md`) is listed in the repo's `.git\info\exclude`

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
| 8 | Global memory works | `/memory -global Test rule, delete me`, then `/new` and ask: "What rules are in your global memory?" Delete the line from `memory.md` afterwards. | Check `instructions` in the installed `opencode.json` lists `memory.md`. |
| 9 | Repo memory works | `/memory <repo> Test rule, delete me`. The line appears under `## Remembered` in the repo guide with no prompt. Delete it. | The writer could not edit the file. Approve once and report it. |
| 10 | Each ADO connection resolves | Run the `-ShowConnection` command from step 3 once per connection (`-From <name>`) and once for a repo in each collection. | Fix `paths` or the connection's `serverUrl` and `collection`. |
| 11 | Normal work does not prompt | Run one real item through `/start` to `/review`. Note every approval you give. | Add each safe command to `overlay\permissions\read.json` or `build.json` ([Permissions](customization.md#permissions)) and reinstall. |

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
| Model makes a company-specific mistake | `/memory <rule>` in the session where it happened, or edit that repo's guide (one repo) or `overlay\AGENTS.md` (every repo) by hand |
| Agents keep asking about a safe command | Add it to `overlay\permissions\read.json` or `build.json`, then `.\install.ps1` |
| Edited the overlay | Run `.\install.ps1` again |
| Edited the repo map or a repo `AGENTS.md` | Start a new opencode session |
| Base repo changed | At home: `git fetch upstream`, `git merge upstream/main`, `git push`. At work: `git pull`, then `.\install.ps1` |

Updates never touch your overlay, config, memory, workspace, or repo guides. Never put the PAT in a file, and never commit any of this.

## Mac or Linux

Never run `install.ps1` or `opencode` with `sudo`. If opencode reports permission errors, make sure its background service is not running as root:

```bash
ps -o user,command -A | grep -i '[o]pencode'   # serve --service must not show root
sudo opencode service stop && opencode service start
sudo chown -R $(whoami) ~/.config ~/.local ~/.cache
```
