# Paused: <id> <title>

Status: PAUSED
Paused: <yyyy-mm-dd hh:mm>
Reason: <why, or "not given">

<!-- /resume changes the Status line to RESUMED and adds a "Resumed:" line. Keep every section short and concrete. -->

## Where it stands

- Lane: <feature | bug>
- Phase: <spec | plan | tasks | do-task | review | pr>
- Tasks: <done>/<total> done
- In progress: <Task N: title, or "none (paused between steps)">

## Repos

| Repo | Branch | State at pause | Last commit |
|---|---|---|---|
| <repo-folder> | <branch> | <clean, or WIP commit <sha>, or N uncommitted files> | <sha> <message> |

## Work in progress

<What is half done in the current task: which files, what works, what is left. "None" if paused between steps.>

## Waiting on

- <open question or decision, and who it is waiting on, or "nothing">

## To resume

1. `/resume <id>`
2. Then: `<exact next command>`
