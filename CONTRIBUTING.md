# Contributing

For changes to `core/` in eng-agents. Personal preferences belong in your fork's `personal/`; company content belongs on the work PC ([where does a change go?](docs/customization.md#where-does-a-change-go)).

## Before merging a change to Core

- [ ] It would help **anyone**. No company names, no personal preferences.
- [ ] Permission changes are made in `core/opencode.json` **and** every agent file that repeats the same tier lists.
- [ ] `Status: DRAFT` lines in the `spec`, `plan`, and `bug` templates, `Status: PAUSED` in `paused`, and `## [ ] Task N:` headings in `tasks` are unchanged (commands depend on them).
- [ ] Docs that describe the behavior are updated (`README.md`, `docs/`).
- [ ] `pwsh ./install.ps1 -DryRun` runs cleanly.
- [ ] For a notable release, tag it (`core-v2`, ...) and tell teammates to run `git fetch upstream` and `git merge upstream/main` in their forks.

Reject any pull request that includes a `personal/` folder or company content.

## Team rollout

1. Run real work items through every lane at work and fold generic fixes into Core.
2. Decide where the base repo lives for the team (GitHub, or a company ADO mirror teammates fork from).
3. Teammates fork, add a Personal layer, and set up their own Company layer.
4. Share company content only through company-hosted places, for example a team overlay or repo `AGENTS.md` files committed to company repos once the team adopts this.
