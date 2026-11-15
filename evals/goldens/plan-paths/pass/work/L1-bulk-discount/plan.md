# Plan: L1 Bulk discount for large orders

Status: DRAFT
Draft-hash: STAMP

## Approach

Add two constants to `PricingOptions` and apply the discount in `OrderTotals.Calculate` before rounding. A small private helper counts items. Tests go in the existing test class.

## Changes by repo

### sample-api

Pattern to follow: `sample-api/src/Orders/OrderTotals.cs` (`Subtotal` shows how rules read orders)

| File | New or changed | What changes |
|---|---|---|
| `sample-api/src/Orders/PricingOptions.cs` | changed | Add `BulkDiscountMinItems = 10` and `BulkDiscountRate = 0.05m` |
| `sample-api/src/Orders/OrderTotals.cs` | changed | Apply the discount when the item count reaches the threshold |
| `sample-api/tests/Orders.Tests/OrderTotalsTests.cs` | changed | Tests at 9, 10 and 12 items |

## Test plan

| Acceptance criterion | Test type | Test location | What it checks |
|---|---|---|---|
| AC-1 | xUnit | `sample-api/tests/Orders.Tests/OrderTotalsTests.cs` | 10 and 12 items get 5% off |
| AC-2 | xUnit | `sample-api/tests/Orders.Tests/OrderTotalsTests.cs` | 9 items: no discount |
| AC-3 | xUnit | `sample-api/tests/Orders.Tests/OrderTotalsTests.cs` | Expected values computed from `PricingOptions` |

## Risks

- None

## Out of scope

- Null `Lines` (separate bug).
