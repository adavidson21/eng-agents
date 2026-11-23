---
description: "Draft or update documentation from the code. Usage: /docs <what to document>"
agent: writer
---

Write documentation for: **$ARGUMENTS**

## Step 1: Clarify

If the request ends with `--name <short-name>` (Loom sends it), take it off the request: it is the `<short-name>` in Step 5.

Work out these three things from the request, the repo and its existing docs. Do not ask: pick the most likely answer for anything missing, and show your picks in Step 6 so the engineer can change them:
- **Where** the doc lives (file path, new or existing).
- **Who** reads it (new engineer, another team, operations, end user).
- **What** they need to do after reading it.

## Step 2: Read

- Read the `AGENTS.md` of the repo involved.
- If the doc already exists, read it fully.
- Read the code the doc describes. Keep a list of every fact you will state and the file it came from.

## Step 3: Outline

- Plan a short outline (headings with one line each) and write from it. Do not ask about it: the engineer reads the draft next and can send it back.

## Step 4: Write

- Write the doc to the agreed path.
- Every fact must come from your list in Step 2. If you are not sure about something, leave it out and list it as a question.
- Match the style of existing docs in that repo.

## Step 5: Save sources for the fact check

- Create `.work/docs-<short-name>/sources.md` listing each factual claim and the file that supports it. `<short-name>` is the `--name` value from Step 1, or else 3 to 5 lowercase words from the doc's topic joined with hyphens.
- The first line of `sources.md` is `Doc: <the doc's path from the workspace root>`, for example `Doc: gateway/docs/run-locally.md`. Loom reads it to save the doc to Folio, and `/publish` reads it to approve the doc.

## Step 6: Hand off

- Tell the engineer the doc path, your picks from Step 1 in one line (where, who, what they do next: "Change any of these and run `/docs` again"), any open questions, and: "Read the draft first. When it says the right things, start a new session and run `/check-docs <doc path>` to fact-check it against the code. Then `/publish docs-<short-name>` approves it."
