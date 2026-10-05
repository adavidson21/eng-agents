using Orders.Application;
using Orders.Infrastructure;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddSingleton<IOrderRepository, InMemoryOrderRepository>();
builder.Services.AddScoped<GetOrderSummaryHandler>();
builder.Services.AddCors(options =>
    options.AddDefaultPolicy(policy =>
        policy.WithOrigins("http://localhost:4200").AllowAnyHeader().AllowAnyMethod()));

var app = builder.Build();

app.UseCors();

app.MapGet("/api/orders/{id:int}/summary", async (int id, GetOrderSummaryHandler handler, CancellationToken cancellationToken) =>
    await handler.HandleAsync(id, cancellationToken) is { } summary
        ? Results.Ok(summary)
        : Results.NotFound());

app.Run();
