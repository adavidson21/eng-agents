# Company overlay

Copy this folder to `%USERPROFILE%\.config\eng-agents\overlay\` on your work PC, then run `install.ps1`.

It has the same shape as `core/`. Anything you put here overrides Core and Personal:

| Add a file here | Effect |
|---|---|
| `AGENTS.md` | Appended as the last section of the installed `AGENTS.md`. Company-wide rules. |
| `templates/pr.md` | Replaces the Core PR template. Use it if your team expects specific PR sections. |
| `commands/<name>.md` | Adds a command, or replaces a Core command with the same name. |
| `agents/<name>.md` | Adds an agent, or replaces a Core agent with the same name. |
| `opencode.json` | Permission entries merged over Core and Personal. |

This folder is company content. It never goes back into the eng-agents repo. This README is not installed.
