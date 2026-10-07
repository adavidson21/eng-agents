# company/

Placeholder for the **Company layer**: anything that names your employer, its code, or its systems. `.gitignore` blocks anything dropped in here except the tracked placeholders. The real files live on the work PC only.

| Tracked file | What it is |
|---|---|
| `repo-map.template.md` | Blank repo map to fill in: products to repos, glossary (work item terms to code names), dependencies, change order. Copy it to `C:\src\work\AGENTS.md` and fill it in there. |

The overlay at `%USERPROFILE%\.config\eng-agents\overlay\` can hold `AGENTS.md`, `commands\`, `agents\`, `templates\`, `permissions\` (shell commands for every agent), and `opencode.json`. `config.json` (ADO connections) and `memory.md` (written by `/memory -global`) sit next to it in `%USERPROFILE%\.config\eng-agents\`.

**How to set it up:** [docs/onboarding-company.md](../docs/onboarding-company.md)
