# Milestones: <scope name>

Status: DRAFT

<!-- The engineer approves this file with /approve scope-<name> milestones, or by changing the line above to "Status: APPROVED". No other command changes it. -->
<!-- Export-Backlog.ps1 reads this file. Keep every heading and the "Epic:" line exactly in this shape. Comments like this one are ignored. -->

Epic: <copy the Epic line from epics.md>

<Two to four sentences about the epic, copied from epics.md.>

## Feature 1: <title>

<!-- Features are in build order. Each one is a vertical slice: when its stories are done, a user can use it and you can verify it end to end. -->

- Goal: <what the user can do when this ships>
- Verify: <how to see it working end to end>

### Story 1.1: <title>

<!-- Stories are in build order. Each story is one /start item: at most 2 repos and about 8 tasks. -->

As a <role>, I want <capability>, so that <benefit>.

#### Acceptance criteria

```gherkin
Scenario: <name>
  Given <context>
  When <action>
  Then <result>
```

#### Work item

- Repos: `<repo>`
- Changes: `<repo>/path/to/File.cs` (<what changes>)
- Pattern to follow: `<repo>/path/to/Similar.cs`
- Data: <tables, columns, or migrations, or "none">
- Depends on: <Story n.m, or "none">

## Changes from stories.md

<!-- Every story you split, merged, moved, or reworded. "None" if nothing changed. -->

| Change | Why |
|---|---|
| <for example "Split 1.2 into 1.2 and 1.3"> | <reason> |

## Coverage

<!-- Every scenario in stories.md, and the story here that covers it. -->

| stories.md scenario | Covered by |
|---|---|
| 1.1 <scenario name> | Story 1.1 |

## Open questions

- <Anything still unknown. Must be empty before approval, or marked "accepted risk".>
