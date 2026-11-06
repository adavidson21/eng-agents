---
description: "Triage an enhancement request before any work starts: what it is, what it touches, what is missing, and who should build it. Usage: /triage <ADO id or the request in words>, or /triage triage-<name> to triage again"
agent: investigator
---

Triage this request: **$ARGUMENTS**

Follow these steps in order. Do not change any code, and never post anything to ADO.

## Step 1: Pick the folder

- If `$ARGUMENTS` is empty, stop and reply: `Usage: /triage <ADO id or the request in words>, or /triage triage-<name> to triage again`.
- **Folder:** if `$ARGUMENTS` is one word that starts with `triage-`, it is an existing folder: `.work/$1/`. If it does not exist, list the `.work/triage-*` folders and stop. Otherwise this is a re-triage (below). If the folder name is `triage-<number>`, that number is the ADO item: do Step 2 with it.
- **ADO item:** `$1` is a number. The folder is `.work/triage-$1/`.
- **Words:** otherwise the whole of `$ARGUMENTS` is the request. Make a short name from it: the first 5 meaningful words, lowercase, joined with `-`, at most 40 characters, filler words (a, an, the, to, of, for, and, add, new) dropped. The folder is `.work/triage-<short name>/`.
- **Again:** if the folder already has a `triage.md`, this is a re-triage. Read it, and `answers.md` in the folder if there is one (the requester's answers, pasted in by the engineer or by Slate). Keep what still holds and update the rest.

## Step 2: Get the request (ADO item only)

Run exactly this command:

```
{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/ado/Get-WorkItem.ps1" -Id $1 -WorkRoot ".work/triage-$1" -Parents -IncludeComments
```

- It writes `workitem.md` into a folder inside `.work/triage-$1/`. Read it, including the comments: answers to earlier questions often arrive there.
- If the command fails, say so in one line, and stop. Do not guess the request.

## Step 3: Read the product and the code

- Read the repo map (the workspace root `AGENTS.md`). Match words in the request against the **Products** and **Glossary** tables to pick the product. If none matches, say so in Products and repos and carry on with what you can find.
- Read the repo guide (`<repo>/AGENTS.local.md` if it exists, otherwise `<repo>/AGENTS.md`) of each repo in the product.
- Search the code for the nouns in the request and the closest thing that already exists. Note each with its file path.
- Run `git -C <repo> log --oneline -20 -- <path>` for the paths you found, to see recent or related work.
- List `.work/` for folders about the same thing (a scope, a spike, a started item).
- Stop after about 20 files read. Triage is a first look, not a spike.

## Step 4: Write triage.md

- Start from `{{ENG_HOME}}/templates/triage.md`. Write it to the folder as `triage.md` (on a re-triage, update it).
- **Questions for the requester:** only what blocks writing acceptance criteria: rules, limits, who uses it, what "done" looks like. One per line. If nothing is missing, write `- None.`
- **Route:** `delegate` when it fits work the team already owns and you can point to where it lives; `myself` when it needs a decision only the engineer can make or is small enough to do now; `undecided` when the questions must be answered first. Never rank or judge people.
- **Size:** S (a day or less), M (a few days), L (a sprint), XL (more than a sprint: suggest `/scope`).

## Step 5: Hand off

- Add a `progress.md` entry for `/triage` (copy `{{ENG_HOME}}/templates/progress.md` first if the folder has none, with the folder name as the id and the request's title).
- Reply in 3 lines or fewer: the summary, how many questions are open, the route, and the next step: send the questions, `/refine <title>` for one story, or `/scope <idea>` for an epic.
