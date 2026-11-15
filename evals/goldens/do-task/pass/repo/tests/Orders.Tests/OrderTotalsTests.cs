using Orders;

namespace Orders.Tests;

public class OrderTotalsTests
{
    [Fact]
    public void Calculate_TwoLines_SumsQuantityTimesPrice()
    {
        var order = new Order
        {
            Id = "o-1",
            Lines = new List<OrderLine>
            {
                new("A", 2, 10.00m),
                new("B", 1, 5.50m),
            },
        };

        Assert.Equal(25.50m, OrderTotals.Calculate(order));
    }

    [Fact]
    public void Calculate_RoundsToTwoDecimals()
    {
        var order = new Order { Id = "o-2", Lines = new List<OrderLine> { new("A", 3, 0.335m) } };

        Assert.Equal(1.01m, OrderTotals.Calculate(order));
    }

    [Fact]
    public void Calculate_NineItems_NoDiscount()
    {
        var order = new Order { Id = "o-9", Lines = new List<OrderLine> { new("A", 9, 10.00m) } };

        Assert.Equal(90.00m, OrderTotals.Calculate(order));
    }

    [Fact]
    public void Calculate_TenItems_GetsBulkDiscount()
    {
        var order = new Order { Id = "o-10", Lines = new List<OrderLine> { new("A", 4, 10.00m), new("B", 6, 10.00m) } };

        Assert.Equal(100.00m * (1 - PricingOptions.BulkDiscountRate), OrderTotals.Calculate(order));
    }

    [Fact]
    public void Calculate_TwelveItems_GetsBulkDiscount()
    {
        var order = new Order { Id = "o-12", Lines = new List<OrderLine> { new("A", 12, 10.00m) } };

        Assert.Equal(120.00m * (1 - PricingOptions.BulkDiscountRate), OrderTotals.Calculate(order));
    }
}
