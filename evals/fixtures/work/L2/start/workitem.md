# Work item L2: Total crashes for an order with no lines

- Type: Bug
- State: New
- Link: none (local work item)
- Fetched: Pasted by engineer

## Description

Pricing a brand-new order (before any item is added) throws instead of returning 0.

## Acceptance criteria

- An order with no lines yet has a total of 0.

## Repro steps (bugs only)

1. Create `new Order { Id = "o-1" }` (Lines not set).
2. Call `OrderTotals.Calculate(order)`.
3. Expected: 0. Actual: `ArgumentNullException` (Value cannot be null, parameter 'source').

## Extra context from the engineer

None
