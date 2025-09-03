using LegoCatalog.App.Data;
using LegoCatalog.App.Services;
using Microsoft.EntityFrameworkCore;
using System.Text.Json.Serialization;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;
using OpenTelemetry.Metrics;
using OpenTelemetry.Logs;
using System.Diagnostics;

var builder = WebApplication.CreateBuilder(args);

// ----------------------------------------------------------------------------
// OpenTelemetry configuration
// ----------------------------------------------------------------------------
// We rely solely on standard OpenTelemetry environment variables for runtime
// configuration (endpoints, headers, protocol, sampler etc.). Nothing here is
// required for the app to run; if env vars are absent we simply export nothing.
// Key variables (all optional):
//   OTEL_SERVICE_NAME                         (logical service id)
//   OTEL_RESOURCE_ATTRIBUTES                  (comma separated k=v, e.g. deployment.environment=dev)
//   OTEL_EXPORTER_OTLP_PROTOCOL               (grpc|http/protobuf)
//   OTEL_EXPORTER_OTLP_ENDPOINT               (base endpoint)
//   OTEL_EXPORTER_OTLP_{TRACES|METRICS|LOGS}_ENDPOINT (signal specific)
//   OTEL_EXPORTER_OTLP_HEADERS                (key1=val1,key2=val2)
//   OTEL_TRACES_SAMPLER                       (always_on|always_off|traceidratio|parentbased_traceidratio)
//   OTEL_TRACES_SAMPLER_ARG                   (ratio for traceidratio, e.g. 0.1)
//   OTEL_BSP_* / OTEL_BLRP_* / OTEL_METRIC_*  (batch / reader tuning)
// Attribute limits & other knobs also respected (OTEL_SPAN_*, OTEL_ATTRIBUTE_* etc.)
// ----------------------------------------------------------------------------

const string ServiceName = "lego-catalog"; // default if OTEL_SERVICE_NAME not set
const string ServiceVersion = "1.0.0";

// Custom ActivitySource & Meter for any future manual spans / instruments
ActivitySource activitySource = new("LegoCatalog.App");
var meter = new System.Diagnostics.Metrics.Meter("LegoCatalog.App", ServiceVersion);
var perfEndpointCounter = meter.CreateCounter<long>("lego.perf_endpoint.invocations", description: "Number of /perftest/catalog calls");

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

// Add OpenTelemetry (no exporter credentials hard-coded; exporter activated via env vars)
builder.Services.AddOpenTelemetry()
    .ConfigureResource(r => r.AddService(serviceName: Environment.GetEnvironmentVariable("OTEL_SERVICE_NAME") ?? ServiceName,
                                         serviceVersion: ServiceVersion))
    .WithMetrics(m => m
        .AddAspNetCoreInstrumentation()
        .AddRuntimeInstrumentation()
        .AddProcessInstrumentation()
        .AddMeter("LegoCatalog.App")
        .AddHttpClientInstrumentation()
        .AddSqlClientInstrumentation()
        .AddOtlpExporter())
    .WithTracing(t => t
        .AddAspNetCoreInstrumentation()
        .AddSqlClientInstrumentation(opt =>
        {
            // Keep defaults (do not capture full SQL text by default to avoid PII/leak)
            // Toggle via env in future if needed.
        })
        .AddHttpClientInstrumentation()
        .AddSource("LegoCatalog.App")
        .AddOtlpExporter()); // Will silently no-op if no OTLP env configuration provided.

// Logging pipeline (OTel) - still falls back to console if no exporter envs.
builder.Logging.ClearProviders();
builder.Logging.AddConsole();
builder.Logging.AddOpenTelemetry(o =>
{
    // Exporter selection via env vars; we keep defaults here.
    // Adding OTLP exporter to logs piggybacks on UseOtlpExporter above; but AddOpenTelemetry logging requires explicit call.
    o.IncludeScopes = true;
    // NOTE: Do not call AddOtlpExporter() here because UseOtlpExporter() was already
    // applied on the main OpenTelemetry builder (covers logs/metrics/traces). Adding
    // it again would throw NotSupportedException at runtime.
});

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
    perfEndpointCounter.Add(1);
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
        if (activitySource.HasListeners())
        {
            using var activity = activitySource.StartActivity("PerfEndpoint.PostProcessing", ActivityKind.Internal);
            activity?.SetTag("lego.catalog.count", count);
        }
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
