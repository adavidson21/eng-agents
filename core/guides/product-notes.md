# Writing product notes

Read by any agent before it changes a product note (the Product notes section of `AGENTS.md` points here), and by `/memory -product`, `/product-notes` and `/onboard-repo`.

When you confirm a product fact that is missing from the note or contradicts it, and it would help the next person working on this product, change the note with:
  `{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/notes/Set-ProductNote.ps1" -Product "<product name>" -Line "<the fact>" -Source "<PR, work item or file>" [-Section <section>] [-Replace "<text of the wrong line>"]`
  - One fact per call, one short line, only facts you saw in code, a work item, a PR or from the engineer. Never guesses, plans, to-dos or session notes.
  - If a line already covers the subject, replace that line (`-Replace`) instead of adding a second. When a line is wrong, replace it; never keep both.
  - Default section is `Remembered`. Use `Business rules`, `Gotchas`, `People` or `Decisions` when the fact clearly belongs there.
  - Never edit product notes with any other tool: the script keeps the earlier version in Notes' history and marks the note "Changed by Tandem" for the engineer to review.
  - If the script says the note is over budget, propose a tidy to the engineer instead of adding more.
  - List every product note change in your reply: the note, the section, and the line before and after.
