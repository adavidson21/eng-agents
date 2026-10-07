# Inventory: <product or repo name>

<!--
Written by /tsd, step 3 and step 4. This is the fact list every diagram is drawn from.
- Every row has a Source: a file path, with a line number when it helps.
- Fill one section, save, then start the next.
- If a section finds nothing, replace its table with "None found."
- Never copy a config value (connection string, URL, password, key). Names only.
-->

Repos: <repo folder>, <repo folder>

## Deployables

Things that run on their own: web apps, APIs, workers, functions, SPAs.

| Name | Repo | Kind | Tech | Source |
|---|---|---|---|---|
| <Orders.Api> | <orders-api> | <API> | <ASP.NET Core .NET 8> | `<orders-api/src/Orders.Api/Orders.Api.csproj>` |

## Data stores

| DbContext or store | Repo | Engine | Connection name | Model source | Source |
|---|---|---|---|---|---|
| <OrdersDbContext> | <orders-api> | <SQL Server> | <"OrdersDb"> | `<path to *ModelSnapshot.cs or entity configs>` | `<path to DbContext>` |

## Entities

One table per DbContext. PK and FK columns, plus at most 6 columns that matter.

### <OrdersDbContext>

| Entity | Table | Columns (type name key) | Relationships | Source |
|---|---|---|---|---|
| <Order> | <Orders> | <int Id PK, int CustomerId FK, OrderStatus Status> | <Customer 1 to many Order (required)> | `<path>` |

## External systems

| System | Called from | How | Config key name | Source |
|---|---|---|---|---|
| <Payment gateway> | <Orders.Api> | <Typed HttpClient PaymentClient, REST> | <"Payments:BaseUrl"> | `<path>` |

## Entry points

Group endpoints by controller. At most 30 rows.

| Entry point | Repo | Routes or trigger | Calls | Source |
|---|---|---|---|---|
| <OrdersController> | <orders-api> | <GET/POST /api/orders, GET /api/orders/{id}> | <CreateOrderHandler> | `<path>` |

## Background work

| Job | Repo | Trigger | What it does | Source |
|---|---|---|---|---|
| <FulfillmentWorker> | <orders-api> | <Queue order-placed> | <Ships paid orders> | `<path>` |

## Links between repos

| From | To | How | Source |
|---|---|---|---|
| <orders-ui> | <orders-api> | <REST, base URL key "apiUrl"> | `<path>` |

## Auth

| Where | Mechanism | Source |
|---|---|---|
| <Orders.Api> | <JWT bearer, [Authorize] on controllers> | `<path>` |

## Status fields

Enum properties named Status or State. Good input for business processes.

| Entity.Property | Values | Changed in | Source |
|---|---|---|---|
| <Order.Status> | <Pending, Paid, PaymentFailed, Shipped, Cancelled> | <CreateOrderHandler, FulfillmentWorker> | `<path to enum>` |

## Deployment files

| File | Repo | What it shows | Source |
|---|---|---|---|
| <azure-pipelines.yml> | <orders-api> | <Stages Build, Deploy. Task IISWebAppDeployment.> | `<path>` |

## Candidates

Filled in step 4.

| # | Kind | Name | Entry point or status field |
|---|---|---|---|
| 1 | <Flow> | <Place an order> | <POST /api/orders> |
| 2 | <Process> | <Order lifecycle> | <Order.Status> |

Picked by the engineer: <flows 1, 3, 4; processes 2>

## Traced flows

One table per picked flow or process. One row per step on the code path.

### <Place an order>

| Step | From | To | Call | Source |
|---|---|---|---|---|
| 1 | <Orders web app> | <OrdersController> | <POST /api/orders> | `<path>` |

## Notes

- <Anything truncated, unclear, or found but not drawn.>
