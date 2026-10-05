# Workspace repo map (practice)

This is a practice workspace with made-up repos. It mirrors a real setup: a shared library referenced by relative path, a .NET API using Clean Architecture, and an Angular front end with Playwright tests.

## Repos

All repos are cloned side by side in this folder. Each one gets its own `AGENTS.md` from `/onboard-repo`.

| Folder | What it is | Stack | Shared? |
|---|---|---|---|
| `shared-lib` | Shared building blocks used by other products, such as the `Money` type | .NET 10 class library, xUnit | **Yes** |
| `orders-api` | Orders backend: order summary with pricing (shipping, discount codes) | ASP.NET Core minimal API, Clean Architecture, xUnit, NSubstitute | No |
| `orders-ui` | Orders front end: look up an order and show its summary | Angular 19, Karma/Jasmine unit tests, Playwright | No |

## How the repos depend on each other

All .NET cross-repo references are **relative paths**, so every repo must stay cloned directly in this folder with these exact folder names.

| Repo | Depends on | How | Example reference |
|---|---|---|---|
| `orders-api` | `shared-lib` | ProjectReference by relative path | `..\..\..\shared-lib\src\Shared.Common\Shared.Common.csproj` in `orders-api/src/Orders.Domain/Orders.Domain.csproj` |
| `orders-ui` | `orders-api` | HTTP only (`GET /api/orders/{id}/summary`). Mocked in every test. | n/a |

**Rule:** a change in `shared-lib` affects every repo that references it. Change it first, and run the tests of `orders-api` too.

## Which repos for which kind of work

| If the work item is about... | Usually involves |
|---|---|
| Pricing, totals, shipping, discounts | `orders-api` (and `orders-ui` if the screen changes) |
| Money math or a new capability on `Money` | `shared-lib` first, then its consumers |
| Text or layout on the orders screen only | `orders-ui` |

## Glossary

| Term | Meaning | Where it shows up in code |
|---|---|---|
| Order summary | Subtotal, shipping, discount, and total for one order | `OrderSummary` in `orders-api`, `OrderSummary` interface in `orders-ui` |
| Discount code | A code like `SAVE10` that takes a percentage off | `PricingRules.DiscountRate` in `orders-api` |
| Money | An amount plus a currency code | `Money` in `shared-lib` |

## Local environment notes

- There is no database. `orders-api` uses seeded in-memory data (orders 1001, 1002, 1003).
- All tests run without a running API. Never start servers yourself; Playwright starts the Angular dev server through its own config.
