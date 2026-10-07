---
description: "Copy an approved TSD from .work into the product docs folder. Usage: /publish-tsd <short-name>"
agent: writer
---

Publish the technical spec in **.work/tsd-$1/**. Do not change any code.

## Step 1: Check the gate

- Read `.work/tsd-$1/tsd.md`. If it does not exist, list the `.work/tsd-*` folders and stop.
- If it does not contain `Status: APPROVED`, stop. Tell the engineer: "Review `tsd.md`, then change the line to `Status: APPROVED` and run `/publish-tsd $1` again." Never change the Status line to APPROVED yourself.
- Look for `.work/tsd-$1/check.md`.
  - If it does not exist, ask: "This TSD has not been fact-checked. Publish anyway? (Recommended: no. Run `/check-docs .work/tsd-$1/tsd.md` in a new session first.)" Wait. If the answer is no, stop.
  - If it lists any claim as `Wrong` or `Outdated`, list them in one line each and ask: "Publish anyway?" Wait. If the answer is no, stop.

## Step 2: Pick the destination

- Read the repo map (the workspace root `AGENTS.md`). Find the product block whose name matches the TSD title, or whose repo table lists the TSD's repos (the "Repos:" line under the title).
- If the product block has a "Product docs" folder, propose `<that folder>/technical-spec.md`.
- If there is no product docs folder, or no product matched, ask the engineer for the folder. Suggest the `docs/` folder of the main repo in the TSD.
- Ask: "Publish to `<path>`? (Recommended: yes.)" Wait and use their answer.
- If a file already exists at that path, read it and ask: "`<path>` already exists. Replace it? Git keeps the old version." Wait. If the answer is no, ask for another file name.

## Step 3: Write the published copy

Write the destination file with the content of `tsd.md`, changed only like this:

- Replace the `Status: APPROVED` line with `Approved: <today's date, YYYY-MM-DD>`.
- Delete every HTML comment (`<!-- ... -->`).
- Replace `Fact-check: not yet run.` with `Fact-checked against the code on <date of check.md>.`, or with `Not fact-checked.` if there is no `check.md`.
- Replace the "Sources" section body with one sentence: "Each table under a diagram lists the source files for that diagram."
- Leave every diagram and every table exactly as it is.

## Step 4: Mark the work copy

- In `.work/tsd-$1/tsd.md`, change the Status line to `Status: PUBLISHED to <destination path> on <today's date>`. Change nothing else.
- This tells `/tsd` where the live copy is the next time the TSD is updated.

## Step 5: Hand off

Tell the engineer:
- The destination path.
- "Review the diff and commit it yourself in `<repo that contains the destination>`."
- "If your doc editor does not render Mermaid, the SVGs are in `.work/tsd-$1/render/`."
- "To revise later, run `/tsd` again and choose update. It starts from the published copy."
