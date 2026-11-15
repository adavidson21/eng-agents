namespace Orders;

// A bad outcome: the rate and threshold are inline, the Do-not-touch method is gone, and a file outside src/ and tests/ changed.
public static class OrderTotals
{
    public static decimal Calculate(Order order)
    {
        var subtotal = Subtotal(order);
        if (order.Lines!.Sum(line => line.Quantity) >= 10)
        {
            subtotal -= subtotal * 0.05m;
        }

        return Math.Round(subtotal, PricingOptions.Decimals, MidpointRounding.AwayFromZero);
    }

    public static decimal Subtotal(Order order)
    {
        return order.Lines!.Sum(line => line.Quantity * line.UnitPrice);
    }
}
