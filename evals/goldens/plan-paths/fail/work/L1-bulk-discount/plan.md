# Plan: L1

Status: DRAFT
Draft-hash: STAMP

## Changes by repo

### sample-api

Pattern to follow: `sample-api/src/Orders/DiscountRules.cs`

| File | New or changed | What changes |
|---|---|---|
| `sample-api/src/Orders/Discounts.cs` | changed | Add the 10-item rule with 0.05 inline |

## Test plan

| Acceptance criterion | Test type | Test location | What it checks |
|---|---|---|---|
| AC-1 | xUnit | `sample-api/tests/Orders.Tests/OrderTotalsTests.cs` | 10 items |
