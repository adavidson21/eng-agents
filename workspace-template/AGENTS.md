<!--
WORKSPACE REPO MAP. Copy this file to your workspace root (for example C:\src\work\AGENTS.md).
This is COMPANY content. It lives on the work PC only. Never commit it to eng-agents.

opencode loads this file automatically when you launch from the workspace root.
The planner uses it to decide which repos a work item touches and in what order.
A wrong map produces wrong plans, so keep it accurate.

Everything below marked SAMPLE uses made-up repos (shared-lib, orders-api, orders-ui).
Replace every SAMPLE row with your real repos, then delete this comment.
-->

# Workspace repo map

## Repos

All repos are cloned side by side in this folder. Each one has its own `AGENTS.md` with build and test details.

| Folder | What it is | Stack | Shared? |
|---|---|---|---|
| `shared-lib` | SAMPLE: Monorepo of shared libraries used by several products (auth, logging, common DTOs) | .NET 10, TypeScript | **Yes** |
| `orders-api` | SAMPLE: Orders backend API | ASP.NET Core, EF Core, Clean Architecture | No |
| `orders-ui` | SAMPLE: Orders front end | Angular, Playwright | No |

## How the repos depend on each other

All cross-repo references are **relative paths**, so every repo must stay cloned directly in this folder with these exact folder names.

| Repo | Depends on | How | Example reference |
|---|---|---|---|
| `orders-api` | `shared-lib` | ProjectReference by relative path | SAMPLE: `..\..\shared-lib\src\Shared.Auth\Shared.Auth.csproj` |
| `orders-ui` | `shared-lib` | TypeScript path mapping by relative path | SAMPLE: `"@shared/*": ["../shared-lib/ts/*"]` in `tsconfig.json` |
| `orders-ui` | `orders-api` | HTTP calls only (mocked in tests) | n/a |

**Rule:** a change in `shared-lib` affects every repo that references it. Change it first, and run the tests of every dependent repo touched by the work item.

## Which repos for which kind of work

Hints for the planner when choosing repos in `/start`.

| If the work item is about... | Usually involves |
|---|---|
| SAMPLE: A new field shown on the orders screen | `orders-api` then `orders-ui` |
| SAMPLE: Login, tokens, or permissions | `shared-lib` then every consumer that is affected |
| SAMPLE: A UI-only layout or text change | `orders-ui` |

## Glossary

Domain words the agents will see in work items. Helps them search the code with the right terms.

| Term | Meaning | Where it shows up in code |
|---|---|---|
| SAMPLE: Enrollment | A customer signing up for a plan | `Enrollment*` classes in `orders-api` |

## Local environment notes

- SAMPLE: All tests run without a database. Never point anything at a shared or production environment.
- TODO(you): Anything else every agent must know about working in this workspace (or delete this line).
