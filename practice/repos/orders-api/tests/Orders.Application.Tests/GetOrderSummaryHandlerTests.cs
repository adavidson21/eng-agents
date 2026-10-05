using NSubstitute;
using Orders.Domain;
using Shared.Common;

namespace Orders.Application.Tests;

public class GetOrderSummaryHandlerTests
{
    private readonly IOrderRepository _orders = Substitute.For<IOrderRepository>();

    private GetOrderSummaryHandler CreateHandler() => new(_orders);

    [Fact]
    public async Task HandleAsync_OrderNotFound_ReturnsNull()
    {
        _orders.GetByIdAsync(42, Arg.Any<CancellationToken>()).Returns(Task.FromResult<Order?>(null));

        var result = await CreateHandler().HandleAsync(42);

        Assert.Null(result);
    }

    [Fact]
    public async Task HandleAsync_NoDiscount_TotalIsSubtotalPlusShipping()
    {
        var order = new Order(1001, "USD",
        [
            new OrderLine("MUG-01", 2, new Money(10.00m, "USD")),
            new OrderLine("TEE-02", 1, new Money(25.00m, "USD")),
        ]);
        _orders.GetByIdAsync(1001, Arg.Any<CancellationToken>()).Returns(Task.FromResult<Order?>(order));

        var result = await CreateHandler().HandleAsync(1001);

        Assert.NotNull(result);
        Assert.Equal(new Money(45.00m, "USD"), result.Subtotal);
        Assert.Equal(new Money(7.99m, "USD"), result.Shipping);
        Assert.Equal(new Money(0m, "USD"), result.Discount);
        Assert.Equal(new Money(52.99m, "USD"), result.Total);
    }

    [Fact]
    public async Task HandleAsync_CountsOrderLines()
    {
        var order = new Order(1001, "USD",
        [
            new OrderLine("MUG-01", 2, new Money(10.00m, "USD")),
            new OrderLine("TEE-02", 1, new Money(25.00m, "USD")),
        ]);
        _orders.GetByIdAsync(1001, Arg.Any<CancellationToken>()).Returns(Task.FromResult<Order?>(order));

        var result = await CreateHandler().HandleAsync(1001);

        Assert.NotNull(result);
        Assert.Equal(2, result.ItemCount);
    }
}
