import { expect, test } from '@playwright/test';

import { orderSummaries } from './fixtures/order-summaries';
import { mockOrderNotFound, mockOrderSummary } from './helpers/mock-api';

test('shows the totals for an order', async ({ page }) => {
  await mockOrderSummary(page, 1001, orderSummaries.noDiscount);

  await page.goto('/');
  await page.getByTestId('order-id').fill('1001');
  await page.getByTestId('load-order').click();

  await expect(page.getByTestId('summary-subtotal')).toHaveText('45.00 USD');
  await expect(page.getByTestId('summary-shipping')).toHaveText('7.99 USD');
  await expect(page.getByTestId('summary-total')).toHaveText('52.99 USD');
});

test('shows an error when the order does not exist', async ({ page }) => {
  await mockOrderNotFound(page, 42);

  await page.goto('/');
  await page.getByTestId('order-id').fill('42');
  await page.getByTestId('load-order').click();

  await expect(page.getByTestId('order-error')).toHaveText('Order 42 was not found.');
});
