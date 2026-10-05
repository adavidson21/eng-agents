# Personal layer template

Your personal layer holds how **you** like to work. It sits on top of Core and under your Company overlay.

## Set it up in your fork

```powershell
Copy-Item personal-template personal -Recurse
Remove-Item personal\README.md
```

Then:

1. Edit `personal/AGENTS.md`. Keep, change, or delete each SAMPLE line, and fill in or delete each `TODO(you)`.
2. Keep `personal/commands/standup.md` if you want `/standup`, or delete it.
3. Work through `personal/CHECKLIST.md` to track your own setup.
4. Commit `personal/` to **your fork only**. Never open a pull request that includes it.

## What you can put in personal/

| Add | Effect |
|---|---|
| `AGENTS.md` | Appended after the Core section in every session. |
| `commands/<name>.md` | Adds a command, or replaces a Core command with the same name. |
| `agents/<name>.md` | Adds an agent, or replaces a Core agent with the same name. |
| `templates/<name>.md` | Replaces a Core template with the same name. |
| `opencode.json` | Permission entries merged over Core. |

Files at the top of `personal/` other than `AGENTS.md` and `opencode.json` (like `CHECKLIST.md`) are not installed.

## Rules

- No company content. That belongs in the Company overlay on your work PC.
- The base repo never contains a `personal/` folder, so pulling updates from it never conflicts with yours.
