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

Results files are `version: 3`:

- Each case entry has an `arm` (`tandem` or `baseline`), `passAll` (every run passed), `meanSeconds`, `promptTokens` (what its commands load up front, see Prompt size), and usage: `usageKnown`, `meanTokens`, `meanCost`, `tokensPerPass`, `costPerPass` (null without a pass), `meanQuestions`, `meanToolCalls`, `meanVerifyFails`.
- Each run has `tokens` (input, output and reasoning), `cost`, `toolCalls`, `questions` (the agent asked; should be 0 in `auto`), `verifyFails` (failed verifies in its `.work` progress logs), `usageKnown`, and its `steps` with seconds, tokens and cost.
- Usage comes from `opencode run --format json`, which the runner always passes: `step_finish` events carry tokens and cost, `tool_use` events are tool calls (a `question` tool is the agent asking). `usageKnown` is false when no `step_finish` was seen, so a missing number is never shown as 0. Free models report a cost of 0; compare them on tokens.
- Version 2 files have no usage; version 1 files also have no `arm` (read them as `tandem`).

## Prompt size

`./evals/Get-PromptSize.ps1` lists what each command loads before it does anything (its command file, its agent and `AGENTS.md`), in estimated tokens, biggest first. No model. Use it to pick what to trim; a trim is kept only if the evals do not drop.

Cases marked `needs: dotnet` are skipped without the .NET 8 SDK.

## Does Tandem help? (the lift)

`-Arm both` runs each case twice over: once with Tandem (the **tandem** arm) and once as one plain prompt with Tandem left out (the **baseline** arm), on the same model. The summary adds a lift table: Tandem's pass rate minus the baseline's, per case.

```
./evals/Invoke-Evals.ps1 -Case feature-outcome -Arm both -Runs 3 -AutoApprove -Model <provider/model>
```

- Only cases with a `baseline` prompt take part in the baseline arm (today: `feature-outcome`). `-Arm baseline` runs just that arm.
- The baseline arm starts opencode with a config folder made for the run (`XDG_CONFIG_HOME`): your `opencode.json` without `instructions`, `agent`, `command` and `mode`, so it keeps your model, providers and permissions but none of Tandem's rules, memory, agents or commands. No `.work` files are laid down either.
- Both arms get the same workspace, repo map and repo guide, so the lift measures Tandem's phases, not its knowledge files.
- The Tandem arm of a case with `steps` runs several commands in one workspace and approves each gate in between (the `Status:` line, as `/approve` does), like autopilot. `eachTask` runs `/do-task` once per open task in `tasks.md` (at most 8).
- Report pass rate (any run) and whether every run passed (`Every run`, pass^k). Never compare a pass rate with a best-of-N number.

Workshop's **Bench** app shows the same results: lift, history, compare and each run's failed checks, and can start a run in a terminal you can see.

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
| `small-lane` | `/quick L3 auto` | a one-task change stays quick: quick.md with Given/When/Then ACs and a real pattern file, 1 or 2 tasks with verify commands from the repo guide |
| `small-lane-escalate` | `/quick L4 auto` | a schema plus API change steps up: `Lane: feature`, no quick.md or tasks.md, `escalated=1` logged |
| `feature-outcome` | the whole feature lane (`/spec`, `/plan`, `/tasks`, `/do-task` per task), or one plain prompt (`-Arm baseline`) | outcome only: hidden outcome tests pass, `LegacyRound` kept, settings in `PricingOptions`, changes only under `src/` and `tests/` (committed or not) |
| `retro-repeat` | `/retro --since 2026-01-01` | spots the same repo and category in two items and proposes a rule (or flags the existing one as broken) without writing memory |

## How it fits together

| Path | What |
|---|---|
| `cases/<case>.json` | Command and arguments (or `steps`), an optional `baseline.prompt`, which fixtures to lay down, which grader to run |
| `workspace/` | The repo map and `sample-api` (becomes its own git repo per run) |
| `fixtures/work/` | `.work` files for each starting point; `progress-add.md` is appended to `progress.md` |
| `fixtures/repo/` | Code committed on the branch before the run (the correct and the planted implementation) |
| `fixtures/hidden/` | Acceptance tests the do-task grader adds after the run, runs, and removes |
| `fixtures/hidden-outcome/` | Behavior-only tests the feature-outcome grader adds, runs and removes (no names either arm had to guess) |
| `lib/Graders.ps1` | One grader per case: file and git checks, no model |
| `goldens/<case>/pass`, `fail` | Hand-written good and bad outputs that prove each grader tells them apart |
| `Test-Graders.ps1` | CI: every good golden passes, every bad golden fails (no model, no dotnet) |
| `Test-Harness.ps1` | CI: `Invoke-Evals.ps1` itself, with a fake opencode (`selftest/fake-opencode`): steps in order, gates approved, the baseline's config without Tandem, results with both arms, the lift and usage (tokens, cost, questions, failed verifies); the usage reader and prompt sizes |
| `Get-PromptSize.ps1` | What each command loads up front, in estimated tokens (also printed in CI) |
| `Test-Fixtures.ps1` | CI with dotnet: the fixtures build, the planted bug is real, the do-task grader works end to end |

## Adding a case

1. Write `cases/<name>.json` and the fixtures it needs.
2. Add a grader function to `lib/Graders.ps1`. Prefer checks a script can decide over judgments.
3. Add `goldens/<name>/pass` and `goldens/<name>/fail`, and run `./evals/Test-Graders.ps1`.
4. For a lift case, grade the outcome only (files, tests, scope), never Tandem's own files, so both arms are graded the same way, and add a `baseline.prompt` that gives the plain arm the same information the work item gives Tandem.
5. Keep everything made up: no company names, people, or code.
