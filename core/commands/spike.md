---
description: "Investigate a question without changing code and write findings.md. Usage: /spike <id or topic>"
agent: investigator
---

Run a spike on: **$ARGUMENTS**

## Step 1: Pick the folder

- If `$1` is a number and a folder in `.work/` starts with `$1-`, use that folder.
- Otherwise create a new folder `.work/spike-<short-name>/`, where `<short-name>` is 3 to 5 lowercase words from the topic joined with hyphens.

## Step 2: Frame the question

- Write the question as one sentence, plus the decision it will support.
- If either is unclear, ask the engineer ONE question to clarify. Wait.

## Step 3: Investigate

- Read the repo map and the `AGENTS.md` of each repo you look at.
- Read code, git history, and docs. Run builds or tests only if they answer a specific question.
- Do not change any code.
- Keep a list of facts (Confirmed) and beliefs (Suspected) with evidence.
- Stop when you can answer the question, or after about 25 files read, whichever comes first. If you hit the limit, report what you have.

## Step 4: Write findings.md

- Start from `{{ENG_HOME}}/templates/findings.md`. Write it to the folder as `findings.md`.
- Give 2 or 3 options when there is a real choice. Recommend one and give your confidence.

## Step 5: Hand off

- If the folder has a `progress.md`, add an entry for `/spike`.
- Give the engineer the short answer and recommendation in 3 lines or fewer, and the next step from `findings.md`.
