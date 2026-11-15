using Orders;

namespace Orders.Tests;

// Hidden outcome tests for bug-outcome: copied in by the grader after the run, run, then removed. Behavior only.
public class BugOutcomeTests
{
    [Fact]
    public void Outcome_NoLinesSet_TotalIsZero()
    {
        Assert.Equal(0m, OrderTotals.Calculate(new Order { Id = "o-1" }));
    }

    [Fact]
    public void Outcome_EmptyLines_TotalIsZero()
    {
        Assert.Equal(0m, OrderTotals.Calculate(new Order { Id = "o-2", Lines = new List<OrderLine>() }));
    }

    [Fact]
    public void Outcome_NormalOrder_Unchanged()
    {
        var order = new Order { Id = "o-3", Lines = new List<OrderLine> { new("A", 2, 1.25m) } };
        Assert.Equal(2.50m, OrderTotals.Calculate(order));
    }
}
