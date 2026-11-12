---
description: "Investigate a question or an ask without changing code, write findings.md and a shareable brief.html. Usage: /spike <id or topic> [--for business|engineering|leadership]"
agent: investigator
---

Run a spike on: **$ARGUMENTS**

## Step 1: Pick the folder and the lens

- If `--for <lens>` is in the arguments, take it out and remember it as the **default lens** (`business`, `engineering` or `leadership`). Otherwise the default lens is `engineering`, or `leadership` when the ask came from an executive (CEO, VP, a director).
- If `$1` is a work item id (a number, or a local id like `L12`) and a folder in `.work/` starts with `$1-`, use that folder.
- Otherwise create a new folder `.work/spike-<short-name>/`, where `<short-name>` is 3 to 5 lowercase words from the topic joined with hyphens.

## Step 2: Frame the question

- Keep the ask in the asker's own words. Vague asks ("how hard would it be to add X?") are normal: write what you understood it to mean and the decision it supports.
- Ask the engineer ONE question only if a wrong reading would send the whole investigation the wrong way. Otherwise write your reading as an assumption and go on. Wait if you asked.

## Step 3: Investigate

- Read the repo map and the `AGENTS.md` of each repo you look at. Read the product note of each product the ask touches (see Product notes).
- Read code, git history, and docs. Run builds or tests only if they answer a specific question.
- Do not change any code.
- Keep a list of facts (Confirmed) and beliefs (Suspected) with evidence, and a list of every file, work item and doc you used (for Sources).
- Stop when you can answer the question, or after about 25 files read, whichever comes first. If you hit the limit, report what you have.

## Step 4: Write findings.md

- Start from `{{ENG_HOME}}/templates/findings.md`. Write it to the folder as `findings.md`. Fill every header line; set `Default lens:` to the default lens from Step 1.
- One investigation, three readers. Write a `### For business`, `### For engineering` and `### For leadership` block where the template has them; leave a block out when that reader has nothing to gain there.
  - **Business:** what customers and the business get, rough timing, team time. No file paths, class names or jargon.
  - **Engineering:** the approach, evidence with `file:line`, options table, risks.
  - **Leadership:** the recommendation, the tradeoff, and the one decision needed.
- Every estimate is a range with a confidence level, never a single number. `Questions for the requester` always has at least one question.
- Give 2 or 3 options when there is a real choice. Recommend one and give your confidence.

## Step 5: Export the brief

Run:

`{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/briefs/Export-Brief.ps1" -Path ".work/<folder>/findings.md"`

It writes `brief.html` next to `findings.md`: one self-contained page (no web requests) with a Business / Engineering / Leadership switch that opens on the default lens. It can be emailed, posted in Teams or printed to PDF. Re-run it after anyone edits `findings.md`.

## Step 6: Hand off

- If the folder has a `progress.md`, add an entry for `/spike`.
- Give the engineer the short answer and recommendation in 3 lines or fewer, the path to `brief.html`, and the next step from `findings.md`.
