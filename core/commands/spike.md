---
description: "Investigate a question or an ask without changing code, write findings.md and a shareable brief.html. Or diagnose an error log: probable root cause, why, and a fix, configuration first. Usage: /spike <id or topic> [--for business|engineering|leadership] [--timebox 1h|2h|4h|1d], or /spike spike-<name> --log"
agent: investigator
---

Run a spike on: **$ARGUMENTS**

## Step 1: Pick the folder and the lens

- If `--for <lens>` is in the arguments, take it out and remember it as the **default lens** (`business`, `engineering` or `leadership`). Otherwise the default lens is `leadership`.
- If `--timebox <t>` is in the arguments, take it out and remember it (`1h`, `2h`, `4h` or `1d`; Builds sends it from the Investigate card). It sets how far you dig in Step 3.
- If `--log` is in the arguments, take it out: this is **log mode**. `$1` is a `spike-` folder that already has `log.md` (Builds writes it when you paste a log on Fix a bug). If the folder or its `log.md` is missing, say so in one line and stop. Follow "Log mode" at the end instead of Steps 2 to 5.
- If `$1` is a work item id (a number, or a local id like `L12`) and a folder in `.work/` starts with `$1-`, use that folder.
- If `--name <short-name>` is in the arguments (Builds sends it), take it out and remember it.
- Otherwise create a new folder `.work/spike-<short-name>/`, where `<short-name>` is the `--name` value, or else 3 to 5 lowercase words from the topic joined with hyphens.

## Step 2: First look, then gather, then aim

- Keep the ask in the asker's own words. Vague asks ("how hard would it be to add X?") are normal: write what you understood it to mean and the decision it supports.
- **First look (fast).** Read the repo map and at most 5 files or docs that the ask points to most directly. Then write `first-look.md` in the folder from `{{ENG_HOME}}/templates/first-look.md` (question mode): a quick answer, a confidence (Low or Medium) and what you will dig into. Do this before anything else in Step 3; Builds shows it on the card right away.
- **Gather.** Collect the sources the ask needs (code, git history, docs, work items, product notes) into your list of facts and sources, without writing the answer yet.
- **Aim.** If the ask is broad (it could be answered for different readers, scopes or depths, and the answer would differ), ask the engineer ONE focus question with 2 to 4 options, your recommendation first, using what you gathered to make the options concrete. Otherwise write your reading as an assumption and go on. Wait if you asked. This is the only question the spike asks.

## Step 3: Investigate

- Read the repo map and the `AGENTS.md` of each repo you look at. Read the product note of each product the ask touches (see Product notes).
- Read code, git history, and docs. Run builds or tests only if they answer a specific question.
- Do not change any code.
- Keep a list of facts (Confirmed) and beliefs (Suspected) with evidence, and a list of every file, work item and doc you used (for Sources).
- Stop when you can answer the question, or after about 25 files read, whichever comes first. If you hit the limit, report what you have.
- With a timebox, the file limit is the timebox's instead: `1h` about 10 files, `2h` about 15, `4h` about 25, `1d` about 40. When you stop at the limit, say in the Short answer that the timebox ended and what is still unknown.

## Step 4: Write findings.md

- Start from `{{ENG_HOME}}/templates/findings.md`. Write it to the folder as `findings.md`. Fill every header line; set `Default lens:` to the default lens from Step 1.
- One investigation, three readers. Write a `### For business`, `### For engineering` and `### For leadership` block where the template has them; leave a block out when that reader has nothing to gain there.
  - **Business:** what customers and the business get, rough timing, team time. No file paths, class names or jargon.
  - **Engineering:** the approach, evidence with `file:line`, options table, risks.
  - **Leadership:** the recommendation, the tradeoff, and the one decision needed.
- Every estimate is a range with a confidence level, never a single number. `Questions for the requester` lists only real open questions; write `- None.` when nothing is open.
- Give 2 or 3 options when there is a real choice. Recommend one and give your confidence.

## Step 5: Export the brief

Run:

`{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/briefs/Export-Brief.ps1" -Path ".work/<folder>/findings.md"`

It writes `brief.html` next to `findings.md`: one self-contained page (no web requests) with a Business / Engineering / Leadership switch that opens on the default lens. It can be emailed, posted in Teams or printed to PDF. Re-run it after anyone edits `findings.md`.

