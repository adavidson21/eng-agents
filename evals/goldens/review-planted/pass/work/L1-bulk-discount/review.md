# Review: L1 Bulk discount for large orders

Verdict: CHANGES NEEDED

## Test results

| Repo | Command | Result |
|---|---|---|
| sample-api | `dotnet test sample-api/tests/Orders.Tests/Orders.Tests.csproj` | PASS |

## Pass 1: Spec compliance

| Criterion | Status | Evidence |
|---|---|---|
| AC-1 | Not met | `OrderTotals.cs:9` uses `>`; an order of exactly 10 items gets no discount, and no test covers 10 |
| AC-2 | Met | `Calculate_NineItems_NoDiscount` |
| AC-3 | Met | `PricingOptions.cs` |

## Pass 2: Code quality

| # | Severity | Category | Location | Problem | Suggested fix |
|---|---|---|---|---|---|
| 1 | Blocker | spec | `sample-api/src/Orders/OrderTotals.cs:9` | Uses > instead of >=, so exactly 10 items get no discount (AC-1) | Use >= and add a 10-item test |
