# orders-ui

## Purpose

Angular front end. Looks up an order and shows its summary from orders-api.

## Tech stack

- Angular 19 standalone components, signals
- Karma and Jasmine unit tests
- Playwright end-to-end tests with every API call mocked

## Commands

Run from the workspace root.

| Purpose | Command |
|---|---|
| Install | `npm --prefix orders-ui ci` |
| All unit tests | `npm --prefix orders-ui run test:ci` |
| Playwright tests | `npm --prefix orders-ui run e2e` |
| Build | `npm --prefix orders-ui run build` |

First time only: `npx --prefix orders-ui playwright install chromium`.

## Architecture

| Path | Holds |
|---|---|
| `src/app/orders/` | Feature code: component, service, models, money formatting |
| `src/app/api-config.ts` | API base URL |

## Patterns to follow

| When you need to... | Copy this example |
|---|---|
| Add a component | `orders-ui/src/app/orders/order-summary.component.ts` (standalone, `inject()`, signals, `@if`) |
| Add an API call | `orders-ui/src/app/orders/order.service.ts` |
| Add a component test | `orders-ui/src/app/orders/order-summary.component.spec.ts` (spy service with `jasmine.createSpyObj`) |
| Add a Playwright test with API mocks | `orders-ui/e2e/order-summary.spec.ts` |

## Testing

- Unit tests live next to the code as `*.spec.ts`.
- Playwright config: `orders-ui/playwright.config.ts`. webServer starts the app itself: yes.
- Playwright mock helpers: `orders-ui/e2e/helpers/mock-api.ts`. Mock bodies: `orders-ui/e2e/fixtures/`. Always use these; never call a real API.
- Select elements with `data-testid` attributes.

## Dependencies on other repos

| Other repo | How it is referenced | Example reference |
|---|---|---|
| orders-api | HTTP only | `GET /api/orders/{id}/summary`, mocked in tests |

## Gotchas

- Use `test:ci`, not `test`. Plain `test` runs in watch mode and never exits.
