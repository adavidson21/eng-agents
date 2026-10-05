export interface Money {
  amount: number;
  currency: string;
}

export interface OrderSummary {
  orderId: number;
  itemCount: number;
  subtotal: Money;
  shipping: Money;
  discount: Money;
  total: Money;
}
