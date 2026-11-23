# Refine: <title>

Status: DRAFT
Type: <User Story | Bug>
Parent: <#id or none>

<!-- Written by /refine. The engineer approves it with /approve refine-<name>, or by changing the Status line to "Status: APPROVED". Builds (Workshop) publishes the Description and Acceptance criteria sections to ADO as they are. -->

## Description

As a <role>, I want <capability>, so that <benefit>.

<One or two sentences of context: what exists today and what changes. Say what and why, not how. User's language, no class names or file paths.>

## Acceptance criteria

<!-- 1 to 3 scenarios: the main outcome and the edge cases a user would really notice. Outcomes only: no button labels, layouts, field names, or data shapes unless the requester asked for them. -->

```gherkin
Scenario: <name>
  Given <context>
  When <action>
  Then <result>
```

## Release note

<One or two plain, business-friendly sentences about what users can now do. Not published by Builds yet: copy it into the release notes field.>

## Notes for the builder

- <Pointers into the code you saw (`repo/path/File.cs`), and anything to watch. Hints, not decisions. Not published to ADO.>

## Open questions

- <Anything still unknown. Must be empty before approval, or marked "accepted risk".>
