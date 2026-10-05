using Orders.Application;
using Orders.Domain;
using Shared.Common;

namespace Orders.Infrastructure;

/// <summary>
/// Sample data only. There is no database in this practice repo.
/// </summary>
public sealed class InMemoryOrderRepository : IOrderRepository
{
    private static readonly Dictionary<int, Order> SampleOrders = new()
    {
        [1001] = new Order(1001, "USD",
        [
            new OrderLine("MUG-01", 2, new Money(10.00m, "USD")),
            new OrderLine("TEE-02", 1, new Money(25.00m, "USD")),
        ]),
        [1002] = new Order(1002, "USD",
        [
            new OrderLine("HOODIE-01", 2, new Money(40.00m, "USD")),
        ], discountCode: "SAVE10"),
        [1003] = new Order(1003, "USD",
        [
            new OrderLine("JACKET-01", 1, new Money(120.00m, "USD")),
        ]),
    };

    public Task<Order?> GetByIdAsync(int id, CancellationToken cancellationToken = default) =>
        Task.FromResult(SampleOrders.GetValueOrDefault(id));
}
