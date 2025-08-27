using LegoCatalog.App.Services;

namespace LegoCatalog.App.Services;

/// <summary>
/// On startup, imports seed data if DB empty and not skipped.
/// </summary>
public class StartupImportHostedService : IHostedService
{
    private readonly IServiceProvider _provider;
    private readonly IConfiguration _cfg;
    private readonly ILogger<StartupImportHostedService> _logger;
    public StartupImportHostedService(IServiceProvider provider, IConfiguration cfg, ILogger<StartupImportHostedService> logger)
    { _provider = provider; _cfg = cfg; _logger = logger; }

    public async Task StartAsync(CancellationToken cancellationToken)
    {
        using var scope = _provider.CreateScope();
        var figures = scope.ServiceProvider.GetRequiredService<IFigureRepository>();
        var importService = scope.ServiceProvider.GetRequiredService<ImportService>();
        var path = Environment.GetEnvironmentVariable("SEED_DATA_PATH") ?? _cfg["Seed:CatalogPath"];
        if (string.IsNullOrWhiteSpace(path) || !File.Exists(path))
        {
            _logger.LogWarning("Seed data path not found – skipping import (path: {Path})", path);
            return;
        }
        await using var fs = File.OpenRead(path);
        var (added, total) = await importService.ImportAsync(fs, cancellationToken);
    _logger.LogInformation("Startup import complete (always run): parsed {Total} items, added {Added} new.", total, added);
    }

    public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;
}
