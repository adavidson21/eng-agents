---
description: "Start a work item: fetch or describe it, create its .work folder, pick repos, create branches (and a brief with --brief). Usage: /start <id|owner/repo#n|new> [feature|bug|quick] [repo folder or ADO connection] [--brief] [--no-baseline] [auto]"
agent: planner
---

Start work item **$1** in lane **$2**. Optional third argument (where to fetch it from): **$3**

All arguments: **$ARGUMENTS**

Follow these steps in order. Do not skip any step, except the ones marked "only when" that do not apply.

**Auto mode.** If any argument is `auto`, Workshop's autopilot is running this for a local item that is already described (a story from an approved breakdown, or a product's trial run) and nobody is watching. `auto` is never the lane or the third argument. Ask nothing:
- `$1` must be a local id (`L<n>`). If not, say `Needs you: /start runs on its own only for local items.` and stop.
- Step 5: if `workitem.md` has a `- Repos:` line, those repos are the list (in that order, shared repos first); do not show the list or ask. Otherwise pick from the product and the repo map as usual and keep your best list. If you cannot settle on a repo, say `Needs you: pick the repos for $1.` and stop.
- Step 7: when the base cannot be found, use `origin/main`, else `origin/master`, else say `Needs you: which branch should $1 start from?` and stop.
- Anything else that would ask: take your recommended answer, write it under Notes in the `progress.md` entry, and keep going.

## Step 1: Check the arguments

- `$1` is one of:
  - a number: a work item in ADO.
  - a GitHub issue, `owner/repo#<number>` (for example `acme/web#12`): it is fetched into a new local work item (Step 3c). A bare `#12` is a GitHub issue too; then the third argument must be the repo folder it belongs to.
  - a local id, `L` and a number (for example `L12`): work with no tracker item, already described. Workshop's Builds creates its folder before it runs `/start`.
  - `new`: work with no tracker item that is not described yet.
- The lane is optional. If `$2` is `feature`, `bug` or `quick`, that is the lane. Otherwise there is no lane argument: every argument after `$1` moves up one place (what this command calls the third argument is `$2`), and Step 4 takes the lane from the work item's type: `bug` if the type is Bug, otherwise `feature`. `quick` is never inferred; the engineer types it. `quick` is the small lane: one repo, at most 3 tasks, no schema or API contract change (see `/quick`).
- For `new` with no lane, ask for the lane with the description in Step 3a (`feature`, `bug` or `quick`; recommend `feature`).
- If `$1` is wrong, stop and reply: `Usage: /start <id|owner/repo#n|new> [feature|bug|quick] [repo folder or ADO connection] [--brief] [--no-baseline]`.
- `--no-baseline` is optional and can come anywhere after `$1`. If any argument is `--no-baseline`, remember it: Step 7b is skipped. Like `--brief`, it is never the third argument.
- `--brief` is optional and can come anywhere after `$1`. Only with `--brief` does Step 8b write the brief; without it Step 8b is skipped. `--brief` is never the third argument. (`--cold`, from older versions, is accepted and changes nothing: no brief is the default.)
- `$3` is optional and only for a number or a bare `#<number>`. For `#<number>` it is the repo folder whose GitHub remote holds the issue. It is a repo folder in the workspace or an ADO connection name. It tells the script which ADO server or collection holds the work item. If the third argument above is empty, there is none.

## Step 2: Check for existing work

- List the `.work/` folder. If `.work/` does not exist, that is fine: Step 3a or 3b creates it.
- If `$1` is a local id: find the folder starting with `$1-`.
  - If there is none, stop and say: "There is no `.work/$1-*` folder. Use `/start new $2` to describe the work."
  - If it has a `repos.md`, it is already started: stop and suggest `/status $1`.
  - Otherwise use that folder, skip Steps 3a and 3b, and go to Step 4.
- If `$1` is a number and a folder starting with `$1-` already exists, stop. Tell the engineer it exists and suggest `/status $1`.
- If `$1` is a GitHub issue, go to Step 3c: its script finds an existing folder for that issue.

## Step 3a: Describe new local work (only when `$1` is `new`)

- Ask the engineer, in one message: "What is the work? Give a short title, then describe it: what should change and why. For a bug, also the steps to reproduce it." If no lane was given, add: "Which lane: feature, bug or quick? (Recommended: feature.)" Wait for the answer.
- Pick a title of at most 10 words from the answer. The type is `Bug` if `$2` is `bug`, otherwise `Feature`.
- Run exactly this command, with the title in place of `<title>`:

```
{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/work/New-LocalWorkItem.ps1" -WorkRoot ".work" -Title "<title>" -Type <Feature or Bug>
```

- The last line of output is the new folder path. Its name starts with the new local id (for example `L3-`). Use that id in place of `$1` from here on.
- Open `workitem.md` in the new folder and replace `<describe the work here>` with the engineer's description in their words. For a bug, put their repro steps under "Repro steps". Do not add requirements they did not give.
- Go to Step 4.

## Step 3b: Get the work item (only when `$1` is a number)

If there is no third argument, run exactly this command:

```
{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/ado/Get-WorkItem.ps1" -Id $1 -WorkRoot ".work" -Parents -IncludeComments
```

