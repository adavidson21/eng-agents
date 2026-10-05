import { Page } from '@playwright/test';

/** Mock GET /api/orders/{id}/summary to return the given body. Use this in every test that loads an order. */
export async function mockOrderSummary(page: Page, orderId: number, body: unknown): Promise<void> {
  await page.route(`**/api/orders/${orderId}/summary`, (route) =>
    route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(body) }),
  );
}

/** Mock GET /api/orders/{id}/summary to return 404. */
export async function mockOrderNotFound(page: Page, orderId: number): Promise<void> {
  await page.route(`**/api/orders/${orderId}/summary`, (route) => route.fulfill({ status: 404 }));
}
