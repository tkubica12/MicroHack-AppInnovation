using LegoCatalog.App.Data;
using LegoCatalog.App.Services;
using Microsoft.EntityFrameworkCore;

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

app.MapRazorPages();
app.MapBlazorHub();
app.MapFallbackToPage("/_Host");

app.Run();
