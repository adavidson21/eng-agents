# Answer key: feature 102

## Repos and order

1. `shared-lib`: add a way to compare `Money` (for example `IsGreaterThanOrEqualTo(Money other)` or comparison operators), with currency check and tests.
2. `orders-api`: free shipping rule plus `FreeShipping` on `OrderSummary`.
3. `orders-ui`: show `Free` in the shipping row when `freeShipping` is true.

## Good spec questions

- Is the threshold always 100.00 in every currency, or per currency? (Reasonable answer: same number for now, non-goal: per-currency thresholds.)
- Exactly 100.00 qualifies? (Already in the acceptance criteria. A good planner does not ask what is already answered.)

## Good plan details

- Threshold constant in `PricingRules` (for example `FreeShippingThreshold = 100.00m`), shipping chosen in `PricingRules` or the handler based on subtotal before discount.
- `OrderSummary` gains `bool FreeShipping`. JSON becomes `freeShipping`.
- UI: add `freeShipping: boolean` to the `OrderSummary` interface, update the template, update the Playwright fixture.

## Good tasks (about 6)

1. shared-lib: Money comparison + tests.
2. orders-api: threshold rule in `PricingRules` + tests (below, exactly at, above).
3. orders-api: `FreeShipping` on `OrderSummary` and handler + handler tests (including: discount does not affect eligibility).
4. orders-ui: model + component template + component unit test.
5. orders-ui: Playwright fixture for a free-shipping order + e2e test using `mock-api.ts` helpers.

## Signs the agent did well

- `shared-lib` first in `repos.md`.
- Every acceptance criterion maps to at least one task.
- Plan names real files and a "pattern to follow" for each repo.
