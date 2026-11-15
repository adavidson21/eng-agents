# Spec: L1 Bulk discount for large orders

Status: APPROVED

## Goal

Orders with 10 or more items in total get 5% off the subtotal, so customers who order a lot pay less.

## Current behavior

`sample-api/src/Orders/OrderTotals.cs` `Calculate` sums quantity times unit price (`Subtotal`) and rounds to `PricingOptions.Decimals`. There is no discount.

## Acceptance criteria

- **AC-1:** Given an order whose line quantities add up to 10 or more, when the total is calculated, then the total is the subtotal minus 5%, rounded to 2 decimals.
- **AC-2:** Given an order whose line quantities add up to fewer than 10, when the total is calculated, then the total equals the subtotal, as today.
- **AC-3:** Given the threshold and rate, when they change, then only `PricingOptions` changes; the rule reads both from there.

## Non-goals

- Discounts per line or per product.

## Decisions made during clarification

| Question | Answer |
|---|---|
| None asked | |

## Assumptions

- The discount applies before rounding.

## Open questions

- None
