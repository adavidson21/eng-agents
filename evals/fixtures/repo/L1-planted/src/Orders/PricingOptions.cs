namespace Orders;

/// <summary>Values that change with pricing decisions. Rules read them from here, never inline.</summary>
public static class PricingOptions
{
    /// <summary>Totals are rounded to this many decimal places.</summary>
    public const int Decimals = 2;

    /// <summary>Orders with at least this many items in total get the bulk discount.</summary>
    public const int BulkDiscountMinItems = 10;

    /// <summary>Bulk discount, as a fraction of the subtotal.</summary>
    public const decimal BulkDiscountRate = 0.05m;
}
