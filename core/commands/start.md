---
description: "Start a work item: fetch or describe it, create its .work folder, pick repos, create branches, write a brief. Usage: /start <id|new> <feature|bug> [repo folder or ADO connection] [--cold]"
agent: planner
---

Start work item **$1** in lane **$2**. Optional third argument (where to fetch it from): **$3**

All arguments: **$ARGUMENTS**

Follow these steps in order. Do not skip any step, except the ones marked "only when" that do not apply.

## Step 1: Check the arguments

- `$1` is one of:
  - a number: a work item in ADO.
  - a local id, `L` and a number (for example `L12`): work with no tracker item, already described. Dispatch creates its folder before it runs `/start`.
  - `new`: work with no tracker item that is not described yet.
- `$2` must be `feature` or `bug`.
- If either is wrong, stop and reply: `Usage: /start <id|new> <feature|bug> [repo folder or ADO connection] [--cold]`.
- `--cold` is optional and can come anywhere after the lane. If any argument is `--cold`, remember it: Step 8b is skipped. `--cold` is never the third argument, so if `$3` is `--cold`, there is no third argument.
- `$3` is optional and only for a number. It is a repo folder in the workspace or an ADO connection name. It tells the script which ADO server or collection holds the work item. If the third argument above is empty, there is none.

## Step 2: Check for existing work

- List the `.work/` folder. If `.work/` does not exist, that is fine: Step 3a or 3b creates it.
- If `$1` is a local id: find the folder starting with `$1-`.
  - If there is none, stop and say: "There is no `.work/$1-*` folder. Use `/start new $2` to describe the work."
  - If it has a `repos.md`, it is already started: stop and suggest `/status $1`.
  - Otherwise use that folder, skip Steps 3a and 3b, and go to Step 4.
- If `$1` is a number and a folder starting with `$1-` already exists, stop. Tell the engineer it exists and suggest `/status $1`.

## Step 3a: Describe new local work (only when `$1` is `new`)

- Ask the engineer, in one message: "What is the work? Give a short title, then describe it: what should change and why. For a bug, also the steps to reproduce it." Wait for the answer.
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

## Step 4: Read the work item

- Read `workitem.md` in the new folder.
- If the type is Bug but `$2` is `feature` (or the other way around), ask the engineer which lane is correct. Use their answer as the lane.

## Step 5: Choose repos

- List the repo folders in the workspace root (folders with a `.git` folder).
- If there are none, stop and tell the engineer: "There are no repos in this workspace yet. Add one (Dispatch: Add a repo, or `git clone <url>` in the workspace folder), then run `/start $1 $2` again." The work item folder stays, so nothing is lost.
- If there is exactly one repo, use it. Skip the rest of this step's matching, but still show it and ask in the last bullet.
- Read the repo map (the workspace root `AGENTS.md`). If there is none, choose from the folder names and the work item, and say the repo map is missing.
- Match words in the work item against the repo map's **Products** and **Glossary** tables. Pick the product first, then use that product's repo table and change order.
- If no product matches, use the "Which repos for which kind of work" table. If that does not settle it, ask the engineer. Do not guess.
- Decide which repos this work item needs. Shared repos go first.
- Show the engineer a short list: repo folder and one-line reason for each. Ask: "Is this the right list?" Wait for the answer and apply any changes.

## Step 6: Write repos.md

- Copy `{{ENG_HOME}}/templates/repos.md` into the work folder as `repos.md` and fill it in.
- Lane is the lane from Step 4.
- Branch name is `dev/<lane>/<folder name without the .work/ part>`. For example, folder `.work/12345-export-retry` in lane `feature` gives `dev/feature/12345-export-retry`.

## Step 7: Create branches

For each repo in `repos.md`, in order:

1. Run `git -C <repo> status --porcelain`. If there is any output, the repo has uncommitted changes. Skip this repo and tell the engineer.
2. Run `git -C <repo> branch --show-current`. If the repo is on any `dev/` branch, it belongs to another work item, even if there are no uncommitted changes. **Do not switch it.** Ask the engineer first: "`<repo>` is on `<branch>` for another work item. Switch it to `<new branch>` anyway, skip this repo, or use a git worktree?" Wait for the answer and do what they choose.
3. Find the base branch (the repo's main line, which is not always called `main`):
   - Run `git -C <repo> remote`.
   - **If it prints `origin`:** run `git -C <repo> fetch origin`, then `git -C <repo> rev-parse --abbrev-ref origin/HEAD`. If that prints `origin/<name>`, the base is exactly what it printed. If it fails, run `git -C <repo> remote set-head origin --auto` and try once more. If it still fails, the base is `origin/main` if `git -C <repo> rev-parse --verify --quiet origin/main` prints a hash, else `origin/master` if that prints one, else ask the engineer which branch to start from.
   - **If it prints nothing** (a repo with no remote): the base is `main` if `git -C <repo> rev-parse --verify --quiet main` prints a hash, else `master` if that prints one, else the current branch if it does not start with `dev/`, else ask the engineer.
   - Write the base in the repo's **Base** column in `repos.md`.
4. Run `git -C <repo> checkout -b <branch> <base>`.

## Step 8: Start the log

- Copy `{{ENG_HOME}}/templates/progress.md` into the work folder as `progress.md`. Fill in the header and add the first entry for `/start`.

## Step 8b: Write the brief (skip with `--cold`)

Skip this step if `--cold` was given. Otherwise write a short brief, so the engineer does not start from a blank screen. Keep it light: this step reads no file contents in any repo.

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
- **First tiny step:** usually "Run `/spec $1`" (or "Run `/bug $1`" for a bug). If the work item leaves something important open (no acceptance criteria, or a contradiction), write the one concrete question to answer first instead.
- Do not add requirements the work item does not give.
- If this step fails, say so in one line and go on. The brief is a help, not a gate.

## Step 9: Tell the engineer what is next

Reply with:
- The folder path.
- The repos and branches created, and any that were skipped.
- The brief: print `brief.md` as it is (or say it was skipped with `--cold`).
- The next command: `/spec $1` for a feature, or `/bug $1` for a bug.
