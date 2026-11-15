# Tasks: L3

## [ ] Task 1: Add ItemCount

- Repo: `sample-api`
- Covers: AC-1, AC-2
- Files:
  - `sample-api/tests/Orders.Tests/OrderTotalsTests.cs` (changed)
  - `sample-api/src/Orders/OrderTotals.cs` (changed)
- Pattern to follow: `sample-api/src/Orders/OrderTotals.cs`
- Human interface: `OrderTotals.ItemCount` (proven by unit tests)
- Verify: `dotnet test sample-api/tests/Orders.Tests/Orders.Tests.csproj --filter "FullyQualifiedName~OrderTotalsTests"`
- Done when: the new tests pass and no other tests fail

---

## Coverage check

| Acceptance criterion | Covered by tasks |
|---|---|
| AC-1 | 1 |
| AC-2 | 1 |
