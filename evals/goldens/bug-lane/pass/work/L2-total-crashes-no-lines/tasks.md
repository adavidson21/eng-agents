# Tasks: L2

## [ ] Task 1: Test an order with no lines

- Repo: `sample-api`
- Files:
  - `sample-api/tests/Orders.Tests/OrderTotalsTests.cs` (changed)
- Human interface: `OrderTotals.Calculate` on a new order
- Verify: `dotnet test sample-api/tests/Orders.Tests/Orders.Tests.csproj --filter "FullyQualifiedName~OrderTotalsTests"`
- Done when: the new test FAILS, showing the bug.

---

## [ ] Task 2: Treat null Lines as empty

- Repo: `sample-api`
- Files:
  - `sample-api/src/Orders/OrderTotals.cs` (changed)
- Human interface: `OrderTotals.Calculate` on a new order
- Verify: `dotnet test sample-api/tests/Orders.Tests/Orders.Tests.csproj --filter "FullyQualifiedName~OrderTotalsTests"`
- Done when: the test from Task 1 now passes and no other tests fail.
