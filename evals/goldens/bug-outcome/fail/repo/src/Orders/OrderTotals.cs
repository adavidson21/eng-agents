namespace Orders;

public static class OrderTotals
{
    /// <summary>The amount the customer pays for the order.</summary>
    public static decimal Calculate(Order order)
    {
        var subtotal = Subtotal(order);
        return Math.Round(subtotal, PricingOptions.Decimals, MidpointRounding.AwayFromZero);
    }

    /// <summary>Sum of quantity times unit price over every line.</summary>
    public static decimal Subtotal(Order order)
    {
        return order.Lines?.Sum(line => line.Quantity * line.UnitPrice) ?? 0m;
    }

}
