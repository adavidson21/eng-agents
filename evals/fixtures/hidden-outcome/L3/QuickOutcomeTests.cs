using Orders;

namespace Orders.Tests;

// Hidden outcome tests for quick-outcome: copied in by the grader after the run, run, then removed.
// ItemCount is named in the work item's acceptance criteria, so both arms know the name.
public class QuickOutcomeTests
{
    [Fact]
    public void Outcome_ItemCount_SumsQuantities()
    {
        var order = new Order { Id = "o-1", Lines = new List<OrderLine> { new("A", 3, 1m), new("B", 4, 2m) } };
        Assert.Equal(7, OrderTotals.ItemCount(order));
    }

    [Fact]
    public void Outcome_ItemCount_NoLines_Zero()
    {
        Assert.Equal(0, OrderTotals.ItemCount(new Order { Id = "o-2", Lines = new List<OrderLine>() }));
    }
}
