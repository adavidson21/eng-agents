using Orders;

namespace Orders.Tests;

// Hidden acceptance tests: copied in by the eval grader after /do-task, run, then removed.
// They check the behavior the spec asks for, whatever tests the agent wrote.
public class BulkDiscountAcceptanceTests
{
    [Fact]
    public void Hidden_ExactlyTenItems_FivePercentOff()
    {
        var order = new Order { Id = "h-10", Lines = new List<OrderLine> { new("A", 7, 2.00m), new("B", 3, 2.00m) } };
        Assert.Equal(19.00m, OrderTotals.Calculate(order));
    }

    [Fact]
    public void Hidden_NineItems_NoDiscount()
    {
        var order = new Order { Id = "h-9", Lines = new List<OrderLine> { new("A", 9, 2.00m) } };
        Assert.Equal(18.00m, OrderTotals.Calculate(order));
    }

    [Fact]
    public void Hidden_SettingsLiveInPricingOptions()
    {
        Assert.Equal(10, PricingOptions.BulkDiscountMinItems);
        Assert.Equal(0.05m, PricingOptions.BulkDiscountRate);
    }
}
