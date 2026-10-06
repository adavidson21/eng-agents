# Practice run

A dry run of the whole pipeline on made-up repos, so problems show up at home instead of on your first day at work. Anyone on the team can use it.

The practice workspace mirrors a real setup:

| Repo | What it has |
|---|---|
| `shared-lib` | .NET library with a `Money` type. Other repos reference it by **relative path**. |
| `orders-api` | .NET API with Clean Architecture, xUnit and NSubstitute tests, no database. Has a **planted bug** (work item 101). |
| `orders-ui` | Angular 19 app with Karma unit tests and Playwright tests that mock the API with `page.route`. |

Work items to practice with are in `work-items/`. Expected results are in `answer-keys/`.

---

## Two tiers

| Tier | Needs | Covers |
|---|---|---|
| **Tier 1** | opencode, git, PowerShell 7 | Install, permissions, every planning and investigation command: `/onboard-repo`, `/start`, `/bug`, `/spec`, `/plan`, `/tasks`, `/spike`, `/status`, `/standup` |
| **Tier 2** | Tier 1 plus .NET 10 SDK and Node | The commands that run code: `/do-task`, `/review`, `/pr`, `/docs`, `/check-docs` |

Tier 1 already tests most of what can go wrong. Do Tier 2 if you can install the SDKs.

---

## Step 1: Prerequisites (Mac)

**PowerShell 7** (runs `install.ps1` and the work item script): Homebrew no longer offers it, so install Microsoft's package. Download the `.pkg` from the [PowerShell releases page](https://aka.ms/powershell-release?tag=stable) (`osx-arm64` for Apple Silicon, `osx-x64` for Intel) and double-click it.

```bash
# Tier 2 only
brew install --cask dotnet-sdk
brew install node
```

Check:

```bash
pwsh --version
opencode --version
dotnet --version   # Tier 2: must be 10.x
node --version     # Tier 2
```

**Model:** any model works for testing the mechanics. For the most realistic test, pick a Qwen model in opencode (`/models`) if one is available, since that is closest to what you use at work.

## Step 2: Install eng-agents from your copy

From your copy of the repo (the one with your `personal/` folder):

```bash
git pull
pwsh ./install.ps1 -Company ./practice/overlay -DryRun
pwsh ./install.ps1 -Company ./practice/overlay
```

`-Company ./practice/overlay` installs a small practice Company layer, so all three layers get tested. Expect `AGENTS.md: 3 sections`. The two `[todo]` lines about ADO are expected at home; `/start` will use offline mode.

## Step 3: Create the practice workspace

```bash
pwsh ./practice/New-PracticeWorkspace.ps1
cp ./practice/findings-template.md ~/eng-practice/FINDINGS.md
cd ~/eng-practice
opencode
```

Keep `FINDINGS.md` open and fill it in as you go.

## Step 4: Verification checks

In opencode, in the practice workspace:

| # | Check | How | Expected |
|---|---|---|---|
| 1 | Commands loaded | Type `/` | `start`, `spec`, `plan`, `tasks`, `do-task`, `review`, `pr`, `bug`, `spike`, `docs`, `check-docs`, `onboard-repo`, `status`, `standup` |
| 2 | Agents loaded | Press Tab to cycle agents | `planner`, `implementer`, `reviewer`, `investigator`, `writer` |
| 3 | Planner writes `.work` | Switch to planner. Ask: "Create `.work/_test/hello.md` with the word hi." | Succeeds, no prompt |
| 4 | Planner cannot edit code | Ask planner to add a comment to `orders-api/src/Orders.Domain/Order.cs` | Denied |
| 5 | Templates readable | Ask planner: "Read the spec template in the eng-agents templates folder and show its first line." | No external-directory prompt |
| 6 | Push blocked | Switch to implementer. Ask it to run `git -C orders-api push` | Denied |
| 7 | Layers merged | Ask: "What does the Company section of your instructions say about logging?" | Mentions not logging personal or payment data |

