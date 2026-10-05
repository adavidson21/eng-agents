using Shared.Common;

namespace Orders.Domain;

public sealed record OrderLine(string Sku, int Quantity, Money UnitPrice)
{
    public Money Total() => UnitPrice.Multiply(Quantity);
}
