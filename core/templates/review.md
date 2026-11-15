# Review: <id> <title>

Verdict: <READY | CHANGES NEEDED>

## Test results

| Repo | Command | Result |
|---|---|---|
| <repo> | `<command>` | <PASS / FAIL (n failed)> |

## Pass 1: Spec compliance

| Criterion | Status | Evidence |
|---|---|---|
| AC-1 | <Met / Partly met / Not met> | <test name and file> |

Scope creep (changes no criterion or task asked for):
- <file and change, or "None">

## Pass 2: Code quality

Every finding goes in this table, including Pass 1 problems and missing checklists. Category is one word from the `/review` checklist (`architecture`, `consistency`, `correctness`, `efcore`, `security`, `tests`, `angular`, `playwright`, `leftovers`, `overbuild`, `tdd`) or `spec`, `scope`, `checklist`. `/retro` groups findings by it.

| # | Severity | Category | Location | Problem | Suggested fix |
|---|---|---|---|---|---|
| 1 | <Blocker / Should fix / Nit> | <category> | `<repo/path/File.cs:42>` | <what is wrong> | <how to fix> |

## Questions for you

Things the reviewer was not sure are problems. Not findings: they do not change the verdict.

- <`repo/path/File.cs:42`: question, or "None">

## Manual validation

Every task's checklist from `progress.md`, in order. Walk through these before `/pr`.

**Task 1: <title>**
1. Open <exact URL or file path>
2. <exact physical action>
3. Verify <exact result>

## Proposed fix tasks

Every Blocker (except checklist Blockers), plus the other findings the engineer picks. These get added to `tasks.md`.

- <Finding #1 -> one-line task>
