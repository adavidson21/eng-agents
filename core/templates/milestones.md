# Milestones: <scope name>

Status: DRAFT

<!-- The engineer approves this file with /approve scope-<name> milestones, or by changing the line above to "Status: APPROVED". No other command changes it. -->
<!-- Export-Backlog.ps1 reads this file. Keep every heading and the "Epic:" line exactly in this shape. Comments like this one are ignored. -->

Epic: <copy the Epic line from epics.md>

<Two to four sentences about the epic, copied from epics.md.>

## Feature 1: <title>

<!-- Features are in build order. Each one is a vertical slice: when its stories are done, a user can use it and you can verify it end to end. -->
<!-- The description is two or three sentences: what the user can do when it ships, and why it matters. No design, screens, fields, or code. It is published to ADO. -->

<Two or three sentences.>

#### Release note

<!-- One or two business-friendly sentences for customers: what they can do now. No jargon, ids, or code. At most 255 characters. Published to the release note field in ADO. -->

<One or two sentences.>

### Story 1.1: <title>

<!-- Stories are in build order. Each story is one /start item: at most 2 repos and about 8 tasks. -->
<!-- Say what and why, not how. Engineering decides the implementation. -->

As a <role>, I want <capability>, so that <benefit>.

<Optional: one or two sentences of context.>

#### Acceptance criteria

<!-- 2 to 5 scenarios: the main outcome and the edge cases a user would notice. Outcomes only: no button labels, layouts, field names, or data shapes unless the requester asked for them. -->

```gherkin
Scenario: <name>
  Given <context>
  When <action>
  Then <result>
```

#### Notes for the builder

<!-- Local only: never published to ADO. Pointers, not decisions; the engineer may build it another way. -->

- Repos: `<repo>`
- Where to look: `<repo>/path/to/File.cs` (<why>)
- Similar existing code: `<repo>/path/to/Similar.cs`
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
