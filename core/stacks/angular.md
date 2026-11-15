# Stack: angular

Read by `/plan`, `/tasks`, `/do-task` and `/review` when a repo guide's `Stack:` line names `angular`. The repo guide wins where it says more.

## Testing

- Tests are required, with the repo's existing unit test runner. Order is flexible: code and tests in either order.
- Run headless, single run (no watch mode).

## Review checklist

Category in `review.md` in brackets.

- **Angular** (`angular`): subscriptions are cleaned up, no `any` unless the code already uses it, follows existing component patterns.
- **Angular** (`angular`): `OnPush` change detection and signals where the repo already uses them.
- **Angular** (`angular`): no logic in templates beyond simple bindings; move it into the component or a pipe.
- **Angular** (`angular`): accessibility basics: form fields have labels, interactive elements are real buttons or links (or have a role), and everything works with the keyboard.
