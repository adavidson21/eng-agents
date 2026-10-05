using System.Globalization;

namespace Shared.Common;

/// <summary>
/// An amount of money in a single currency. Amounts are rounded to cents when multiplied.
/// </summary>
public readonly record struct Money(decimal Amount, string Currency)
{
    public static Money Zero(string currency) => new(0m, currency);

    public Money Add(Money other)
    {
        EnsureSameCurrency(other);
        return this with { Amount = Amount + other.Amount };
    }

    public Money Subtract(Money other)
    {
        EnsureSameCurrency(other);
        return this with { Amount = Amount - other.Amount };
    }

    public Money Multiply(decimal factor) =>
        this with { Amount = Math.Round(Amount * factor, 2, MidpointRounding.AwayFromZero) };

    public override string ToString() =>
        $"{Amount.ToString("0.00", CultureInfo.InvariantCulture)} {Currency}";

    private void EnsureSameCurrency(Money other)
    {
        if (!string.Equals(Currency, other.Currency, StringComparison.Ordinal))
        {
            throw new InvalidOperationException($"Cannot combine {Currency} and {other.Currency}.");
        }
    }
}
