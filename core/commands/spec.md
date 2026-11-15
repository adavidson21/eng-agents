---
description: "Clarify a work item and draft spec.md, plan.md and tasks.md for one approval. Usage: /spec <id> [auto]"
agent: planner
---

Write the spec, plan and tasks for work item **$1**. Mode: **$2**

The feature lane has one gate: this command drafts `spec.md`, then `plan.md` and `tasks.md` from it, and one `/approve` covers all three.

If the mode above is `auto`, nobody is watching (autopilot or an eval run). Ask no questions: in Step 4, write every question you would have asked under "Assumptions" with your recommended answer, and write `questions=0` on the Stats line. In Step 6, follow `/plan`'s `auto` rule for a missing repo.

## Step 1: Find the work folder

- List `.work/` and find the folder that starts with `$1-`. If there is none, stop and suggest `/start $1 feature`.

## Step 2: Read

- Read `workitem.md`, `repos.md`, and `progress.md` in the work folder.
- Read the repo guide (`<repo>/AGENTS.local.md` if it exists, otherwise `<repo>/AGENTS.md`) for every repo in `repos.md`.
- If a `.work/scope-*/published.md` lists `$1` in its Id column, read that story's "Notes for the builder" in the same folder's `milestones.md` (older files call it "Work item"). They are hints from slicing, not decisions.
- If `spec.md` exists and says `Status: APPROVED`, stop. Tell the engineer the spec is already approved and give the next command from `/status $1`.
- If `spec.md` exists as a draft, read it, and `plan.md` and `tasks.md` if they exist. You are refining them, not starting over.

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
- Number acceptance criteria `AC-1`, `AC-2`, and so on. Each one must be testable.
  - If the work item already has clear acceptance criteria, keep them in its own words and end each with `(from work item)`. Do not rewrite them. Add new ACs only for real gaps.
  - Write every new AC as Given / When / Then.
- Put every question and answer from Step 4 in the "Decisions" table.
- Put anything still unknown in "Open questions".

## Step 6: Draft the plan and the tasks

The spec is still a draft; that is expected. Do not wait for approval.

- Open `{{ENG_HOME}}/../commands/plan.md` and follow its Steps 2 to 5 to write `plan.md` from this draft spec. Skip its Step 1 and Step 6. Ask no new questions there: anything unclear goes under "Risks" or the spec's "Assumptions".
- Then open `{{ENG_HOME}}/../commands/tasks.md` and follow its Steps 2 to 4 to write `tasks.md`. Skip its Step 1 and Step 5.

## Step 7: Log and hand off

- Stamp both drafts as your last change: run exactly `{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/work/Set-DraftHash.ps1" -Path "<work folder>/spec.md"`, then the same command with `plan.md`. It adds a `Draft-hash:` line so `/approve` can tell whether the engineer edited the draft. If you change a file again, run it again for that file.
- Add three `progress.md` entries, in this order:
  - `/spec` with a `- Stats: questions=<n> assumptions=<n>` line (how many questions you asked the engineer, and how many assumptions you wrote instead).
  - `/plan` with a `- Stats: questions=0 assumptions=<n>` line.
  - `/tasks` with a `- Stats: tasks=<number of tasks>` line.
- Tell the engineer: "Review `spec.md`, `plan.md` and `tasks.md`. Edit anything that is wrong. When they are right, run `/approve $1` (it approves the spec and the plan together), then start a new session and run `/do-task $1 1`."
