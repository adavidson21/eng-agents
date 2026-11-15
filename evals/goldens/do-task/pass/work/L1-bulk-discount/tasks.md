# Tasks: L1 Bulk discount for large orders

Rules for every task:
- Changes at most 3 files, all in ONE repo.
- Has exactly one verify command that can be run as written.
- Can be done in one fresh session without reading other tasks.

Run each task with `/do-task <id> <n>` in a NEW session.

---

## [x] Task 1: Apply the bulk discount

- Repo: `sample-api`
- Covers: AC-1, AC-2, AC-3
- Files:
  - `sample-api/tests/Orders.Tests/OrderTotalsTests.cs` (changed)
  - `sample-api/src/Orders/PricingOptions.cs` (changed)
  - `sample-api/src/Orders/OrderTotals.cs` (changed)
- Pattern to follow: `sample-api/src/Orders/OrderTotals.cs`
- Human interface: `OrderTotals.Calculate` returns the discounted total (no UI; proven by the unit tests)
- Steps:
  1. Add tests for 9, 10 and 12 items, with expected values computed from `PricingOptions`.
  2. Add `BulkDiscountMinItems` and `BulkDiscountRate` to `PricingOptions`.
  3. Apply the discount in `Calculate` before rounding.
- Verify: `dotnet test sample-api/tests/Orders.Tests/Orders.Tests.csproj --filter "FullyQualifiedName~OrderTotalsTests"`
- Done when: the new tests pass and no other tests fail

---

## Coverage check

| Acceptance criterion | Covered by tasks |
|---|---|
| AC-1 | 1 |
| AC-2 | 1 |
| AC-3 | 1 |
