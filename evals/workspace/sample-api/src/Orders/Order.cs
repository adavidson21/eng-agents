namespace Orders;

public sealed record OrderLine(string Sku, int Quantity, decimal UnitPrice);

public sealed class Order
{
    public string Id { get; init; } = "";

    // Lines can be null when an order is created before any item is added.
    public List<OrderLine>? Lines { get; init; }
}
