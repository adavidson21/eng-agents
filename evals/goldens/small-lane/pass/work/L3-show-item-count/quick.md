# Quick plan: L3 Show how many items an order has

Status: DRAFT
Draft-hash: STAMP

## Goal

Expose the item count of an order.

## Current behavior

`sample-api/src/Orders/OrderTotals.cs` has `Subtotal` but no item count.

## Acceptance criteria

- **AC-1:** Given an order with lines, when `ItemCount` is called, then it returns the sum of the quantities.
- **AC-2:** Given an order with no lines, when `ItemCount` is called, then it returns 0.

## Assumptions

- Null `Lines` counts as no lines.

## Files

Pattern to follow: `sample-api/src/Orders/OrderTotals.cs` (`Subtotal`)

| File | New or changed | What changes |
|---|---|---|
| `sample-api/src/Orders/OrderTotals.cs` | changed | Add `ItemCount` |
| `sample-api/tests/Orders.Tests/OrderTotalsTests.cs` | changed | Two tests |

## Why this fits the quick lane

- One repo: sample-api, not a shared repo
- Tasks: 1
- No schema, migration, or public API contract change

## Open questions

- None
