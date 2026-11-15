namespace Orders;

public static class OrderTotals
{
    /// <summary>The amount the customer pays for the order.</summary>
    public static decimal Calculate(Order order)
    {
        var subtotal = Subtotal(order);
        if (ItemCount(order) > PricingOptions.BulkDiscountMinItems)
        {
            subtotal -= subtotal * PricingOptions.BulkDiscountRate;
        }

        return Math.Round(subtotal, PricingOptions.Decimals, MidpointRounding.AwayFromZero);
    }

    /// <summary>Sum of quantity times unit price over every line.</summary>
    public static decimal Subtotal(Order order)
    {
        return order.Lines!.Sum(line => line.Quantity * line.UnitPrice);
    }

    private static int ItemCount(Order order)
    {
        return order.Lines!.Sum(line => line.Quantity);
    }

    // Unused here, but an external report reflects over it. Kept on purpose; see the repo guide.
    public static decimal LegacyRound(decimal value)
    {
        return Math.Round(value, 2);
    }
}
