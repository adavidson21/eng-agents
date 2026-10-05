# orders-api

Backend for orders. ASP.NET Core minimal API using Clean Architecture.

| Project | Holds | References |
|---|---|---|
| `Orders.Domain` | Entities: `Order`, `OrderLine` | `shared-lib` (relative path) |
| `Orders.Application` | Use cases and pricing rules: `GetOrderSummaryHandler`, `PricingRules`, `IOrderRepository` | Domain |
| `Orders.Infrastructure` | `InMemoryOrderRepository` (seeded sample data, no database) | Application, Domain |
| `Orders.Api` | HTTP endpoints | Application, Infrastructure |

Endpoints:

- `GET /api/orders/{id}/summary`

Run the tests:

```
dotnet test orders-api/tests/Orders.Application.Tests/Orders.Application.Tests.csproj
```

Run the API (port 5080):

```
dotnet run --project orders-api/src/Orders.Api/Orders.Api.csproj
```
