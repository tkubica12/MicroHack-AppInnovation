## Lego Catalog (.NET Blazor Server)

Simple demo application that serves the generated Lego catalog, allows browsing, searching, filtering by category, viewing details, and importing additional seed data from a JSON file (idempotent insert-only for new product IDs).

### Features
- Blazor Server (.NET 8 LTS) – runs cross‑platform (Windows / Linux) with Kestrel
- EF Core (SQL Server) with automatic schema creation on startup (`EnsureCreated`) – zero extra steps
- Environment variable driven configuration (overrides `appsettings.json`)
- Idempotent JSON import on every startup (always attempted; inserts only new figure IDs)
- Local filesystem image serving via `/images/{imageFile}` endpoint

### Configuration
Configuration sources (highest precedence last):
1. `appsettings.json` / `appsettings.Development.json`
2. Environment variables (override file values)

Environment variables (aligns with design doc):

| Variable | Purpose | Example |
|----------|---------|---------|
| SQL_CONNECTION_STRING | Full SQL Server connection string | `Server=.\\SQLEXPRESS;Database=LegoCatalog;TrustServerCertificate=True;Integrated Security=True` |
| SEED_DATA_PATH | Optional path to `catalog.json` for automatic import when DB empty | `C:\\git\\MicroHack-AppInnovation\\data\\catalog.json` |
| IMAGE_ROOT_PATH | Folder containing PNG images | `C:\\git\\MicroHack-AppInnovation\\data\\images` |
| (removed) | Import now always runs on startup (idempotent) | |

If `SQL_CONNECTION_STRING` is not supplied, the fallback from `appsettings.json` is used.

### Prerequisites
- .NET 9 SDK (preview or later current release)
- SQL Server Express (or any reachable SQL Server). Example local install: https://aka.ms/sqlexpress
- The generated `catalog.json` + `images/` from the Python generator (place them under the repository `data/` folder or anywhere and point env vars accordingly).

### Quick Start (PowerShell)
```powershell
# From repo root
cd dotnet

# (Optional) set environment variables for this session
$env:SQL_CONNECTION_STRING = 'Server=.\SQLEXPRESS;Database=LegoCatalog;TrustServerCertificate=True;Integrated Security=True'
$env:SEED_DATA_PATH = (Resolve-Path ..\data\catalog.json)
$env:IMAGE_ROOT_PATH = (Resolve-Path ..\data\images)

# Restore & run
dotnet restore
dotnet run --project src/LegoCatalog.App/LegoCatalog.App.csproj
```

Open http://localhost:5000 (or shown URL) in a browser.

### Importing Data
On every startup the application attempts to import the seed catalog JSON specified by `SEED_DATA_PATH` (or config fallback). Existing IDs are ignored (no duplicates).

### JSON Schema (Expected Fields)
Minimal required per item: `id`, `name`, `category`, `description`, `imageFile` (and optional `prompt`).

### Production / Container Notes
- Provide env vars instead of editing `appsettings.*` inside container.
- Images can be volume-mounted and pointed via `IMAGE_ROOT_PATH`.
- For Azure SQL, set `SQL_CONNECTION_STRING` accordingly.

### Future Enhancements (Deferred)
- Switch to EF Core migrations later if schema evolution becomes necessary.
- Blob storage image provider via `IImageStore` abstraction.
- OpenTelemetry instrumentation.

### Troubleshooting
- If images 404: verify `IMAGE_ROOT_PATH` and that filenames in DB match actual PNG files.
- If startup import does nothing: ensure `SKIP_STARTUP_IMPORT` is not `true` and DB is empty.

### License / Generated Assets
Generated images & metadata are for instructional use only.
