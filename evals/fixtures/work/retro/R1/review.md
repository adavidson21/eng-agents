# Review: R1 Free shipping over 50

Verdict: CHANGES NEEDED

| # | Severity | Category | Location | Problem | Suggested fix |
|---|---|---|---|---|---|
| 1 | Blocker | consistency | `sample-api/src/Orders/OrderTotals.cs:14` | Free shipping threshold 50 is written inline instead of in PricingOptions | Move it to `PricingOptions.FreeShippingMin` |
| 2 | Nit | tests | `sample-api/tests/Orders.Tests/OrderTotalsTests.cs:40` | Test name does not follow Method_Scenario_ExpectedResult | Rename |
