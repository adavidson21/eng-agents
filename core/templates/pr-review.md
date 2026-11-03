# PR review: <id> <title>

Reviewed commit: <first 7 characters of the source commit in context.md>
Reviewed: <YYYY-MM-DD>
Recommendation: <Approve | Approve after optional cleanup | Request changes | Needs clarification>
Risk: <low | medium | high>

## Summary

<Two or three sentences: what the PR changes and why, in plain words.>

## Intent

| Criterion | Status | Evidence |
|---|---|---|
| <acceptance criterion from a linked work item, or the PR description's goal> | <Met / Partly met / Not met / Not visible> | <`path/File.cs:42`, or the test name> |

Changes nothing asked for:
- <file and change, or "None">

## Comments

<One block per comment, numbered C1, C2, ... in order of severity (blocking first). If there are none, write "None." and delete the example block.>

### C1
- File: `<path/from/repo/root.cs>`
- Line: <line number in the PR's version of the file, or a range like 42-48>
- Severity: <blocking | should-fix | optional>
- Why: <one or two sentences on the real risk>

> <The comment as the engineer would post it: short, kind, specific. Usually one or two sentences. Only get technical when the problem needs it.>

## Questions for the author

- <Only questions whose answer would change the recommendation, or "None">

## Checked and fine

- <Short list of what you looked at and found OK, so the engineer knows what was covered>
