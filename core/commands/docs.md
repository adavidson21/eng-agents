---
description: "Draft or update documentation from the code. Usage: /docs <what to document>"
agent: writer
---

Write documentation for: **$ARGUMENTS**

## Step 1: Clarify

Work out these three things from the request, the repo and its existing docs. Do not ask: pick the most likely answer for anything missing, and show your picks in Step 6 so the engineer can change them:
- **Where** the doc lives (file path, new or existing).
- **Who** reads it (new engineer, another team, operations, end user).
- **What** they need to do after reading it.

## Step 2: Read

- Read the `AGENTS.md` of the repo involved.
- If the doc already exists, read it fully.
- Read the code the doc describes. Keep a list of every fact you will state and the file it came from.

## Step 3: Outline

- Show the engineer a short outline: headings with one line each. Ask: "Does this outline work?" Wait. Apply changes.

## Step 4: Write

- Write the doc to the agreed path.
- Every fact must come from your list in Step 2. If you are not sure about something, leave it out and list it as a question.
- Match the style of existing docs in that repo.

## Step 5: Save sources for the fact check

- Create `.work/docs-<short-name>/sources.md` listing each factual claim and the file that supports it. `<short-name>` is 3 to 5 lowercase words from the doc's topic joined with hyphens.

## Step 6: Hand off

- Tell the engineer the doc path, your picks from Step 1 in one line (where, who, what they do next: "Change any of these and run `/docs` again"), any open questions, and: "Start a new session and run `/check-docs <doc path>` to fact-check it against the code."
