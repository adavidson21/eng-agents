# Brief: <id> <title>

<!-- Written by /start (skip with --cold). A two-minute read for the engineer, so a new item never starts from a blank screen. Built only from workitem.md, repos.md, file names and commit messages. No file contents were read. Keep each section short. -->

## Goal

<One sentence: what changes for the user, in plain words.>

## Done means

- [ ] <acceptance criterion, one per line, in the work item's words>

<!-- "None provided" if the work item has no acceptance criteria. Then /spec will ask. -->

## Where it fits

- Epic (version): <#id title, or "unknown">
- Feature (smallest usable deliverable): <#id title, or "unknown">
- This item: <type> #<id>, which builds the Feature above.

<!-- From the "Parents" section of workitem.md. Write "Parents unknown" if it is missing or could not be fetched. Write "None" for local work. -->

## Recent talk

- <one line per comment, the 5 newest at most>

<!-- "No comments" if there are none. "Comments not fetched" if workitem.md says so. -->

## Repos and branch

| Repo | Branch | Base |
|---|---|---|
| <repo-folder> | <dev/feature/id-short-name> | <origin/main> |

## Likely files (guesses)

These are guesses from file names and commit messages that match words in the title. Nothing was opened. Check them before you trust them.

- `<repo>/<path>`: <why: name matches "<word>", or commit "<message>">

<!-- At most 10. "No matches" if none. -->

## First tiny step

<Usually: run `/spec <id>` (or `/bug <id>` for a bug). Or one concrete question to answer first, if the work item leaves something important open.>
