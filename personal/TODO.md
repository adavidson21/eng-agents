# personal/

Your **Personal layer**: how *you* like to work. Empty in the base repo. Fill it in your own fork only, never with company names. Setup: [Personal onboarding](../docs/onboarding-personal.md).

This file is never installed. Leave it so merges from the base stay clean.

Start with 3 to 5 rules. Add more only when you see the same mistake twice.

## Rules for one agent

Every agent reads `personal/AGENTS.md`, so put agent-specific rules under a heading the agent will recognize. Copy what fits:

```markdown
## When you are the implementer
- Before asking to commit, show the changed files with line counts.
- Run the whole test project for the repo, not just the new test, before marking a task done.
- Add to an existing test class when one covers the same type. Do not create a new one.

## When you are the planner
- In /spec, ask at most 4 questions. Put anything else under Open questions.
- In every plan, say whether the change needs a feature flag and why.
- Prefer 4 to 6 tasks. If a plan needs more than 8, suggest splitting the work item.

## When you are the reviewer
- Flag any new method longer than 30 lines as Should fix.
- Flag async methods that do not accept a CancellationToken when callers have one.
- Treat a missing test for an edge case named in the spec as a Blocker.

## When you are the investigator
- In /bug, include `git log` for the files on the code path, last 10 commits.
- In spikes, give at most 3 options, each with effort (S, M, L) and risk.

## When you are the writer
- PR descriptions: start with why, then what, then a "How to test" list.
- Docs: write for someone in their first week on the team.
```

## Commands to add

| Command | Agent | What it does |
|---|---|---|
| `/standup [days]` | planner | Yesterday / Today / Blockers from every `progress.md` |
| `/weekly` | planner | One line per work item for the week |
| `/handoff <id>` | planner | Summary for a teammate taking over an item: status, decisions, gotchas |
| `/review-branch <repo> <branch>` | reviewer | Review someone else's branch against `main` with the `/review` checklist |
| `/explain <path>` | planner | Plain-language walkthrough of a file or folder |
| `/retro <id>` | planner | What went well or badly, and rules to add to the repo `AGENTS.md` |

File format: [Personal onboarding, step 3](../docs/onboarding-personal.md#3-optional-commands-overrides-permissions).

## Permissions to add

Commands you approve every time can go in `personal/permissions/read.json` (read-only, every agent) or `build.json` (build and test agents). Only the keys you add:

```json
{
  "npx playwright show-report*": "allow"
}
```

Details: [Permissions](../docs/customization.md#permissions).

## Templates to override

| Template | Common change |
|---|---|
| `pr.md` | Add "How to test" and "Screenshots" sections |
| `spec.md` | Add "Rollout" or "Telemetry" sections |
| `progress.md` | Shorter entries |

What each template must keep: [Customizing templates](../docs/customization.md#customizing-templates). A company overlay template with the same name wins over yours.
