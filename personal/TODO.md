# personal/

Your **Personal layer**: how *you* like to work. Empty in the base repo. Fill it in your own fork only, never in the base repo, and never with company names.

**How to set it up:** [docs/onboarding-personal.md](../docs/onboarding-personal.md)

This file is never installed. Leave it in place so merges from the base repo stay clean.

## Ideas for layering on top of Core

Core stays as it is. You add to it. Use the lightest option that works:

| Option | When | Core updates still reach you? |
|---|---|---|
| A rule in `personal/AGENTS.md` under a heading for one agent | You want to add or adjust behavior | Yes |
| A new file in `personal/commands/` | You want a new command | Yes (new name) |
| A file in `personal/templates/` | You want a different format | No, for that template |
| A file in `personal/agents/` | You must change permissions or the model | No, for that agent |

Start with 3 to 5 rules. Add more only when you see the same mistake twice.

### Rules for one agent

Every agent reads `personal/AGENTS.md`, so put agent-specific rules under a heading the agent will recognize. Copy what fits:

```markdown
## When you are the implementer
- Before asking to commit, show the changed files with line counts.
- Run the whole test project for the repo, not just the new test, before marking a task done.
- Run `dotnet format` on the files you changed before committing.
- Add to an existing test class when one covers the same type. Do not create a new one.
- Commit messages: "<id>: <summary>".

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
- PR descriptions: start with why, then what, then a "How to test" list a reviewer can follow.
- Docs: write for someone in their first week on the team.
```

### Commands to add

| Command | Agent | What it does |
|---|---|---|
| `/standup [days]` | planner | Yesterday / Today / Blockers from every `progress.md` |
| `/weekly` | planner | One line per work item for the week, for a status report |
| `/handoff <id>` | planner | Summary for a teammate taking over an item: where it stands, decisions, gotchas |
| `/review-branch <repo> <branch>` | reviewer | Review someone else's branch against main with the same checklist as `/review` |
| `/explain <path>` | planner | Plain-language walkthrough of a file or folder, read-only |
| `/retro <id>` | planner | What went well or badly on an item, and rules to add to the repo `AGENTS.md` |

See [onboarding-personal.md step 2](../docs/onboarding-personal.md#2-add-commands-optional) for the file format.

### Templates to override

| Template | Common change |
|---|---|
| `pr.md` | Add "How to test" and "Screenshots" sections |
| `spec.md` | Add "Rollout" or "Telemetry" sections (keep the `Status:` line and `AC-n` criteria) |
| `progress.md` | Shorter entries, or a different output length |

See [Customizing templates](../docs/customization.md#customizing-templates) for what each template must keep. If your company overlay also overrides a template, the company version wins.
