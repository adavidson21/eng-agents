using Shared.Common;

namespace Orders.Application;

public sealed record OrderSummary(
    int OrderId,
    int ItemCount,
    Money Subtotal,
    Money Shipping,
    Money Discount,
    Money Total);
