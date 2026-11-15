# Stack: playwright

Read by `/plan`, `/tasks`, `/do-task` and `/review` when a repo guide's `Stack:` line names `playwright`. The repo guide wins where it says more.

## Testing

- Tests are required. Order is flexible.
- Mock every API call with `page.route`. Never call a real environment.
- Use the repo's existing mock helpers if the repo guide lists any.

## Review checklist

Category in `review.md` in brackets.

- **Playwright** (`playwright`): every API call mocked with `page.route`, no fixed waits (`waitForTimeout`), stable selectors.
