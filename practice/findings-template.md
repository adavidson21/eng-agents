# Practice run findings

Copy this file to your practice workspace as `FINDINGS.md` and fill it in as you go. When done, paste it back to Claude so the fixes can go into the base repo.

Model used: <name>
opencode version: <`opencode --version`>
Date: <date>

## Setup and verification

| Check | Result (pass / fail / notes) |
|---|---|
| install.ps1 -DryRun output looked right | |
| install.ps1 wrote 3 sections to AGENTS.md (Core, Personal, Company) | |
| `/` shows the eng-agents commands | |
| Tab cycles to planner, implementer, reviewer, investigator, writer | |
| Planner can write `.work/_test/hello.md` without a prompt | |
| Planner is denied editing a `.cs` file | |
| Templates readable without an external-directory prompt | |
| `git push` is denied for the implementer | |

## Command runs

For each command: did it follow the steps, where did it go wrong, how many prompts did you get, how long did it take.

| Command | Worked? | Problems | Prompts you had to approve |
|---|---|---|---|
| /onboard-repo shared-lib | | | |
| /onboard-repo orders-api | | | |
| /onboard-repo orders-ui | | | |
| /start 101 bug | | | |
| /bug 101 | | | |
| /start 102 feature | | | |
| /spec 102 | | | |
| /plan 102 | | | |
| /tasks 102 | | | |
| /spike 103 ... | | | |
| /status | | | |
| /standup | | | |
| /do-task 101 1 (Tier 2) | | | |
| /do-task 101 2 (Tier 2) | | | |
| /review 101 (Tier 2) | | | |
| /pr 101 (Tier 2) | | | |
| /docs ... 104 (Tier 2) | | | |
| /check-docs ... (Tier 2) | | | |

## Biggest problems (most important first)

1.
2.
3.

## Things that worked well

-
