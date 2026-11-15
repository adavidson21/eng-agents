# Review: L1 Bulk discount for large orders

Verdict: CHANGES NEEDED

## Test results

| Repo | Command | Result |
|---|---|---|
| sample-api | `dotnet test sample-api/tests/Orders.Tests/Orders.Tests.csproj` | PASS |

## Pass 1: Spec compliance

| Criterion | Status | Evidence |
|---|---|---|
| AC-1 | Met | `Calculate_TenItems_GetsBulkDiscount` |
| AC-2 | Met | `Calculate_NineItems_NoDiscount` |
| AC-3 | Met | `PricingOptions.cs` |

## Pass 2: Code quality

| # | Severity | Category | Location | Problem | Suggested fix |
|---|---|---|---|---|---|
| 1 | Blocker | style | `sample-api/src/Orders/OrderTotals.cs:9` | I would name this differently | rename |
