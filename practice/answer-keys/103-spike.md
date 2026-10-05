# Answer key: spike 103

## Short answer

Not today. `Order.Subtotal()` starts from `Money.Zero(order.Currency)` and adds each line. `Money.Add` throws `InvalidOperationException` when currencies differ, so an order with mixed-currency lines fails when the summary is built (likely a 500 from the API).

## Evidence

- `shared-lib/src/Shared.Common/Money.cs`: `EnsureSameCurrency` throws on mismatch.
- `orders-api/src/Orders.Domain/Order.cs`: one `Currency` per order; `Subtotal()` aggregates with `Add`.
- `orders-api/src/Orders.Application/PricingRules.cs`: shipping is one fixed amount in the order currency.

## Reasonable options

| Option | Effort |
|---|---|
| A. Reject mixed currencies when creating an order (validate in `Order` constructor) | S |
| B. Convert line prices to the order currency at order time (needs exchange rates source) | M to L |
| C. Group totals per currency in the summary (API and UI change, harder pricing rules) | L |

## Recommendation

A now (fail fast with a clear error), B later if the business confirms the need.
