# Doc check: sample-api/docs/pricing.md

| Claim | Status | Correction | Evidence |
|---|---|---|---|
| Rounds the total to 3 decimal places | Wrong | 2 decimals (`PricingOptions.Decimals`) | `src/Orders/PricingOptions.cs` |
| Uses banker's rounding (ToEven) | Wrong | `MidpointRounding.AwayFromZero` | `src/Orders/OrderTotals.cs` |
| `LegacyRound` is called by `Calculate` | Wrong | `LegacyRound` is unused here, kept for an external report | `src/Orders/OrderTotals.cs` |
| Decimals live in `PricingOptions.Decimals` | Correct | | `src/Orders/PricingOptions.cs` |
