import { formatMoney } from './money';

describe('formatMoney', () => {
  it('formats the amount with two decimals and the currency', () => {
    expect(formatMoney({ amount: 7.9, currency: 'USD' })).toBe('7.90 USD');
  });

  it('formats zero', () => {
    expect(formatMoney({ amount: 0, currency: 'USD' })).toBe('0.00 USD');
  });
});
