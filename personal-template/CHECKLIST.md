# My setup checklist

Your own progress, tracked in your fork. Check items off and commit as you go.

## Personal layer

- [ ] **`personal/AGENTS.md`**: every SAMPLE line kept, changed, or deleted. Every `TODO(you)` filled in or deleted.
- [ ] **`personal/commands/`**: kept only the commands you want (for example `/standup`).

## Work PC setup (Company layer, never committed)

Full commands are in `docs/setup-at-work.md`.

- [ ] Clone your fork to `C:\tools\eng-agents`
- [ ] Confirm the opencode config folder path
- [ ] Copy `workspace-template\company-overlay` to `%USERPROFILE%\.config\eng-agents\overlay\` and fill in its `AGENTS.md`
- [ ] Create a PAT (Work Items Read, Code Read) and set `ADO_PAT`
- [ ] Create and fill in `%USERPROFILE%\.config\eng-agents\config.json`
- [ ] Run `install.ps1 -DryRun`, then `install.ps1`
- [ ] Test `Get-WorkItem.ps1` against a real work item
- [ ] Clone all repos flat into `C:\src\work`
- [ ] Write `C:\src\work\AGENTS.md` (repo map) from the template
- [ ] `/onboard-repo` each repo, shared repos first, and review each generated `AGENTS.md`
- [ ] Day-one verification checks 1 to 7
- [ ] Smoke test: one small bug through the bug lane

## Feeding back

- [ ] Generic fixes (anything that would help anyone) sent to the base repo, not kept in your fork
- [ ] Company-specific fixes added to your Company overlay on the work PC
