# Personal onboarding

Create your own fork of eng-agents and fill in its `personal/` folder: how *you* like the agents to work. One file is required, the rest is optional. No company names anywhere in it.

You need git, [opencode](https://opencode.ai), and PowerShell (built in on Windows; install PowerShell 7 as `pwsh` on Mac or Linux).

## Files

| File | | What it does |
|---|---|---|
| `personal/AGENTS.md` | **Required** | Your house rules, added to every session after Core |
| `personal/commands/*.md` | Optional | Extra slash commands |
| `personal/agents/*.md` | Optional | Replace a Core agent (for example to pick a model) |
| `personal/templates/*.md` | Optional | Replace a Core template |
| `personal/opencode.json` | Optional | Permission tweaks |

Leave `personal/TODO.md` alone. It is never installed.

## 0. Create your fork (required)

Fork eng-agents on GitHub (keep it private), then clone it and link it to the base so you can pull updates:

```bash
git clone <your fork url> eng-agents
cd eng-agents
git remote add upstream <eng-agents url>
```

If you own eng-agents you cannot fork it into the same account. Create an empty private repo instead and push eng-agents into it.

To pick up base updates later: `git fetch upstream`, `git merge upstream/main`, `git push`.

## 1. Write your rules (required)

`personal/AGENTS.md`. Short bullets under a few headings. Start from this and edit:

```markdown
## How to talk to me
- Be concise and direct. Short answers unless I ask for detail.
- If you are not confident, say so before answering.
- Ask a clarifying question instead of guessing.

## Code preferences
- Prefer clear names over comments. Comment only to explain why.
- Prefer small methods with early returns over deep nesting.
- Do not add NuGet or npm packages without asking me first.

## Workflow
- Commit after each passing task. I approve each commit.
- A task changes at most 3 files.

## Writing (docs and PR text)
- PR descriptions stay under 10 lines.
- Use a professional, neutral tone in anything a teammate will read.
```

More ideas:

- **Talk:** punctuation or words to avoid (for example em dashes). "End every reply with the exact next command to run."
- **Code:** "Match the existing style of the file over your own preference." "Use the repo's existing test helpers before writing new ones."
- **Workflow:** "Never commit. Stage the files and tell me the commit message." "Show me the failing test output before you implement."
- **Writing:** "Write PR text for a reviewer who has not read the work item."

Write rules as instructions ("Never...", "Prefer..."), one idea per bullet. Text inside `<!-- -->` is stripped on install, so use it for notes to yourself.

## 2. Add commands (optional)

`personal/commands/<name>.md`. The file name becomes the command. A same-named file replaces the Core command.

```markdown
---
description: "Summarize this week's work. Usage: /weekly"
agent: planner
---

Summarize this week's work. Do not change any files.

1. Read every `.work/*/progress.md` entry from the last 7 days.
2. Reply with one line per work item: id, short name, what got done, what is next.
```

Ideas: `/weekly` (above), `/standup` (Yesterday / Today / Blockers from the progress logs), `/handoff <id>` to summarize an item for a teammate.

Use `agent: planner` for read-only commands so they cannot change code.

## 3. Override an agent or template (optional)

`personal/agents/<name>.md` or `personal/templates/<name>.md`. Copy the Core file first, then edit your fork. Example: pick a model for the implementer by adding a `model:` line to its front matter.

```bash
cp core/agents/implementer.md personal/agents/implementer.md
```

> An override replaces the whole file, so you stop getting Core updates for it. Prefer a rule in `AGENTS.md` when one will do.

## 4. Tweak permissions (optional)

`personal/opencode.json`. Only the keys you add. They merge over Core.

```json
{
  "permission": {
    "bash": {
      "npx playwright show-report*": "allow"
    }
  }
}
```

> Not confirmed: each pipeline agent file repeats its own permission rules, so a global entry may not apply inside those agents. Test it. To change what one agent may do, override that agent (step 3).

## 5. Install and check (required)

```bash
pwsh ./install.ps1 -DryRun
pwsh ./install.ps1
```

- The `Layers :` line lists **Personal**
- No warning about `TODO(you)`
- In opencode, ask: "What does the Personal section of your instructions say?"

## 6. Commit to your fork (required)

```bash
git add personal
git commit -m "Update personal layer"
git push
```

Your fork only. Never send `personal/` to eng-agents.

## When to come back

- The model keeps ignoring a preference: make the rule more explicit.
- After your first week at work: loosen the task size or commit rules if you trust the model more.
