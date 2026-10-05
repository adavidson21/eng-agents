# orders-ui

Angular front end for orders. Shows the summary of one order, loaded from orders-api.

| Path | Holds |
|---|---|
| `src/app/orders/` | `OrderSummaryComponent`, `OrderService`, models, money formatting |
| `src/app/api-config.ts` | Base URL of orders-api |
| `e2e/` | Playwright tests. Every API call is mocked with `page.route`. |
| `e2e/helpers/mock-api.ts` | Mock helpers. Use these instead of writing `page.route` by hand. |
| `e2e/fixtures/` | Mock response bodies |

Commands (run from the workspace root):

| Purpose | Command |
|---|---|
| Install | `npm --prefix orders-ui ci` |
| Unit tests (headless, single run) | `npm --prefix orders-ui run test:ci` |
| Playwright tests (starts the dev server itself) | `npm --prefix orders-ui run e2e` |
| Build | `npm --prefix orders-ui run build` |

First time only, install the Playwright browser: `npx --prefix orders-ui playwright install chromium`.
