# PR text: <id>

One section per repo. Copy each section into your git host (Azure DevOps, GitHub, ...) when you open the PR.

## Checks

- Builds: <clean, or what failed>
- Unit tests: <n passed, n new>
- Regression tests: <n passed, n new covering AC-1, AC-2, n flaky (where), or none in this repo>
- Docs: <files updated, or no doc change needed>
- Clean up: <leftovers removed, or none>
- Review: <READY, with n Should fix and n Nit left>

---

## <repo-folder>

Branch: `<branch>` -> `<target: the base from repos.md without origin/>`

**Title:** <short summary, under 70 characters>

**Description:**

<One or two sentences: why this change, then what changed.>

- <key change>
- <key change>

Testing: <how to test it, then the command(s) run and the result, in one or two lines>

<Only when the change touches UI:>
Screenshots: <add before and after screenshots>

<Linked ADO work item: AB#<number>. GitHub issue: Closes owner/repo#<n>. Local item: its id, for example L12.>
