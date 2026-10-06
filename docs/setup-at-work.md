# Setup at work

Step-by-step first-day setup on the work PC. Run everything in PowerShell. For what to write in each file, see [onboarding-company.md](onboarding-company.md).

Paths below are examples. Change them if you prefer other locations, but keep them consistent.

---

## 1. Get the repo onto the work PC

Clone **your own fork** (with your `personal\` folder), not the base repo:

```powershell
mkdir C:\tools -Force
git clone <your fork's url> C:\tools\eng-agents
```

If cloning from GitHub is blocked at work, download your fork as a zip at home and copy it over. Do not send company content back the other way.

## 2. Find your opencode config folder

opencode's docs do not state the Windows path. Check both:

```powershell
Test-Path "$env:USERPROFILE\.config\opencode"
Test-Path "$env:APPDATA\opencode"
```

Use whichever exists (or contains your current `opencode.json`). If it is not `%USERPROFILE%\.config\opencode`, pass `-Target <path>` to `install.ps1` every time.

**Important:** your work `opencode.json` likely holds the provider and model settings for the company AI. `install.ps1` keeps those and only merges the `permission` block. It backs the file up first.

## 3. Create the company overlay

```powershell
mkdir "$env:USERPROFILE\.config\eng-agents\overlay" -Force
notepad "$env:USERPROFILE\.config\eng-agents\overlay\AGENTS.md"
```

Write the company-wide rules. [onboarding-company.md](onboarding-company.md#2-write-company-wide-rules) lists what belongs there.

## 4. Set up ADO access

**Create a PAT** in ADO Server: your profile, then Security, then Personal access tokens. Scopes:
- Work Items: **Read**
- Code: **Read**

**Store it as a user environment variable** (not in any file):

```powershell
[Environment]::SetEnvironmentVariable("ADO_PAT", "<paste token>", "User")
```

Close and reopen PowerShell so the variable is visible.

**Create the config file:**

```powershell
Copy-Item C:\tools\eng-agents\core\scripts\ado\config.example.json "$env:USERPROFILE\.config\eng-agents\config.json"
notepad "$env:USERPROFILE\.config\eng-agents\config.json"
```

| Key | What to put |
|---|---|
| `serverUrl` | The ADO Server base URL, up to but not including the collection. Often ends in `/tfs`. |
| `collection` | The collection name, for example `DefaultCollection`. |
| `project` | The project name. Used only for comments. |
| `apiVersion` | Start with `6.0`. If requests fail with a version error, try `5.1`. |
| `auth` | `pat` (uses `ADO_PAT`), or `windows` to use your Windows login instead of a PAT. |

## 5. Install

Run PowerShell as your normal user, not "Run as administrator", and never start opencode from an elevated window. After the first launch, ask opencode to run `whoami`: it must print your normal Windows username. Files created by an elevated session can end up unusable by opencode running as you.


```powershell
cd C:\tools\eng-agents
.\install.ps1 -DryRun
.\install.ps1
```

If PowerShell blocks the script, run it once with `powershell -ExecutionPolicy Bypass -File .\install.ps1`.

Read the "Checks" at the end. Both should say `[ok]` before you rely on `/start` fetching from ADO.

## 6. Test the ADO script

Pick any work item you can see:

```powershell
mkdir C:\src\work -Force
cd C:\src\work
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.config\opencode\eng-agents\scripts\ado\Get-WorkItem.ps1" -Id <id> -WorkRoot .work
```

It should print a folder path and create `workitem.md`. Open it and check the description came through readable. Delete the test folder afterward.

## 7. Build the workspace

```powershell
cd C:\src\work
git clone <shared repo url>
git clone <each other repo url>
notepad C:\src\work\AGENTS.md
```

- Clone every repo **directly** into `C:\src\work`, side by side. Shared repos are referenced by relative paths, so folder names must match what the other repos expect.
- Write the repo map using the skeleton in [onboarding-company.md](onboarding-company.md#4-build-the-workspace-and-repo-map). This is the most important file you write.

## 8. Onboard each repo

```powershell
cd C:\src\work
opencode
```

Then, shared repos first:

```
/onboard-repo <shared-repo-folder>
/onboard-repo <next-repo-folder>
```

After each one, open the generated `<repo>\AGENTS.md`, fix every `(inferred, verify)` item, fill or delete every `TODO(you)`. Start a new session (`/new`) between repos.

## 9. Day-one verification

Do these in a scratch session. Each one confirms an assumption the scaffolding depends on.

| # | Check | How | If it fails |
|---|---|---|---|
| 1 | Agents and commands loaded | Type `/` in opencode. You should see `start`, `spec`, `do-task`, and the rest. Press Tab to cycle agents; you should see `planner`, `implementer`, and the others. | Wrong config folder. Re-run install with `-Target`. |
| 2 | Shell is PowerShell | Ask: "Run `$PSVersionTable.PSVersion` and show the output." | Commands still work, but tell the agents which shell in your overlay `AGENTS.md`. |
| 3 | Planner can write to `.work` | Switch to `planner`. Ask: "Create `.work/_test/hello.md` with the word hi." It should succeed without a prompt. | The edit path pattern did not match on Windows. In `core\agents\planner.md` (and reviewer, investigator, writer), change `edit` to `ask` and reinstall. |
| 4 | Planner cannot edit code | Ask planner to add a comment to any `.cs` file. It should be denied. | Same as above. Report it so the pattern can be fixed. |
| 5 | Templates are readable | Ask planner: "Read the spec template in the eng-agents templates folder and show its first line." It should not prompt about an external directory. | Approve the prompt once with "always", or add the exact path to `external_directory` in your overlay `opencode.json`. |
| 6 | Push is blocked | Switch to `implementer`. Ask it to run `git -C <repo> push`. It should be denied. | Check the installed `opencode.json` permission block. |
| 7 | Repo AGENTS.md is read when needed | Run `/status`. Then ask planner what a repo's test command is without naming the file. | Expected: it may not know until it reads the file. Commands always tell it to read the file, so this is fine. |

When done, delete only the test folder yourself in a normal PowerShell window (agents are blocked from recursive deletes on purpose): `Remove-Item C:\src\work\.work\_test -Recurse`. Keep `.work` itself.

## 10. Smoke test

Pick a small, low-risk bug and run the bug lane end to end:

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

Write down every place the model stumbled. Those become fixes in Core (generic problems) or your overlay (company-specific problems).

## Updating later

`git pull` here only gets your fork. To pick up base repo changes, merge them into your fork first (at home: `git fetch upstream`, `git merge upstream/main`, `git push`). Then:

```powershell
cd C:\tools\eng-agents
git pull
.\install.ps1
```

Your overlay, config, workspace, and repo `AGENTS.md` files are never touched by an update.

## Mac or Linux

Never run `install.ps1` or `opencode` with `sudo` (install refuses to run as root). If opencode reports permission errors, check that its background service is not running as root:

```bash
ps -o user,command -A | grep -i '[o]pencode'   # serve --service must not show root
sudo opencode service stop && opencode service start
sudo chown -R $(whoami) ~/.config ~/.local ~/.cache
```
