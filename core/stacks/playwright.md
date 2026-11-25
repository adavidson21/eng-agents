# Stack: playwright

Read by `/spec`, `/quick`, `/do-task` and `/review` when a repo guide's `Stack:` line names `playwright`. The repo guide wins where it says more.

## Testing

- Tests are required. Order is flexible.
- Mock every API call with `page.route`. Never call a real environment.
- Use the repo's existing mock helpers if the repo guide lists any.
- **Acceptance tests.** When the repo guide has a `## Regression tests` table, every acceptance criterion a person can see or click gets one end-to-end test in its Folder, with `[AC-<n>]` at the end of the test title (`test('saves the refund reason [AC-1]', ...)`). The tests stay in the repo: they are the team's regression suite from then on. Test the behavior the criterion names, not the markup.

- **Tandem tools** (when `tandem_*` tools are available): `tandem_tests_detect` says what the repo has (Angular project and port, Playwright, config, routes, a test to copy). `tandem_tests_ensure_env` sets up only what is missing (package, `playwright.config.ts` with `webServer`, test folder, Chromium). `tandem_tests_scaffold` writes a new spec with one `[AC-<n>]` test per criterion; each fails until you write its steps.

## Review checklist

Category in `review.md` in brackets.

- **Playwright** (`playwright`): every API call mocked with `page.route`, no fixed waits (`waitForTimeout`), stable selectors, no `test.only` or `test.skip` added.
