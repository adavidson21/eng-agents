# Writing product notes

Read by any agent before it changes a product note or the team handbook (the Product notes section of `AGENTS.md` points here), and by `/memory`, `/retro`, `/product-notes` and `/onboard-repo`.

When you confirm a fact that is missing from the note or contradicts it, and it would help the next person, change the note with:
  `{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/notes/Set-ProductNote.ps1" -Product "<product name>" -Line "<the fact>" -Source "<PR, work item or file>" [-Section <section>] [-Replace "<text of the wrong line>"]`
  - One fact per call, one short line, only facts you saw in code, a work item, a PR or from the engineer. Never guesses, plans, to-dos or session notes.
  - If a line already covers the subject, replace that line (`-Replace`) instead of adding a second. When a line is wrong, replace it; never keep both.
  - Default section is `Remembered`. Use `Business rules`, `Gotchas`, `Who to ask` or `Decisions` when the fact clearly belongs there. Never write owners: they live in Workshop's People.
  - **Team facts** (sprints, work item states, pull requests, releases, definition of done, who approves what) go in the handbook: use `-Note team/handbook.md` instead of `-Product`, with the matching section.
  - **A line the code contradicts, when you cannot confirm the right value:** flag it instead of replacing it: `-Product "<product>" -Flag "<text of the line>" -Reason "<what the code says>" -Source "<file>"`. The engineer sees it as stale in Folio.
  - Never edit these notes with any other tool: the script keeps the earlier version in Folio's history and marks the note "Changed by Tandem" for the engineer to review.
  - If the script says the note is over budget, propose a tidy to the engineer instead of adding more.
  - List every change in your reply: the note, the section, and the line before and after.

When you change a repo guide's `## Remembered` or the global rules (`memory.md`), log it so the engineer reviews it in Folio with the rest:
  `{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/notes/Set-ProductNote.ps1" -Note tandem/changes.md -Line "<repo> repo guide, Remembered: <the rule>" -Source "<the command>"` (for global rules: `global rules: <the rule>`). If it says product notes are not available, skip it.
