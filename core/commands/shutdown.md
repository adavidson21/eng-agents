---
description: "End the day: capture uncommitted work and what is in your head, and write tomorrow's runway (.work/runway.md). Usage: /shutdown"
agent: planner
---

Shut down for the day. Offload the engineer's working memory and write the runway for tomorrow morning.

Do not change code, commit, stash, or push. The only file you write is `.work/runway.md`.

## Step 1: Gather the state (silently)

Do this without narrating each command. Do not show the output yet.

- List the repo folders in the workspace root (folders with a `.git` folder).
- For each repo, run:
  - `git -C <repo> status --porcelain --branch`
  - `git -C <repo> diff --stat`
  - `git -C <repo> diff` only if `--stat` shows 10 files or fewer. Read it to understand what is half-done or broken. Do not paste it anywhere.
- List every folder in `.work/` except `_onboard` and `_dashboard`. For each one that is not finished, read the last entry of `progress.md` and work out its phase and next command with the "Next-command rules" in `{{ENG_HOME}}/../commands/status.md`. Note any entry where a verify step failed or a task is blocked.
- If `.work/runway.md` exists, read it. Its "Open Loops" may still be open.

## Step 2: Ask

Ask exactly this, and nothing else:

"What is the very first thing you need to tackle tomorrow at 9:00 AM, and is there anything else lingering in your head?"

If the previous runway had open loops, add one line after the question: "Still open from last time: <loop>; <loop>. Drop any that are done."

Wait for the answer.

## Step 3: Write the runway

- Start from `{{ENG_HOME}}/templates/runway.md`. Write it as `.work/runway.md`, replacing any old one.
- **Current State:** exactly two sentences from Step 1: what is uncommitted (repo and what the change is), and where the code was left. If everything is clean, say so and name the item that is furthest along.
- **Tomorrow's Ignition:** one step, the smallest one that gets the engineer moving on what they said. Make it concrete: the exact pipeline command (with "in a new session" for `/do-task`), or the file and line to open. If their answer is about something outside the pipeline, write the first physical action for it.
- **Open Loops:** everything else they said, one line each, in their words, plus loops from the old runway they did not drop. Add failing verify steps or blocked tasks from Step 1. Write "None" if there is nothing.
- **Snapshot:** fill both tables from Step 1. Only list repos that are off their default branch, dirty, or unpushed; then one line "Clean: <repo>, <repo>".
- Never write secrets, tokens, or connection strings, even if they appear in a diff.

## Step 4: Finish

- Add a `progress.md` entry for `/shutdown` to the item named in Tomorrow's Ignition, if it names one. Otherwise skip this.
- If any repo has uncommitted changes, add one line before the final message: "Uncommitted work in <repo>, <repo>. It is safe where it is; `/pause <id>` can commit it as WIP if you want."
- Then print this exact final message:

"✅ Runway paved. The workday is paused. Close the terminal."
