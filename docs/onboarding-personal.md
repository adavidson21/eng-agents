# Personal onboarding

Create your own fork of eng-agents and fill in `personal/`: how *you* like the agents to work. It lives in your fork only and never contains company names.

You need git, [opencode](https://opencode.ai), and PowerShell (built in on Windows; install PowerShell 7 as `pwsh` on Mac or Linux).

| File | | What it does |
|---|---|---|
| `personal/AGENTS.md` | **Required** | Your rules, added to every session after Core |
| `personal/commands/<name>.md` | Optional | Extra slash commands, or a replacement for a Core command |
| `personal/agents/<name>.md` | Optional | Replace a Core agent (for example to pick a model) |
| `personal/templates/<name>.md` | Optional | Replace a Core template |
| `personal/opencode.json` | Optional | Permission entries merged over Core |

`personal/TODO.md` is never installed. Leave it so merges from the base stay clean. What else you can change: [customization guide](customization.md#personal).

## 1. Create your fork

Fork eng-agents on GitHub (keep it private), clone it, and link it to the base:

```bash
git clone <your fork url> eng-agents
cd eng-agents
git remote add upstream <eng-agents url>
```

If you own eng-agents, you cannot fork it into the same account. Create an empty private repo (for example `eng-agents-personal`) and push eng-agents into it.

Pick up base updates later with `git fetch upstream`, `git merge upstream/main`, `git push`.

## 2. Write your rules

Create `personal/AGENTS.md`. Short bullets under a few headings, one idea per bullet, written as instructions. Start from this:

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

More ideas: words or punctuation to avoid; "End every reply with the exact next command to run"; "Never commit. Stage the files and tell me the commit message"; "Show me the failing test output before you implement." Rules for a single agent go under a heading like `## When you are the implementer` (examples in [personal/TODO.md](../personal/TODO.md#rules-for-one-agent)).

Text inside `<!-- -->` is stripped on install, so use it for notes to yourself.

## 3. Optional: commands, overrides, permissions

**Command.** `personal/commands/<name>.md`. The file name becomes the command. Use `agent: planner` for read-only commands so they cannot change code.

```markdown
---
description: "Summarize this week's work. Usage: /weekly"
agent: planner
---

Summarize this week's work. Do not change any files.

1. Read every `.work/*/progress.md` entry from the last 7 days.
2. Reply with one line per work item: id, short name, what got done, what is next.
```

**Agent or template override.** Copy the Core file into `personal/agents/` or `personal/templates/` and edit the copy, for example to add a `model:` line to the implementer. An override replaces the whole file, so you stop getting Core updates for it. Prefer a rule in `personal/AGENTS.md` when one will do.

```bash
cp core/agents/implementer.md personal/agents/implementer.md
```

**Permissions.** `personal/opencode.json`, only the keys you add:

```json
{
  "permission": {
    "bash": {
      "npx playwright show-report*": "allow"
    }
  }
}
```

> Not confirmed: each agent file repeats its own permission rules, so a global entry may not apply inside those agents. Test it. To change what one agent may do, override that agent.

## 4. Install and check

```bash
pwsh ./install.ps1 -DryRun
pwsh ./install.ps1
```

- The `Layers :` line lists **Personal**.
- No warning about `TODO(you)`.
- In opencode, ask: "What does the Personal section of your instructions say?"

On Windows, run `.\install.ps1` instead. Never run it with `sudo` (it refuses to run as root).

## 5. Commit to your fork

```bash
git add personal
git commit -m "Update personal layer"
git push
```

Never send `personal/` to eng-agents. Next: [Company onboarding](onboarding-company.md).
