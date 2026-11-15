namespace Orders;

/// <summary>Values that change with pricing decisions. Rules read them from here, never inline.</summary>
public static class PricingOptions
{
    /// <summary>Totals are rounded to this many decimal places.</summary>
    public const int Decimals = 2;
}
