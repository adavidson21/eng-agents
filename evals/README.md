# Evals

Behavior tests for Tandem's commands. A prompt change can make agents quietly worse; these runs show it before a release.

Each case builds a made-up workspace (a repo map and `sample-api`, a small .NET order pricing library), runs one command with a real model through `opencode run`, and grades what the agent left behind with plain file and git checks. Nothing touches your real workspace, ADO or company code, so results can be committed.

## Run

1. Install this checkout so opencode uses the commands you are testing: `./install.ps1`
2. Run every case 3 times with your default model:

   ```
   ./evals/Invoke-Evals.ps1
   ```

   Pick cases, runs and a model:

   ```
   ./evals/Invoke-Evals.ps1 -Case spec-basic,review-planted -Runs 5 -Model <provider/model>
   ```

3. Read the summary table. It compares each case with the newest file in `evals/results/`. A drop means read that case's failed checks and log before releasing.
4. Commit the results file you want later runs compared against (your baseline).

Cases marked `needs: dotnet` are skipped without the .NET 8 SDK.

Debug one case by hand: `./evals/Invoke-Evals.ps1 -Case do-task -SetupOnly` builds the workspace and prints the opencode line to run there. `-KeepWorkspaces` keeps every run's folder.

## Permissions

Runs are unattended. A command that hits an `ask` rule waits for an answer nobody gives and times out (`-TimeoutMinutes`, default 20), which shows up as a failed run. `-AutoApprove` passes `--auto` to opencode so anything not denied is approved. The workspace is a throwaway temp folder with no git remote, but read the guards before you use it.

## Cases

| Case | Command | Passes when |
|---|---|---|
| `spec-basic` | `/spec L1 auto` | spec is DRAFT with a matching draft hash, 2+ Given/When/Then ACs covering the threshold and smaller orders, cited paths exist, no questions, no code changed |
| `plan-paths` | `/plan L1 auto` | the pattern file and every changed file exist, the test plan covers every AC, settings go in `PricingOptions` |
| `tasks-shape` | `/tasks L1 auto` | each task: one repo, 3 files or fewer, a Human interface line, a verify command from the repo guide; coverage complete; Stats counts the tasks |
| `do-task` | `/do-task L1 1 auto` | one commit with only the task's files, `LegacyRound` (Do not touch) kept, settings in `PricingOptions`, Red and Green runs logged, all tests pass including hidden acceptance tests |
| `review-planted` | `/review L1 auto` | finds a planted off-by-one (exactly 10 items get no discount) that the branch's own tests miss |
| `review-clean` | `/review L1 auto` | a correct branch gets READY with no invented Blockers |
| `bug-lane` | `/bug L2 auto` | root cause in `OrderTotals.cs` with a confidence, 1 to 3 tasks, Task 1 a test that must fail |
| `retro-repeat` | `/retro --since 2026-01-01` | spots the same repo and category in two items and proposes a rule (or flags the existing one as broken) without writing memory |

## How it fits together

| Path | What |
|---|---|
| `cases/<case>.json` | Command, arguments, which fixtures to lay down, which grader to run |
| `workspace/` | The repo map and `sample-api` (becomes its own git repo per run) |
| `fixtures/work/` | `.work` files for each starting point; `progress-add.md` is appended to `progress.md` |
| `fixtures/repo/` | Code committed on the branch before the run (the correct and the planted implementation) |
| `fixtures/hidden/` | Acceptance tests the do-task grader adds after the run, runs, and removes |
| `lib/Graders.ps1` | One grader per case: file and git checks, no model |
| `goldens/<case>/pass`, `fail` | Hand-written good and bad outputs that prove each grader tells them apart |
| `Test-Graders.ps1` | CI: every good golden passes, every bad golden fails (no model, no dotnet) |
| `Test-Fixtures.ps1` | CI with dotnet: the fixtures build, the planted bug is real, the do-task grader works end to end |

## Adding a case

1. Write `cases/<name>.json` and the fixtures it needs.
2. Add a grader function to `lib/Graders.ps1`. Prefer checks a script can decide over judgments.
3. Add `goldens/<name>/pass` and `goldens/<name>/fail`, and run `./evals/Test-Graders.ps1`.
4. Keep everything made up: no company names, people, or code.