## Step 6: Hand off

- If the folder has a `progress.md`, add an entry for `/spike`.
- Give the engineer the short answer and recommendation in 3 lines or fewer, the path to `brief.html`, and the next step from `findings.md`.

## Log mode (an error log)

The engineer pasted an error log and wants three things: the probable root cause, why, and a solution. **Prefer a solution that changes no code**: a setting, a feature flag, an environment or pipeline variable, a timeout, a connection, data, or infrastructure. Give a code fix only when nothing else fixes the cause, and say why. Do not change any code or any configuration yourself.

### L0: First look (fast)

- Read `log.md`. Within the first few minutes, before L2, write `first-look.md` in the folder from `{{ENG_HOME}}/templates/first-look.md` (log mode): product, environment, error, first guess and a confidence (Low or Medium). Match the product from namespaces, hosts and file names against the repo map. Same secrets rule as L1: name things, never copy values. Builds shows it on the card right away.
- Ask the engineer ONE question only when the log cannot tell you something that changes where you look (most often the environment, or what changed just before). Otherwise go on.

### L1: Read the log

- Read `log.md`. Note the exception type and message, every stack frame, timestamps, the service or host, the environment, request or correlation ids, and the line just before the first error (it often names the cause).
- The log may hold secrets or personal data. Never copy a password, token, key, connection string, email address or customer data into any file you write. Name the thing instead ("the database connection string").
- If the log names no service or repo, match its namespaces, file names and messages against the repo map (the workspace root `AGENTS.md`) and its **Products** and **Glossary** tables.

### L2: Find where it happens

- Read the repo guide (`<repo>/AGENTS.local.md` if it exists, otherwise `<repo>/AGENTS.md`) of each repo the log points to, and the product note (see Product notes).
- Find the first stack frame in our code (not a framework or library) and read that method and its callers. Search the code for the exact error message when there is no stack trace.
- Run `git -C <repo> log --oneline -15 -- <those files>` to see recent changes there. A change shortly before the first timestamp is a strong lead.

### L3: Check the configuration first

- Find every setting the failing code reads: options classes, `IConfiguration` keys, environment variables, feature flags, connection names, timeouts, retry counts, URLs, certificates. Note the key names.
- Read where each one is set in the repo: `appsettings*.json`, `web.config` and its transforms, launch settings, Helm or Kubernetes values, Terraform, pipeline YAML and its variables. Compare the environment in the log with the others. Never open `.env` files, key vaults or secret stores (core rules): for a secret, a connection string or a key, compare only its key name, whether it is set, and where, never its value.
- Look for the usual config causes: a missing or empty key, a value that differs between environments, a wrong URL or host, a timeout shorter than the call takes, an expired certificate or secret (from its name and dates, never its value), a feature flag in the wrong state, a pool or size limit too small.
- Values you cannot see (portal settings, key vaults, release variables) are Suspected: say where to look and what to compare.

### L4: Decide

- State the probable root cause with Confirmed and Suspected evidence and a confidence: High (the log, the code and the config all agree), Medium (one link is Suspected), Low (several are).
- Pick the fix type in this order, taking the first that fixes the cause: **Configuration**, **Data**, **Infrastructure**, **Code**. For Configuration: the exact key, where it is set, the value to set (never a secret), how to roll it out, and the log line that should stop.
- Stop after about 25 files read (or the timebox's limit). Report what you have.

### L5: Write findings.md

- Start from `{{ENG_HOME}}/templates/diagnosis.md`. Write it to the folder as `findings.md`. Fill every header line, including `Fix type:`.
- Plain words. Every Confirmed step has its `file:line`, config key and file, commit, or command output.
- Do not export `brief.html` in log mode.

### L6: Hand off

- Add a `progress.md` entry for `/spike` (copy `{{ENG_HOME}}/templates/progress.md` first if the folder has none) with a `- Stats: mode=log fix_type=<type> confidence=<level>` line.
- Reply in 3 lines or fewer: the probable root cause, the fix type and the change, and the next step. For Configuration, Data or Infrastructure: who applies it and where, then close the spike in Builds. For Code: Fix it in Builds (or `/start new bug` with these findings).

