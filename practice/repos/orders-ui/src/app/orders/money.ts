import { Money } from './order-summary';

export function formatMoney(money: Money): string {
  return `${money.amount.toFixed(2)} ${money.currency}`;
}
