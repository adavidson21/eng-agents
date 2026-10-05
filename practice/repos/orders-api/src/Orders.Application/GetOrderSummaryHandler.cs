namespace Orders.Application;

public sealed class GetOrderSummaryHandler(IOrderRepository orders)
{
    public async Task<OrderSummary?> HandleAsync(int orderId, CancellationToken cancellationToken = default)
    {
        var order = await orders.GetByIdAsync(orderId, cancellationToken);
        if (order is null)
        {
            return null;
        }

        var subtotal = order.Subtotal();
        var shipping = PricingRules.Shipping(order.Currency);
        var beforeDiscount = subtotal.Add(shipping);
        var discount = beforeDiscount.Multiply(PricingRules.DiscountRate(order.DiscountCode));
        var total = beforeDiscount.Subtract(discount);

        return new OrderSummary(order.Id, order.Lines.Count, subtotal, shipping, discount, total);
    }
}
