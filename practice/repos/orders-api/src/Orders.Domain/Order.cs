using Shared.Common;

namespace Orders.Domain;

public sealed class Order
{
    public Order(int id, string currency, IEnumerable<OrderLine> lines, string? discountCode = null)
    {
        Id = id;
        Currency = currency;
        Lines = lines.ToList();
        DiscountCode = discountCode;
    }

    public int Id { get; }

    public string Currency { get; }

    public IReadOnlyList<OrderLine> Lines { get; }

    public string? DiscountCode { get; }

    public Money Subtotal() =>
        Lines.Aggregate(Money.Zero(Currency), (sum, line) => sum.Add(line.Total()));
}
