# shared-lib

## Purpose

Shared building blocks (such as `Money`) used by other repos through relative project references.

## Tech stack

- .NET 10 class library
- xUnit tests, no mocking library needed

## Commands

Run from the workspace root.

| Purpose | Command |
|---|---|
| Build | `dotnet build shared-lib/src/Shared.Common/Shared.Common.csproj` |
| All unit tests | `dotnet test shared-lib/tests/Shared.Common.Tests/Shared.Common.Tests.csproj` |
| One test class | `dotnet test shared-lib/tests/Shared.Common.Tests/Shared.Common.Tests.csproj --filter "FullyQualifiedName~MoneyTests"` |
| Format check | `dotnet format shared-lib/src/Shared.Common/Shared.Common.csproj --verify-no-changes` |

## Architecture

Single library project. No layers.

## Patterns to follow

| When you need to... | Copy this example |
|---|---|
| Add an operation to `Money` | `Add` / `Subtract` in `shared-lib/src/Shared.Common/Money.cs` (currency check first, then `this with { ... }`) |
| Add a test | `shared-lib/tests/Shared.Common.Tests/MoneyTests.cs` |

## Testing

- Test project: `shared-lib/tests/Shared.Common.Tests`
- Test naming: `Method_Scenario_ExpectedResult`
- Arrange, act, assert separated by blank lines

## Dependencies on other repos

None. **Other repos depend on this one:** `orders-api` references `Shared.Common.csproj` by relative path. Any change here must keep `orders-api` building and passing.

## Gotchas

- `Money` is a `readonly record struct`. Equality compares amount and currency.
- Mixing currencies throws `InvalidOperationException`.
