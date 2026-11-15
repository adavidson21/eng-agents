# Review: R2 Loyalty discount

Verdict: CHANGES NEEDED

| # | Severity | Category | Location | Problem | Suggested fix |
|---|---|---|---|---|---|
| 1 | Should fix | consistency | `sample-api/src/Orders/OrderTotals.cs:22` | Loyalty rate 0.03 is a literal in the rule, not a PricingOptions constant | Add `PricingOptions.LoyaltyRate` |
