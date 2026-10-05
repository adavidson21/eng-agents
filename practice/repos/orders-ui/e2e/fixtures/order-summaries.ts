/** Mock API responses. Shapes match orders-api's OrderSummary JSON. */
export const orderSummaries = {
  noDiscount: {
    orderId: 1001,
    itemCount: 2,
    subtotal: { amount: 45, currency: 'USD' },
    shipping: { amount: 7.99, currency: 'USD' },
    discount: { amount: 0, currency: 'USD' },
    total: { amount: 52.99, currency: 'USD' },
  },
};
