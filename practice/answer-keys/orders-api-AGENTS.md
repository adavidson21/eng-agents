# orders-api

## Purpose

Orders backend. Returns an order summary (subtotal, shipping, discount, total) over HTTP.

## Tech stack

- .NET 10, ASP.NET Core minimal API
- xUnit and NSubstitute
- No database: `InMemoryOrderRepository` holds seeded sample orders

## Commands

Run from the workspace root.

| Purpose | Command |
|---|---|
| Build | `dotnet build orders-api/src/Orders.Api/Orders.Api.csproj` |
| All unit tests | `dotnet test orders-api/tests/Orders.Application.Tests/Orders.Application.Tests.csproj` |
| One test class | `dotnet test orders-api/tests/Orders.Application.Tests/Orders.Application.Tests.csproj --filter "FullyQualifiedName~GetOrderSummaryHandlerTests"` |
| Format check | `dotnet format orders-api/src/Orders.Api/Orders.Api.csproj --verify-no-changes` |

## Architecture

Clean Architecture.

| Layer / project | May reference | Must NOT reference |
|---|---|---|
| Orders.Domain | shared-lib | Application, Infrastructure, Api |
| Orders.Application | Domain | Infrastructure, Api |
| Orders.Infrastructure | Application, Domain | Api |
| Orders.Api | Application, Infrastructure (for DI only) | |

Pricing logic lives in `Orders.Application` (`PricingRules`, `GetOrderSummaryHandler`). Endpoints in `Orders.Api/Program.cs` contain no logic.

## Patterns to follow

| When you need to... | Copy this example |
|---|---|
| Add a use case | `orders-api/src/Orders.Application/GetOrderSummaryHandler.cs` |
| Add a pricing rule | `orders-api/src/Orders.Application/PricingRules.cs` |
| Add an endpoint | `orders-api/src/Orders.Api/Program.cs` (`MapGet` returning `Results.Ok` / `Results.NotFound`) |
| Add a handler test | `orders-api/tests/Orders.Application.Tests/GetOrderSummaryHandlerTests.cs` (NSubstitute repo, `Task.FromResult<Order?>`) |

## Testing

- Test project: `orders-api/tests/Orders.Application.Tests`
- Mocking library: NSubstitute
- Test naming: `Method_Scenario_ExpectedResult`
- Assert exact `Money` values, for example `Assert.Equal(new Money(52.99m, "USD"), result.Total)`

## Dependencies on other repos

| Other repo | How it is referenced | Example reference |
|---|---|---|
| shared-lib | Relative path | `..\..\..\shared-lib\src\Shared.Common\Shared.Common.csproj` in `Orders.Domain.csproj` |

## Gotchas

- Sample orders: 1001 (no discount, subtotal 45.00), 1002 (SAVE10, subtotal 80.00), 1003 (subtotal 120.00).
- JSON is camelCase (ASP.NET Core default). `orders-ui` depends on the field names.
