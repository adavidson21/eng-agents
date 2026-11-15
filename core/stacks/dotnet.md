# Stack: dotnet

Read by `/plan`, `/tasks`, `/do-task` and `/review` when a repo guide's `Stack:` line names `dotnet`. The repo guide wins where it says more.

## Testing

- Test framework: xUnit (or what the repo guide names).
- **Strict TDD.** 1) Write the test. 2) Run it and confirm it FAILS for the expected reason (an assertion or the expected exception, not a compile error elsewhere). 3) Write the code. 4) Run it and confirm it PASSES.
- Record the failing run under `Red run` and the passing run under `Green run` in `progress.md`, with `red=<test name>` on the Stats line.
- Mock dependencies. Tests never use a real database.
- In `/tasks`, the test and the code it tests go in the same task, so the implementer can do TDD.

## Review checklist

Category in `review.md` in brackets.

- **Correctness** (`correctness`): async/await used correctly (no `.Result` or `.Wait()`), `CancellationToken` passed through where the pattern does.
- **EF Core** (`efcore`): no queries inside loops, read-only queries use `AsNoTracking()` if the repo does, no unexpected migration changes.
- **Tests** (`tests`): .NET tests use mocks, no real database.
- **Security** (`security`): no secrets, tokens, connection strings or personal data in log messages or exception text.
- **TDD evidence** (`tdd`): every task that changed .NET code has a `Red run` showing the new test failing for the expected reason.
