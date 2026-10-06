# Field guide

A short overview of how eng-agents works. For setup, use the onboarding guides:

- [Personal onboarding](onboarding-personal.md): fill in your `personal/` folder
- [Company onboarding](onboarding-company.md): set up the work PC

You run slash commands, approve specs and plans by editing one line, and always push yourself.

## Layers

```mermaid
flowchart LR
  C["Core<br/>core/ in eng-agents"] --> I["install.ps1"]
  P["Personal<br/>personal/ in your copy"] --> I
  W["Company<br/>work PC only"] --> I
  I --> O["opencode config"]
```

| Layer | What | Lives in |
|---|---|---|
| Core | The pipeline: agents, commands, templates, permissions | `core/` in eng-agents |
| Personal | Your preferences: tone, code taste, extra commands | `personal/` in your copy |
| Company | Anything naming your employer: repo map, repo guides, ADO settings | Work PC only |

Higher layers win. eng-agents is the shared base, your copy (eng-agents-personal) is the base plus `personal/`, and the work PC clones your copy.

## A feature at work

| You run | Agent | Your part |
|---|---|---|
| `/start 12345 feature` | planner | Confirm which repos |
| `/spec 12345` | planner | **Gate:** answer questions, approve `spec.md` |
| `/plan 12345` | planner | **Gate:** approve `plan.md` |
| `/tasks 12345` | planner | Skim task sizes |
| `/do-task 12345 1` | implementer | Approve the commit. New session per task. |
| `/review 12345` | reviewer | **Gate:** fix or accept findings |
| `/pr 12345` | writer | Push and open the PR |

Bugs skip spec, plan and tasks (`/bug` instead). `/status` tells you where you left off.

## What lives where

| eng-agents | Your copy | Work PC |
|---|---|---|
| `core/` | Everything in eng-agents | Company overlay and ADO config |
| `personal/TODO.md`, `company/TODO.md` | `personal/AGENTS.md` | `C:\src\work\AGENTS.md` (repo map) |
| `docs/`, `install.ps1` | `personal/commands/` | An `AGENTS.md` in each repo |

## Phases

| | Phase | |
|---|---|---|
| 0 | Build and personalize | Done |
| 1 | Practice run | Done |
| 2 | Fold fixes into Core | Done |
| 3 | **Set up the work PC** ([Company onboarding](onboarding-company.md)), then smoke test one small bug | **You are here** |
| 4 | Use it on real work for a few weeks, every lane at least once | |
| 5 | Roll out: teammates copy eng-agents and fill in their own Personal and Company layers | |

## Where does a fix go?

| If it... | Put it in |
|---|---|
| Names something at your company | Work PC (overlay or repo guide) |
| Is just your preference | `personal/` in your copy |
| Would help anyone | `core/` in eng-agents, then merge into your copy |
