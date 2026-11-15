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
}
