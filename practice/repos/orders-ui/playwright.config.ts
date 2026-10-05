import { defineConfig, devices } from '@playwright/test';

/**
 * Playwright starts the Angular dev server itself (webServer below).
 * Every API call is mocked with page.route in the tests, so orders-api does not need to run.
 */
export default defineConfig({
  testDir: './e2e',
  fullyParallel: true,
  retries: 0,
  reporter: 'list',
  use: {
    baseURL: 'http://localhost:4200',
    trace: 'retain-on-failure',
  },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
  webServer: {
    command: 'npm start',
    url: 'http://localhost:4200',
    reuseExistingServer: !process.env['CI'],
    timeout: 180_000,
  },
});