If there is a third argument, run exactly this command instead:

```
{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/ado/Get-WorkItem.ps1" -Id $1 -WorkRoot ".work" -From "$3" -Parents -IncludeComments
```

- `-Parents` adds the parent Feature and Epic to `workitem.md`. `-IncludeComments` adds the comments. If either cannot be fetched, the script still succeeds and says so in `workitem.md`. That is fine: the brief says "unknown".

- If it succeeds, the last line of output is the new folder path. Remember it.
- If the error contains `AMBIGUOUS:` or `UNKNOWN:`, the script could not tell which ADO connection to use. Show the engineer the connection names from the error and ask: "Which ADO connection (or which repo folder) is work item $1 in?" Run the second command above, with `$3` replaced by their answer.
- If it fails for any other reason (for example ADO is not set up), show the engineer the error in one line, then ask in one message: "Paste the work item's title, description, and acceptance criteria (and repro steps for a bug) here." Wait. When they answer, run:

```
{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/ado/Get-WorkItem.ps1" -Id $1 -WorkRoot ".work" -Title "<the title they pasted>"
```

  This creates the folder with an empty `workitem.md`. Fill it in yourself from their answer: replace each `<...>` placeholder with what they gave, in their words, or `None provided`. Do not add requirements they did not give. Do not ask them to edit the file.

## Step 3c: Get the GitHub issue (only when `$1` is a GitHub issue)

For `owner/repo#<number>`, run exactly this command:

```
{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/github/Get-GitHubIssue.ps1" -Id "$1" -WorkRoot ".work" -IncludeComments
```

For a bare `#<number>`, add `-From "$3"` at the end.

- It makes a local work item (`L<n>-<name>`) from the issue. `workitem.md` keeps the issue as `- GitHub: owner/repo#<number>` and its link. Use the new local id (the folder name before the first `-`) in place of `$1` from here on, and tell the engineer: "GitHub issue $1 is local work item `L<n>`."
- If it succeeds, the last line of output is the new folder path. Remember it.
- If the first line starts with `ALREADY:`, the issue is already started: stop and suggest `/status <the L id in the folder name>`.
- If the error contains `NOTOKEN:`, tell the engineer the line (it says how to save a GitHub token) and stop.
- If the error contains `BADID:` or `NOTFOUND:`, show it in one line and stop.
- If it fails for any other reason, show the error in one line, then do Step 3a instead (describe it as local work), using the issue's title as the title.

## Step 4: Read the work item

- Read `workitem.md` in the new folder.
- If no lane was given, take it from the type now: `bug` if the type is Bug, otherwise `feature`. Say which lane you picked in Step 9.
- If a lane was given and the type is Bug but the lane is `feature` or `quick` (or the other way around), ask the engineer which lane is correct. Use their answer as the lane.

## Step 5: Choose repos

- List the repo folders in the workspace root (folders with a `.git` folder).
- If there are none, stop and tell the engineer: "There are no repos in this workspace yet. Add one (Workshop Settings > Repos, or `git clone <url>` in the workspace folder), then run `/start $1 $2` again." The work item folder stays, so nothing is lost.
- If there is exactly one repo, use it. Skip the rest of this step's matching, but still show it and ask in the last bullet.
- Read the repo map (the workspace root `AGENTS.md`). If there is none, choose from the folder names and the work item, and say the repo map is missing.
- Match words in the work item against the repo map's **Products** and **Glossary** tables. Pick the product first, then use that product's repo table and change order.
- If no product matches, use the "Which repos for which kind of work" table. If that does not settle it, ask the engineer. Do not guess.
- Decide which repos this work item needs. Shared repos go first.
- Show the engineer a short list: repo folder and one-line reason for each. Ask: "Is this the right list?" Wait for the answer and apply any changes.

## Step 6: Write repos.md

- Copy `{{ENG_HOME}}/templates/repos.md` into the work folder as `repos.md` and fill it in.
- Lane is the lane from Step 4.
- Branch name is `dev/<lane>/<folder name without the .work/ part>`, with `feature` in place of `quick` (a quick item is a small feature). For example, folder `.work/12345-export-retry` in lane `feature` gives `dev/feature/12345-export-retry`.

## Step 7: Create branches

For each repo in `repos.md`, in order:

