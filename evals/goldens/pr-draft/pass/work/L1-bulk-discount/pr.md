# PR text: L1

---

## sample-api

Branch: `dev/feature/L1-bulk-discount` -> `main`

**Title:** Bulk discount: 5% off orders of 10 or more items

**Description:**

Customers who order a lot should pay less, so orders with 10 or more items now get 5% off the subtotal.

- Threshold and rate live in `PricingOptions`
- `OrderTotals.Calculate` applies the discount before rounding

Testing: priced orders of 9 and 10 items; ran `dotnet test sample-api/tests/Orders.Tests/Orders.Tests.csproj`, all passed.
