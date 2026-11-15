# sample-api

## Purpose

Order pricing library. `OrderTotals.Calculate` turns an order into the amount the customer pays.

## Tech stack

- .NET 8 class library, xUnit 2 tests, no mocking library (the code has no dependencies to mock)

## Commands

Run from the workspace root unless stated otherwise. One command per line.

| Purpose | Command |
|---|---|
| Build | `dotnet build sample-api/src/Orders/Orders.csproj` |
| All unit tests | `dotnet test sample-api/tests/Orders.Tests/Orders.Tests.csproj` |
| One test class | `dotnet test sample-api/tests/Orders.Tests/Orders.Tests.csproj --filter "FullyQualifiedName~OrderTotalsTests"` |

## Architecture

One project, `src/Orders`. Pricing rules live in `OrderTotals`. Values likely to change (thresholds, rates) live in `PricingOptions` as constants, never inline.

Architecture doc: none

## Patterns to follow

| When you need to... | Copy this example |
|---|---|
| Add a pricing rule | `sample-api/src/Orders/OrderTotals.cs` (`Subtotal`) |
| Add a pricing setting | `sample-api/src/Orders/PricingOptions.cs` |
| Add a unit test | `sample-api/tests/Orders.Tests/OrderTotalsTests.cs` |

## Testing

- .NET test projects: `sample-api/tests/Orders.Tests`
- Mocking library: none
- Test naming: `Method_Scenario_ExpectedResult`

## Gotchas

- `OrderTotals.LegacyRound` is unused but kept on purpose: an external report still reflects over it. Do not remove it.

## Do not touch

- `OrderTotals.LegacyRound`

## Remembered
- [stated] new rule written directly
