using Shared.Common;

namespace Shared.Common.Tests;

public class MoneyTests
{
    [Fact]
    public void Add_SameCurrency_SumsAmounts()
    {
        var result = new Money(10.50m, "USD").Add(new Money(2.25m, "USD"));

        Assert.Equal(new Money(12.75m, "USD"), result);
    }

    [Fact]
    public void Add_DifferentCurrency_Throws()
    {
        var usd = new Money(1m, "USD");
        var eur = new Money(1m, "EUR");

        Assert.Throws<InvalidOperationException>(() => usd.Add(eur));
    }

    [Fact]
    public void Subtract_SameCurrency_SubtractsAmounts()
    {
        var result = new Money(10m, "USD").Subtract(new Money(2.50m, "USD"));

        Assert.Equal(new Money(7.50m, "USD"), result);
    }

    [Fact]
    public void Multiply_RoundsToCents()
    {
        var result = new Money(87.99m, "USD").Multiply(0.10m);

        Assert.Equal(new Money(8.80m, "USD"), result);
    }

    [Fact]
    public void ToString_FormatsAmountAndCurrency()
    {
        Assert.Equal("7.99 USD", new Money(7.99m, "USD").ToString());
    }
}
