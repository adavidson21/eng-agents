# Spike findings: coupon stacking

## The ask

Should the bulk discount stack with coupon codes we may add later?

## Short answer

### For engineering

Not by default: apply coupons after the bulk discount, behind one setting in `PricingOptions`.

## Options

### For engineering

1. Stack both (S effort, risk: margin loss on big orders).
2. Best single discount (M effort, risk: confusing for customers).
3. Coupon after bulk discount, one switch (S effort, low risk).

## Risks and dependencies

No coupon code exists yet; sales has not said how coupons should work.

## Recommendation

### For engineering

Option 3: keep the rule in `OrderTotals.Calculate`, add the switch to `PricingOptions` when coupons arrive.

## Next step

Ask sales how coupons should combine before building anything.

## Sources

- `sample-api/src/Orders/OrderTotals.cs`
