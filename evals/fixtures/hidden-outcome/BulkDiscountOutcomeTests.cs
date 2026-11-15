using Orders;

namespace Orders.Tests;

// Hidden outcome tests for the feature-outcome case: copied in by the grader after the run, run, then removed.
// Behavior only, no names the agent had to guess, so Tandem and a plain prompt are graded the same way.
public class BulkDiscountOutcomeTests
{
    [Fact]
    public void Outcome_ExactlyTenItems_FivePercentOff()
    {
        var order = new Order { Id = "o-10", Lines = new List<OrderLine> { new("A", 7, 2.00m), new("B", 3, 2.00m) } };
        Assert.Equal(19.00m, OrderTotals.Calculate(order));
    }

    [Fact]
    public void Outcome_NineItems_NoDiscount()
    {
        var order = new Order { Id = "o-9", Lines = new List<OrderLine> { new("A", 9, 2.00m) } };
        Assert.Equal(18.00m, OrderTotals.Calculate(order));
    }

    [Fact]
    public void Outcome_ManyLines_CountsQuantities()
    {
        var order = new Order { Id = "o-12", Lines = new List<OrderLine> { new("A", 4, 5.00m), new("B", 4, 5.00m), new("C", 4, 5.00m) } };
        Assert.Equal(57.00m, OrderTotals.Calculate(order));
    }
}
