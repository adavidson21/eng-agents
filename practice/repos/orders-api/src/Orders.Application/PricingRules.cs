using Shared.Common;

namespace Orders.Application;

public static class PricingRules
{
    public const decimal StandardShipping = 7.99m;

    public static Money Shipping(string currency) => new(StandardShipping, currency);

    public static decimal DiscountRate(string? discountCode) =>
        discountCode?.ToUpperInvariant() switch
        {
            "SAVE10" => 0.10m,
            "SAVE20" => 0.20m,
            _ => 0m,
        };
}
