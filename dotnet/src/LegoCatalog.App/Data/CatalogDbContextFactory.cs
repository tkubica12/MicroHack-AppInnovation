using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace LegoCatalog.App.Data;

/// <summary>
/// Design-time factory so EF CLI can create the context for migrations.
/// </summary>
public class CatalogDbContextFactory : IDesignTimeDbContextFactory<CatalogDbContext>
{
    public CatalogDbContext CreateDbContext(string[] args)
    {
        var config = new ConfigurationBuilder()
            .AddJsonFile("appsettings.json", optional: true)
            .AddEnvironmentVariables()
            .Build();

        var connStr = Environment.GetEnvironmentVariable("SQL_CONNECTION_STRING")
                      ?? config["Sql:ConnectionString"]
                      ?? "Server=.\\SQLEXPRESS;Database=LegoCatalog;TrustServerCertificate=True;Integrated Security=True";

        var options = new DbContextOptionsBuilder<CatalogDbContext>()
            .UseSqlServer(connStr)
            .Options;
        return new CatalogDbContext(options);
    }
}