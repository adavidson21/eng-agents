---
description: "Approve a finished document in .work and move it to where it lives, for example a TSD into the product docs folder. Usage: /publish <.work folder, for example tsd-orders>"
agent: writer
---

Publish the document in **.work/$1/** (the `.work/` part is optional). Do not change any code.

Running this command is the engineer's approval. It is the only command, besides `/approve`, that may treat a document as approved.

## Step 1: Find the document

- Find the folder: `.work/$1/`, or `$1` itself if it already starts with `.work/`. If it does not exist, list the `.work/` folders that contain a file from the table below, and stop.
- Find which publishable file the folder contains:

| File | Kind | Default destination | File name at destination |
|---|---|---|---|
| `tsd.md` | Technical spec from `/tsd` | The product's "Product docs" folder in the repo map | `technical-spec.md` |

- If the folder has none of these, stop. If the folder starts with a work item id, tell the engineer that specs, plans, and bug analyses are approved with `/approve <id>`.
- Read the document's `Status:` line.
  - `Status: PUBLISHED ...`: tell the engineer where it was published and stop. To publish again after changes, run `/tsd` (update) first; it sets the draft back to DRAFT.
  - `Status: DRAFT` or `Status: APPROVED`: continue.

## Step 2: Check it is ready

- Look for `check.md` in the folder (written by `/check-docs`).
  - If there is none, ask: "This document has not been fact-checked. Publish anyway? (Recommended: no. Run `/check-docs .work/$1/<file>` in a new session first.)" Wait. If the answer is no, stop.
  - If it lists any claim as `Wrong` or `Outdated`, list them in one line each and ask: "Publish anyway?" Wait. If the answer is no, stop.
- If the "Open questions" section lists anything, show it and ask: "These questions are still open. Publish anyway? They stay in the published document." Wait. If the answer is no, stop.

## Step 3: Pick the destination

- Read the repo map (the workspace root `AGENTS.md`). Find the product block whose name matches the document title, or whose repo table lists the repos named in the document (the "Repos:" line under the title).
- If that product block has a "Product docs" folder, propose `<that folder>/<file name from the table>`.
- If there is no product docs folder, or no product matched, ask the engineer for the folder. Suggest the `docs/` folder of the first repo named in the document.
- Ask: "Publish to `<path>`? (Recommended: yes.)" Wait and use their answer.
- If a file already exists at that path, read it and ask: "`<path>` already exists. Replace it? Git keeps the old version." Wait. If the answer is no, ask for another file name.

## Step 4: Write the published copy

Write the destination file with the content of the document, changed only like this:

- Replace the `Status:` line with `Approved: <today's date, YYYY-MM-DD>`.
- Delete every HTML comment (`<!-- ... -->`).
- Replace `Fact-check: not yet run.` with `Fact-checked against the code on <date of check.md>.`, or with `Not fact-checked.` if there is no `check.md`.
- Replace the "Sources" section body with one sentence: "Each table under a diagram lists the source files for that diagram."
- Leave every diagram and every table exactly as it is.

## Step 5: Mark the work copy

- In the `.work` copy, change only the Status line to `Status: PUBLISHED to <destination path> on <today's date>`.
- This tells `/tsd` where the live copy is the next time it is updated.

## Step 6: Hand off

Tell the engineer:
- The destination path.
- "Review the diff and commit it yourself in `<repo that contains the destination>`."
- For a TSD: "If your doc editor does not render Mermaid, the SVGs are in `.work/$1/render/`."
- For a TSD: "To revise later, run `/tsd` again and choose update. It starts from the published copy."