Delete `.work/_test` afterwards. Start a new session (`/new`) before Step 5.

## Step 5: Tier 1 runs

Do these in order. Start a new session (`/new`) between numbered items.

**You do not need to pick an agent.** Each command switches to its own agent automatically. Check the agent name opencode shows while it runs. If it does not match the table, note it in `FINDINGS.md`.

| Command | Runs as |
|---|---|
| `/onboard-repo`, `/bug`, `/spike` | investigator |
| `/start`, `/spec`, `/plan`, `/tasks`, `/status`, `/standup` | planner |
| `/do-task` | implementer |
| `/review`, `/check-docs` | reviewer |
| `/pr`, `/docs` | writer | After each one, compare with the answer key and note results in `FINDINGS.md`.

1. **Onboard the repos**, shared repo first. When asked to run build or test commands, say **no** for Tier 1.
   ```
   /onboard-repo shared-lib
   /onboard-repo orders-api
   /onboard-repo orders-ui
   ```
   Compare each generated `<repo>/AGENTS.md` with `answer-keys/<repo>-AGENTS.md`. If one is poor, note why, then copy the answer key over it so later steps have good input.

2. **Bug lane, planning half.**
   ```
   /start 101 bug
   ```
   The ADO fetch fails (expected). Paste the title from `work-items/101.md`, then paste the rest of that file into the new `workitem.md` and reply "done". Choose `orders-api` as the only repo.
   ```
   /bug 101
   ```
   Compare with `answer-keys/101-bug.md`. If the root cause is right, set `Status: APPROVED` in `bug.md`.

3. **Feature lane, planning half.**
   ```
   /start 102 feature
   /spec 102
   ```
   Paste from `work-items/102.md`. Expected repos: `shared-lib`, `orders-api`, `orders-ui`, with `shared-lib` first. Answer the spec questions. Approve `spec.md`, then:
   ```
   /plan 102
   ```
   Approve `plan.md`, then:
   ```
   /tasks 102
   ```
   Compare with `answer-keys/102-feature.md`.

4. **Spike.**
   ```
   /spike 103 can one order contain items priced in different currencies
   ```
   Compare with `answer-keys/103-spike.md`.

5. **Status and standup.**
   ```
   /status
   /status 102
   /standup
   ```

## Step 6: Tier 2 runs (needs .NET and Node)

First time only, in a normal terminal:

```bash
cd ~/eng-practice
dotnet test orders-api/tests/Orders.Application.Tests/Orders.Application.Tests.csproj
npm --prefix orders-ui ci
npx --prefix orders-ui playwright install chromium
```

The .NET tests should pass (3 tests). That proves the planted bug has no test yet.

Then in opencode, one new session per task:

1. **Fix the bug.**
   ```
   /do-task 101 1
   ```
   The new test must **fail** first, with discount 8.80 instead of 8.00. Check that `progress.md` shows the failing output.
   ```
   /new
   /do-task 101 2
   /new
   /review 101
   /pr 101
   ```

2. **Build the feature** (optional, longer): `/do-task 102 1`, then each task in a new session, then `/review 102`.

3. **Docs.**
   ```
   /docs orders-api/docs/api.md: document GET /api/orders/{id}/summary for front-end developers
   /new
   /check-docs orders-api/docs/api.md
   ```

## Step 7: Report back

Paste `FINDINGS.md` back to Claude. Generic problems get fixed in the base repo; you pull them into your copy.

## Starting over

```bash
rm -rf ~/eng-practice ~/eng-practice-remotes
pwsh ./practice/New-PracticeWorkspace.ps1
```

## What this run cannot test

These only show up at work, so they stay on the work-day checklist:

- Windows paths with backslashes in permission patterns
- PowerShell as opencode's shell, and Windows PowerShell 5.1 running the scripts
- Your real ADO Server and PAT
- Your company's model and its speed
