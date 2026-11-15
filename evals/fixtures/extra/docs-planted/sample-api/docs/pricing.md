# Pricing

How `sample-api` prices an order.

- `OrderTotals.Calculate` adds up every line (quantity times unit price) and rounds the total to 3 decimal places.
- Rounding uses banker's rounding (`MidpointRounding.ToEven`).
- `OrderTotals.LegacyRound` is called by `Calculate` for every order.
- The number of decimals lives in `PricingOptions.Decimals`.
