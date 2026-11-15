# Bug: L2 Total crashes for an order with no lines

Status: DRAFT
Draft-hash: STAMP

## Symptom

- Expected: 0
- Actual: ArgumentNullException
- Repro steps:
  1. `new Order { Id = "o-1" }`
  2. `OrderTotals.Calculate(order)`

## Code path

1. `sample-api/src/Orders/OrderTotals.cs` `Calculate`
2. `sample-api/src/Orders/OrderTotals.cs` `Subtotal`: `order.Lines!.Sum(...)` with `Lines` null

## Root cause

`Subtotal` calls `Sum` on a null `Lines`. **Confidence:** High

## Fix approach

Treat null `Lines` as empty in `Subtotal`.

## Tasks

1. Test: an order with no lines has a total of 0
2. Treat null Lines as empty

## Risks

- None
