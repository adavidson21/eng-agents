---
description: "Shape an idea with the engineer: rounds of questions until it is understood, then a brief for /scope or /refine. Usage: /shape <idea>, /shape triage-<name>, or /shape shape-<name> [brief|more]"
agent: product-manager
---

Shape this: **$ARGUMENTS**

You interview the engineer (it is their idea, or a request they want to understand before defining it) in rounds, until the idea is understood well enough to scope. Each run is one round. Follow these steps in order. Do not change any code, and never post anything.

This is the interview the engineer asked for, so core rule 3's limit of 3 questions per command does not apply here: each round asks at most 5, in `questions.md`. The rest of rule 3 does: never ask what the files, the code, the triage or earlier answers already settle, and when a recommended answer is safe to assume, write it in `understanding.md` (as "Assumed: ...") instead of asking.

**You never ask questions in the chat.** Each round's questions go in `questions.md`, and the run ends. The engineer answers in Workshop's Slate (or in `answers.md` by hand) and runs `/shape shape-<name>` again.

## Step 1: Pick the folder

- If the request above is empty, stop and reply: `Usage: /shape <idea>, /shape triage-<name>, or /shape shape-<name> [brief|more]`.
- The mode is the second word, if it is `brief` (write the brief now, ask nothing more) or `more` (ask another round, even if a brief exists). Otherwise there is no mode.
- **Continue:** if the first word starts with `shape-`, the folder is `.work/<that word>/`. If it does not exist, list the `.work/shape-*` folders and stop.
- **From a triage:** if the first word starts with `triage-`, the folder is `.work/shape-<the rest>/` (for `triage-1234`, `.work/shape-1234/`). If `.work/<first word>/triage.md` does not exist, list the `.work/triage-*` folders and stop. If the shape folder exists, continue it; otherwise create it as below.
- **New:** otherwise the whole request is the idea. Make a short name: the first 5 meaningful words, lowercase, joined with `-`, at most 40 characters, filler words (a, an, the, to, of, for, and, add, new) dropped. The folder is `.work/shape-<short name>/`. If it already exists, stop and ask: "`.work/shape-<short name>/` exists. Continue it (`/shape shape-<short name>`) or use another name?"
- A new folder: copy `{{ENG_HOME}}/templates/progress.md` into it as `progress.md`, with the folder name as the id and the idea (or the triage's title) as the title. Write the idea, as given, to `idea.md` (from a triage: the triage's title and summary, and a line `From: .work/<triage folder>/`).

## Step 2: Read

- **First round** (no `questions.md` yet):
  - From a triage: read `triage.md`, `answers.md` if there is one, and the `workitem.md` beside them. Do not ask what they already answer.
  - Read the repo map (the workspace root `AGENTS.md`). Match words in the idea against the **Products** and **Glossary** tables to pick the product. If none or more than one matches, the first question picks it.
  - Read the product note (Product notes in the core rules) and the repo guide (`<repo>/AGENTS.local.md` if it exists, otherwise `<repo>/AGENTS.md`) of each repo in the product.
  - Search the code for the nouns in the idea and the closest thing that exists. Note each with its file path. Run `git -C <repo> log --oneline -20` for each repo.
- **Later rounds:** read `idea.md`, `understanding.md`, `questions.md`, `answers.md` and `brief.md` if it exists. Search the code again only for nouns that are new in the answers.
- `understanding.md` is the engineer's to edit. Treat every line in it as true unless an answer in `answers.md` says otherwise. Never drop a line they wrote.

## Step 3: Update understanding.md

- Start from `{{ENG_HOME}}/templates/shape-understanding.md` on the first round; update it after.
- Write what is known now, short, in the user's language: product, problem, who it is for, goals, non-goals, MVP, open points. Fold in every answer from `answers.md`. An answer of `Skipped` leaves that point open.
- Keep it under 60 lines. This is the running picture the engineer reads first.

## Step 4: Ask, or write the brief

Write the brief (Step 6) when the mode is `brief`, or when there is no mode and all of these are known: the problem, who it is for, the goals, the MVP line (what is in the first version and what can wait), and the rules or edge cases that would change the MVP. Also write it after round 6 with no mode, listing what is still open.

Otherwise (or when the mode is `more`), ask a round (Step 5).

## Step 5: A round of questions

- Start from `{{ENG_HOME}}/templates/shape-questions.md`. Write it to the folder as `questions.md`, replacing the last round.
- `Status: ASKING`. `Round:` is the last round plus 1 (1 on the first round).
- Up to **5 questions**, the ones whose answers change the most, in this order of topics: the product (only if unclear), the problem and who it is for, goals and non-goals, the MVP line, business rules and edge cases, risks. Do not ask about implementation; `/slice` and the build decide that.
- Each question: `## Q<n>: <question>`, then 2 to 4 options as `- A) ...`, `- B) ...`, then `Recommended: <letter>` and `Why: <one line>`, with a file path when the code backs it.
- Never ask again what `answers.md`, `understanding.md` or the triage already answer. From round 4 on, ask only what would change the MVP; leave details for `/scope` or `/refine` under Open points.

## Step 6: The brief

- Start from `{{ENG_HOME}}/templates/shape-brief.md`. Write it to the folder as `brief.md` (update it if it exists).
- `Level:` is `Epic` (a new version of the product, or several features), `Feature` (one usable piece), `User Story` or `Bug`. `Size:` is S, M, L or XL.
- Every section from what is known. No class names, tables or file paths outside "Product and repos". Open points go under "Open questions".
- Rewrite `questions.md` from the template with `Status: READY`, the same `Round:`, and no questions.

## Step 7: Log and hand off

- Add a `progress.md` entry for `/shape` (round, questions asked or brief written).
- Reply in 3 lines or fewer:
  - After a round: "Round <n>: <k> questions in `.work/shape-<name>/questions.md`. Answer them in Slate, or in `answers.md`, then `/shape shape-<name>`." Do not repeat the questions in the chat.
  - After the brief: the problem in one line, the level and size, open questions if any, and the next step: `/scope shape-<name>` (Epic or Feature) or `/refine shape-<name>` (User Story or Bug). `/shape shape-<name> more` asks another round.
