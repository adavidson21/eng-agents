# Workspace repo map

Agents: use this file to choose repos for a work item. First match the work item to a product (Products and Glossary), then use that product's repo table, then apply the change order.

This is the eval workspace for Tandem (eng-agents). Everything in it is made up.

## Repos

| Folder | What it is (one line) | Stack | Shared? |
|---|---|---|---|
| sample-api | Order pricing library: order totals, discounts | .NET 8, xUnit | No |

## Products

### Orders

Also called: Ordering, order pricing

| Repo | What lives here for this product | Typical changes |
|---|---|---|
| sample-api | Order model and total calculation | Pricing rules, discounts |

- Usually change together: sample-api alone
- Change order: sample-api
- Entry points: `sample-api/src/Orders/OrderTotals.cs`
- External systems: none
- Business processes: price an order
- Product docs: none

## Glossary

| Work item term | Name in code | Product | Where it shows up |
|---|---|---|---|
| Order total, price | `OrderTotals.Calculate` | Orders | `sample-api/src/Orders/OrderTotals.cs` |
| Line item | `OrderLine` | Orders | `sample-api/src/Orders/Order.cs` |
| Pricing settings | `PricingOptions` | Orders | `sample-api/src/Orders/PricingOptions.cs` |

## Which repos for which kind of work

| Kind of work | Repos |
|---|---|
| Anything about orders or pricing | sample-api |
