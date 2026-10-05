# Tasks: <id> <title>

Rules for every task:
- Changes at most 3 files, all in ONE repo.
- Has exactly one verify command that can be run as written.
- Can be done in one fresh session without reading other tasks.

Run each task with `/do-task <id> <n>` in a NEW session.

---

## [ ] Task 1: <short imperative title>

- Repo: `<repo-folder>`
- Covers: AC-1
- Files:
  - `<path/to/TestFile.cs>` (new)
  - `<path/to/File.cs>` (changed)
- Pattern to follow: `<path/to/SimilarFile.cs>`
- Steps:
  1. <concrete step>
  2. <concrete step>
- Verify: `<exact command, for example: dotnet test api-repo/tests/App.Tests/App.Tests.csproj --filter "FullyQualifiedName~ExportHandlerTests">`
- Done when: <observable result, for example "the 2 new tests pass and no other tests fail">

---

## [ ] Task 2: <short imperative title>

...

---

## Coverage check

| Acceptance criterion | Covered by tasks |
|---|---|
| AC-1 | 1, 2 |
