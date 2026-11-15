# Work item L4: Save orders and serve them over HTTP

- Type: Feature
- State: New
- Link: none (local work item)
- Fetched: Pasted by engineer

## Description

Orders should be saved in a new `Orders` database table (with a migration) and served by a new REST endpoint, `GET /api/orders/{id}`, that other teams will call. Add a new web project for it next to the library.

## Acceptance criteria

- Orders are stored in a new Orders table.
- `GET /api/orders/{id}` returns the order with its total.
- Other teams can rely on the response shape.

## Repro steps (bugs only)

Not a bug

## Extra context from the engineer

None
