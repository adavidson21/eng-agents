using Orders.Domain;

namespace Orders.Application;

public interface IOrderRepository
{
    Task<Order?> GetByIdAsync(int id, CancellationToken cancellationToken = default);
}
