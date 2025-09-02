using LegoCatalog.App.Data;
using LegoCatalog.App.Services;
using Microsoft.EntityFrameworkCore;
using System.Text.Json.Serialization;

var builder = WebApplication.CreateBuilder(args);

// Configuration precedence: appsettings.* then environment variables (added automatically by default).
var configuration = builder.Configuration;

// Build connection string (env override if present)
var connStr = Environment.GetEnvironmentVariable("SQL_CONNECTION_STRING")
              ?? configuration["Sql:ConnectionString"]
              ?? throw new InvalidOperationException("SQL connection string not configured.");

builder.Services.AddDbContext<CatalogDbContext>(options =>
    options.UseSqlServer(connStr));

builder.Services.AddRazorPages();
builder.Services.AddServerSideBlazor();

// Prevent JSON serialization cycles (Category <-> Figures) in minimal API responses like /perftest/catalog
builder.Services.ConfigureHttpJsonOptions(o =>
{
    o.SerializerOptions.ReferenceHandler = ReferenceHandler.IgnoreCycles; // skip repeat references
    o.SerializerOptions.DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull;
});

builder.Services.AddScoped<IFigureRepository, FigureRepository>();
builder.Services.AddScoped<ICategoryRepository, CategoryRepository>();
builder.Services.AddScoped<IImageStore, LocalImageStore>();
builder.Services.AddScoped<FigureCatalogService>();
builder.Services.AddScoped<ImportService>();
builder.Services.AddHostedService<StartupImportHostedService>();

var app = builder.Build();

// Schema initialization now optional: database must be pre-created externally (script / infra).
// For on-prem dev you can still allow table creation by omitting SKIP_DB_INIT or setting it to 0.
if (Environment.GetEnvironmentVariable("SKIP_DB_INIT") != "1")
{
    try
    {
        using var scope = app.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<CatalogDbContext>();
        // Only attempt table creation if we can connect to existing DB (we no longer create the database itself).
        if (db.Database.CanConnect())
        {
            db.Database.EnsureCreated(); // Creates tables only if missing.
        }
        else
        {
            Console.WriteLine("[Startup] Database unreachable. Skipping schema init. Ensure DB exists and credentials are correct.");
        }
    }
    catch (Exception ex)
    {
        Console.WriteLine($"[Startup] Schema init skipped due to error: {ex.Message}");
    }
}

if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Error");
}

app.UseStaticFiles();
app.UseRouting();

// Image endpoint (serves files from IMAGE_ROOT_PATH or config fallback)
app.MapGet("/images/{fileName}", (string fileName, IConfiguration cfg) =>
{
    var root = Environment.GetEnvironmentVariable("IMAGE_ROOT_PATH") ?? cfg["Images:RootPath"];
    if (string.IsNullOrWhiteSpace(root)) return Results.NotFound();
    var fullPath = Path.Combine(root, fileName);
    if (!System.IO.File.Exists(fullPath)) return Results.NotFound();
    var stream = System.IO.File.OpenRead(fullPath);
    return Results.File(stream, "image/png");
});

// Performance test endpoint: returns all catalog items.
// Secured via simple API key passed in header `x-api-key`.
app.MapGet("/perftest/catalog", async (HttpRequest request,
                                       FigureCatalogService catalog,
                                       IConfiguration cfg,
                                       ILoggerFactory loggerFactory,
                                       CatalogDbContext db,
                                       CancellationToken ct) =>
{
    var logger = loggerFactory.CreateLogger("PerfTest.CatalogEndpoint");
    try
    {
        var remoteIp = request.HttpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown";
        var providedKey = request.Headers["x-api-key"].FirstOrDefault()?.Trim();
        var expectedKey = (Environment.GetEnvironmentVariable("PERFTEST_API_KEY")
                           ?? cfg["PerfTest:ApiKey"]
                           ?? "Azure12346578").Trim();

        if (string.IsNullOrEmpty(providedKey) || !CryptographicEquals(providedKey, expectedKey))
        {
            logger.LogInformation("/perftest/catalog unauthorized from {RemoteIp}", remoteIp);
            return Results.Unauthorized();
        }

        // 1. Normal catalog (kept for response payload)
        var items = await catalog.ListAsync(null, null, ct); // returns figures with categories
        var count = items?.Count() ?? 0;

        // 2. CPU burner query (amplifies work inside SQL Server but discards result)
        //    Techniques: row amplification via CROSS JOIN (VALUES...), window functions, HASHBYTES, aggregation.
        //    Limited to modest amplification factor (x16) to avoid runaway network output.
        const string heavySql = @"
;WITH Tally AS (
    SELECT 1 AS n
    UNION ALL SELECT n+1 FROM Tally WHERE n < 256 -- amplification factor (adjust carefully)
)
SELECT 
    SUM(CAST(ABS(CHECKSUM(NEWID(), f.Id, f.CategoryId, t.n)) AS bigint)) AS [WorkSum],
    AVG(CAST(ABS(CHECKSUM(f.Name, t.n, NEWID())) AS bigint)) AS [AvgWork],
    MAX(HASHBYTES('SHA2_256', CONVERT(varbinary(36), f.Id) + CAST(t.n AS varbinary(4)))) AS [MaxHash]
FROM Figures f
INNER JOIN Categories c ON c.Id = f.CategoryId
CROSS JOIN Tally t
OPTION (MAXRECURSION 0, RECOMPILE, MAXDOP 4);"; // BIGINT prevents overflow; RECOMPILE + NEWID() adds CPU

        // Execute heavy query (discarding result) to generate CPU load.
        // Using ExecuteSqlRawAsync since we don't project results.
        for (int i = 0; i < 20; i++)
        {
            ct.ThrowIfCancellationRequested();
            await db.Database.ExecuteSqlRawAsync(heavySql, ct);
        }

    logger.LogInformation("/perftest/catalog returned {Count} items (heavy SQL executed x10) to {RemoteIp}", count, remoteIp);
        return Results.Ok(items);
    }
    catch (OperationCanceledException)
    {
        logger.LogInformation("/perftest/catalog cancelled");
        return Results.StatusCode(StatusCodes.Status499ClientClosedRequest);
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "/perftest/catalog failed");
        return Results.Problem("Unexpected error executing performance catalog endpoint.");
    }
})
.WithName("PerfCatalogAll");

// Constant-time comparison to avoid timing leaks (micro-optimization, but trivial to add)
static bool CryptographicEquals(string a, string b)
{
    if (a.Length != b.Length) return false;
    var mismatch = 0;
    for (int i = 0; i < a.Length; i++)
    {
        mismatch |= a[i] ^ b[i];
    }
    return mismatch == 0;
}

app.MapRazorPages();
app.MapBlazorHub();
app.MapFallbackToPage("/_Host");

app.Run();
