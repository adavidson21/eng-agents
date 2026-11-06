---
description: "Clarify a work item and write spec.md. Usage: /spec <id>"
agent: planner
---

Write the spec for work item **$1**.

## Step 1: Find the work folder

- List `.work/` and find the folder that starts with `$1-`. If there is none, stop and suggest `/start $1 feature`.

## Step 2: Read

- Read `workitem.md`, `repos.md`, and `progress.md` in the work folder.
- Read the repo guide (`<repo>/AGENTS.local.md` if it exists, otherwise `<repo>/AGENTS.md`) for every repo in `repos.md`.
- If `spec.md` exists and says `Status: APPROVED`, stop. Tell the engineer the spec is already approved and suggest `/plan $1`.
- If `spec.md` exists as a draft, read it. You are refining it, not starting over.

## Step 3: Understand current behavior

- Find the code related to this work item. Read at most 10 files.
- Write down what happens today, citing files you read.

## Step 4: Ask clarifying questions

- Make a private list of everything that is unclear or ambiguous. Drop anything the code, the work item or the files already answer, and anything where your recommended answer is safe to assume.
- Ask the engineer the most important question first. Ask **one question at a time**. For each question give 2 to 4 options and say which you recommend and why.
- Wait for each answer before asking the next question.
- Ask at most 3 questions. Stop sooner if the requirement is clear. Zero questions is fine.
- Put everything you did not ask under "Assumptions" with your recommended answer, so the engineer can change it at review.

## Step 5: Write spec.md

- Start from `{{ENG_HOME}}/templates/spec.md`. Write it to the work folder as `spec.md`.
- Keep `Status: DRAFT`. Never set it to APPROVED.
- Number acceptance criteria `AC-1`, `AC-2`, and so on. Use Given / When / Then. Each one must be testable.
- Put every question and answer from Step 4 in the "Decisions" table.
- Put anything still unknown in "Open questions".

## Step 6: Log and hand off

- Add a `progress.md` entry for `/spec`.
- Tell the engineer: "Review `spec.md`. Edit anything that is wrong. When it is correct, run `/approve $1` (or change the line to `Status: APPROVED` yourself), then `/plan $1`."