1. Run `git -C <repo> status --porcelain`. Any output means the repo has uncommitted changes: it is **busy**.
2. Run `git -C <repo> branch --show-current`. A `dev/` branch belongs to another work item, even with no uncommitted changes: the repo is **busy**. **Never switch or stash a busy repo.** Ask nothing: a busy repo gets a worktree in step 4.
3. Find the base branch (the repo's main line, which is not always called `main`):
   - Run `git -C <repo> remote`.
   - **If it prints `origin`:** run `git -C <repo> fetch origin`, then `git -C <repo> rev-parse --abbrev-ref origin/HEAD`. If that prints `origin/<name>`, the base is exactly what it printed. If it fails, run `git -C <repo> remote set-head origin --auto` and try once more. If it still fails, the base is `origin/main` if `git -C <repo> rev-parse --verify --quiet origin/main` prints a hash, else `origin/master` if that prints one, else ask the engineer which branch to start from.
   - **If it prints nothing** (a repo with no remote): the base is `main` if `git -C <repo> rev-parse --verify --quiet main` prints a hash, else `master` if that prints one, else the current branch if it does not start with `dev/`, else ask the engineer.
   - Write the base in the repo's **Base** column in `repos.md`.
4. Make the branch. Read `worktrees` in the pipeline guide's Factory settings (default `always`): with `always`, every repo is treated as **busy** here, so each build gets its own worktree and two builds never share a folder.
   - **Not busy:** run `git -C <repo> checkout -b <branch> <base>`. Leave the repo's **Path** empty.
   - **Busy:** run exactly `{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/work/New-Worktree.ps1" -Workspace "." -Repo "<repo>" -Folder "<work folder name without .work/>" -Branch "<branch>" -Base "<base>"`. Its last line is the worktree path (`.worktrees/<folder>/<repo>`): write it in the repo's **Path** column in `repos.md`. From here on, everything for this repo runs there (`{{ENG_HOME}}/guides/pipeline.md`, Where the work happens). If it fails, show the error in one line, skip this repo and tell the engineer.

## Step 7b: Record the test baseline (skip with `--no-baseline`)

`/do-task` runs each repo's full unit tests before it commits. This baseline tells it which failures were already there before this work item, so it does not chase them.

- Copy `{{ENG_HOME}}/templates/baseline.md` into the work folder as `baseline.md`.
- For each repo in `repos.md` that has its branch (in its Path when it has one): read its repo guide's Commands table. If it has a **Pre-commit check** row, run that command; otherwise run the **All unit tests** row. If it has neither, write `no command` for that repo.
- Write one row per repo: the command, `PASS` or `FAIL`, and the names of the failing tests (at most 20; if more, write the count). Paste nothing else.
- With the Tandem tools, `tandem_checks_run` (repo, item, kind `precommit`, `baseline: true`) runs it and writes the row for you; skip the copy and the row writing.
- Run each command once. If it cannot run at all (for example a build error on the base branch), write `could not run` and the first error line.
- This step never blocks `/start`. If it fails, say so in one line and go on.
- **Regression baseline.** If `regression` is on (Factory settings) and a repo's guide has a `## Regression tests` table, run `Test-Suite.ps1` once for that repo with `-Name before` (the command is in `/review` Step 3), so the review never blames this item for a test that already failed. It never blocks `/start`.
- **UI baseline.** If `uiChecks` is on (Factory settings) and a repo's guide has a `## UI checks` table, run `Test-Ui.ps1` once for that repo with `-Name before` (the command is in `/review` Step 3b), so the review can show before and after. It never blocks `/start`.

## Step 8: Start the log

- Copy `{{ENG_HOME}}/templates/progress.md` into the work folder as `progress.md`. Fill in the header and add the first entry for `/start`.

## Step 8b: Write the brief (only with `--brief`)

Skip this step unless `--brief` was given. Otherwise write a short brief, so the engineer does not start from a blank screen. Keep it light: this step reads no file contents in any repo.

- Copy `{{ENG_HOME}}/templates/brief.md` into the work folder as `brief.md`.
- Fill it in from `workitem.md` and `repos.md` only:
  - **Goal:** one sentence from the title and description.
  - **Done means:** each acceptance criterion as a `- [ ]` line, in the work item's words. If there are none, write "None provided".
  - **Where it fits:** the Feature and Epic from the "Parents" section of `workitem.md`. In this team Epics are versions, Features are the smallest usable deliverable, and Stories build Features. If there is no "Parents" section, or it says the parents could not be fetched, write "Parents unknown". For local work, write "None".
  - **Recent talk:** the last 5 comments from the "Comments" section, one line each. If there are none, write "No comments".
  - **Repos and branch:** the repo, branch and base of each row in `repos.md`.
- **Likely files:** pick 2 to 4 keywords from the title (skip filler words). For each repo in `repos.md`, run only these two commands, once per keyword:
  1. `git -C <repo> ls-files "*<keyword>*"` (file names only).
  2. `git -C <repo> log --oneline -n 20 -i --grep "<keyword>" --name-only` (recent commit messages and the files they touched).
  List at most 10 paths, most matches first, each with why it matched. Do not open or read any of these files. They are guesses, and the brief says so. If nothing matches, write "No matches".
- **First tiny step:** usually "Run `/spec $1`" (or "Run `/bug $1`" for a bug, "Run `/quick $1`" for the quick lane). If the work item leaves something important open (no acceptance criteria, or a contradiction), write the one concrete question to answer first instead.
- Do not add requirements the work item does not give.
- If this step fails, say so in one line and go on. The brief is a help, not a gate.

## Step 9: Tell the engineer what is next

Reply with:
- The folder path.
- The repos and branches created, which ones got a worktree (and why: uncommitted changes or another item's branch), and any that were skipped.
- If a brief was written: its path, and its Goal and First tiny step lines. Do not print the whole brief.
- The next command: `/spec $1` for a feature, `/bug $1` for a bug, or `/quick $1` for the quick lane.
