---
description: "Clarify a work item and draft spec.md, plan.md and tasks.md for one approval, or redo just the plan or the tasks. Usage: /spec <id> [plan | tasks] [auto]"
agent: planner
---

Write the spec, plan and tasks for work item **$1**. Arguments: **$ARGUMENTS**

The feature lane has one gate: this command drafts `spec.md`, then `plan.md` and `tasks.md` from it, and one `/approve` covers all three.

Read the words after the id:

- **Part.** `plan` redoes only `plan.md`; `tasks` redoes only `tasks.md` (an older item, or after big edits). No part: draft all three.
- **Mode.** `auto` means nobody is watching (autopilot or an eval run). Ask no questions: write every question you would have asked under "Assumptions" with your recommended answer, and write `questions=0` on the Stats line. If Step 6 finds a repo that is not in `repos.md`, do not add it: plan only the listed repos and write the missing repo under "Risks" as an open question.

| Part | Steps |
|---|---|
| none | 1 to 8 |
| `plan` | 1, 2, 6, 8 |
| `tasks` | 1, 2, 7, 8 |

## Step 1: Find the work folder and check the gate

- List `.work/` and find the folder that starts with `$1-`. If there is none, stop and suggest `/start $1 feature`.
- No part: if `spec.md` says `Status: APPROVED`, stop. Tell the engineer the spec is already approved and give the next command from `/status $1`. If `spec.md` exists as a draft, read it, and `plan.md` and `tasks.md` if they exist: you are refining them, not starting over.
- `plan`: `spec.md` must exist (a draft is fine). If it does not, stop and suggest `/spec $1`. If `plan.md` says `Status: APPROVED`, stop and say the plan is approved.
- `tasks`: `plan.md` must exist (a draft is fine). If it does not, stop and suggest `/spec $1`. If any task in `tasks.md` is checked `[x]`, stop: work has started. Ask whether to add tasks at the end instead (in `auto`, add a `progress.md` entry saying why you stopped).

## Step 2: Read

- Read `workitem.md`, `repos.md`, `progress.md`, and `spec.md` and `plan.md` if they exist.
- Read the repo guide (`<repo>/AGENTS.local.md` if it exists, otherwise `<repo>/AGENTS.md`) for every repo in `repos.md`: its architecture rules, "Patterns to follow" table and Commands table, and the stack files its `Stack:` line names (Testing rules in `AGENTS.md`). If it points to an architecture doc, read that too.
- If a `.work/scope-*/published.md` lists `$1` in its Id column, read that story's "Notes for the builder" in the same folder's `milestones.md` (older files call it "Work item"). They are hints from slicing, not decisions.
- **A story from an approved breakdown** (`workitem.md` has `- Breakdown: approved`): the engineer approved what it covers, its repos (`- Repos:`) and its areas (`- Areas:`). Keep the plan inside them: change files only under those areas (tests may go anywhere), add no dependency, migration, or auth or security code unless the story needs it. When it truly does, plan it anyway and say why under "Risks": `/approve $1 spec auto` then holds the plan for the engineer instead of approving it.

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

## Step 6: Write plan.md

The spec may still be a draft; that is expected. Do not wait for approval, and ask no new questions here: anything unclear goes under "Risks" or the spec's "Assumptions".

- For each acceptance criterion, find where the change belongs. Follow the architecture layers in the repo guide.
- For each repo, find one existing file that does something similar. This is the "pattern to follow".
- List every file to create or change. Use real paths you have seen.
- If the plan needs a repo that is not in `repos.md`, stop and ask the engineer. If they agree, add it to `repos.md` and create its branch the same way `/start` does (Step 7 of `/start`).
- Start from `{{ENG_HOME}}/templates/plan.md`. Write it to the work folder as `plan.md`. Keep `Status: DRAFT`. Never set it to APPROVED.
- List repos in the same order as `repos.md`.
- In the test plan, every acceptance criterion must have at least one test, of the kind the repo's stack files ask for. In a repo whose guide has a `## Regression tests` table, a criterion a person can see or click also gets an end-to-end test titled with `[AC-<n>]` (playwright stack), so nobody tests it by hand.
- Keep the plan short. If a section has nothing to say, write "None".

## Step 7: Write tasks.md

Start from `{{ENG_HOME}}/templates/tasks.md`. Write it to the work folder as `tasks.md`. `/quick` and `/revise` follow the same rules.

Rules for every task:
- One repo only.
- At most `taskFileCap` files (Factory settings in the pipeline guide, default 6). Test files do not count.
- Follow each stack file's task rules (for example, `dotnet` puts the test and the code it tests in the same task, so the implementer can do TDD).
- Exactly one verify command, copied from the repo guide's Commands table and narrowed to the relevant tests with a filter when possible.
- A "Done when" line that anyone could check.
- A "Pattern to follow" file from the plan.
- A "Human interface" line: the page, button, endpoint, command, or log line a person uses to see this change. Use only routes and names you have seen in the code.
- Order: shared repos first, then the order in `repos.md`. Inside a repo: domain and application code first, then infrastructure, then API, then UI, then Playwright.

Then fill in the coverage table. Every acceptance criterion must be covered by at least one task; if one is not, add a task.

## Step 8: Log and hand off

- Stamp each gate file you wrote as your last change to it: run exactly `{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/work/Set-DraftHash.ps1" -Path "<work folder>/spec.md"`, then the same command with `plan.md` (only the files you wrote; `tasks.md` has no stamp). It adds a `Draft-hash:` line so `/approve` can tell whether the engineer edited the draft. If you change a file again, run it again for that file.
- Add one `progress.md` entry per file you wrote, in this order. `/stats` reads these names and Stats lines:
  - `/spec` with a `- Stats: questions=<n> assumptions=<n>` line (how many questions you asked the engineer, and how many assumptions you wrote instead).
  - `/plan` with a `- Stats: questions=0 assumptions=<n>` line.
  - `/tasks` with a `- Stats: tasks=<number of tasks>` line.
- Tell the engineer how many tasks there are per repo, then:
  - If `spec.md` or `plan.md` is still a draft: "Review `spec.md`, `plan.md` and `tasks.md`. Edit anything that is wrong. When they are right, run `/approve $1` (it approves the spec and the plan together), then start a new session and run `/do-task $1 1`." After a `plan` redo, add: "Run `/spec $1 tasks` if the new plan changes the tasks."
  - Otherwise: "Skim `tasks.md`. If a task looks too big, split it. Then start a new session and run `/do-task $1 1`."
