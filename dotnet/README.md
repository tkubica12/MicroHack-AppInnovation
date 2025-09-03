## Lego Catalog (.NET Blazor Server)

Simple demo application that serves the generated Lego catalog, allows browsing, searching, filtering by category, viewing details, and importing additional seed data from a JSON file (idempotent insert-only for new product IDs).

### Features
- Blazor Server (.NET 8 LTS) – runs cross‑platform (Windows / Linux) with Kestrel
- EF Core (SQL Server) with automatic schema creation on startup (`EnsureCreated`) – zero extra steps
- Environment variable driven configuration (overrides `appsettings.json`)
- Idempotent JSON import on every startup (always attempted; inserts only new figure IDs)
- Local filesystem image serving via `/images/{imageFile}` endpoint
- OpenTelemetry instrumentation (traces, metrics, logs) via standard OTEL_* environment variables only (no App Insights / vendor SDK)

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
| PERFTEST_API_KEY | API key required for `/perftest/catalog` endpoint (performance testing) | `MySecretKey123` |

If `SQL_CONNECTION_STRING` is not supplied, the fallback from `appsettings.json` is used.

### Observability (OpenTelemetry)
The app is pre-instrumented with OpenTelemetry using only upstream open-source packages. Nothing is required to run locally; if you do not set any OTEL_* environment variables the exporter is effectively dormant.

Packages included:
- OpenTelemetry (SDK + APIs)
- OpenTelemetry.Extensions.Hosting (generic host integration)
- Instrumentations: AspNetCore, SqlClient, HttpClient, Runtime, Process
- OTLP exporter (enabled for traces/metrics/logs through a single `.UseOtlpExporter()` call)
	- Logs also explicitly register `AddOtlpExporter()` (no vendor-specific logging package required)

Key optional environment variables (spec defined):

| Variable | Purpose | Example |
|----------|---------|---------|
| OTEL_SERVICE_NAME | Logical service name (overrides default `lego-catalog`) | `lego-catalog` |
| OTEL_RESOURCE_ATTRIBUTES | Extra resource attrs | `deployment.environment=dev,team=platform` |
| OTEL_EXPORTER_OTLP_ENDPOINT | Base OTLP endpoint | `http://otel-collector:4317` |
| OTEL_EXPORTER_OTLP_PROTOCOL | `grpc` (default) or `http/protobuf` | `http/protobuf` |
| OTEL_EXPORTER_OTLP_HEADERS | Additional headers | `authorization=Bearer abc123` |
| OTEL_EXPORTER_OTLP_TRACES_ENDPOINT | Trace-specific endpoint | `http://collector:4318/v1/traces` |
| OTEL_EXPORTER_OTLP_METRICS_ENDPOINT | Metrics-specific endpoint | `http://collector:4318/v1/metrics` |
| OTEL_EXPORTER_OTLP_LOGS_ENDPOINT | Logs-specific endpoint | `http://collector:4318/v1/logs` |
| OTEL_TRACES_SAMPLER | Sampler strategy | `traceidratio` |
| OTEL_TRACES_SAMPLER_ARG | Sampler argument (e.g. ratio) | `0.1` |
| OTEL_BSP_* | Batch span processor tuning | see spec |
| OTEL_METRIC_EXPORT_INTERVAL | Metric export interval ms | `10000` |

Instrumentation coverage:
- Incoming HTTP & Blazor Server (AspNetCore)
- Outgoing HTTP (HttpClient)
- SQL Server driver operations (SqlClient) – by default **does not** capture raw SQL text to avoid sensitive data; can be enabled by code change if needed.
- Runtime & process metrics (GC, CPU, memory, threads)
- Custom: counter `lego.perf_endpoint.invocations` and manual activity segment `PerfEndpoint.PostProcessing` when `/perftest/catalog` completes.

Quick test with an OpenTelemetry Collector running locally (example docker):
```powershell
docker run --rm -p 4317:4317 -p 4318:4318 -e LOGS_EXPORTER=otlp -e OTEL_EXPORTER_OTLP_PROTOCOL=grpc otel/opentelemetry-collector:latest

# In another shell (run app with OTLP export)
$env:OTEL_SERVICE_NAME = 'lego-catalog'
$env:OTEL_EXPORTER_OTLP_ENDPOINT = 'http://localhost:4317'
dotnet run --project src/LegoCatalog.App/LegoCatalog.App.csproj
```

Add `OTEL_TRACES_SAMPLER=traceidratio` + `OTEL_TRACES_SAMPLER_ARG=0.2` to reduce volume in load tests.

Disable query string redaction for HTTP spans (development only) by setting:
```powershell
$env:OTEL_DOTNET_EXPERIMENTAL_ASPNETCORE_DISABLE_URL_QUERY_REDACTION = 'true'
```

Troubleshooting exporter issues:
- Create a file `OTEL_DIAGNOSTICS.json` in the working directory:
```json
{ "LogDirectory": ".", "FileSize": 32768, "LogLevel": "Warning", "FormatMessage": true }
```
This enables circular self-diagnostics log (e.g. `LegoCatalog.App.<pid>.log`).

### Prerequisites
- .NET 8 SDK
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

### Containerization
A multi-stage Dockerfile (`dotnet/Dockerfile`) is included for Linux builds.

Build (from within the `dotnet` directory where the Dockerfile resides):
```powershell
cd dotnet
docker build -t lego-catalog .
```

Run from project root, configure proper SQL connection string and we are mapping local folders into container as volumes:
```powershell
$env:SQL_CONNECTION_STRING = 'Server=host.docker.internal,1433;Database=LegoCatalog;User Id=sa;Password=Your_password123;TrustServerCertificate=True'
docker run --rm -p 8080:8080 `
	-e SQL_CONNECTION_STRING="$env:SQL_CONNECTION_STRING" `
	-e IMAGE_ROOT_PATH=/data/images `
	-e SEED_DATA_PATH=/seed/catalog.json `
	-v ${PWD}/data/images:/data/images:ro `
	-v ${PWD}/data/catalog.json:/seed/catalog.json:ro `
	lego-catalog
```

Open http://localhost:8080.

Key env vars for container:
- `SQL_CONNECTION_STRING` (required unless default works)
- `IMAGE_ROOT_PATH` (container path to mounted images)
- `SEED_DATA_PATH` (optional seed JSON import file path)
- `PERFTEST_API_KEY` (override default `Azure12346578` for perf endpoint)

Non-root user `appuser` is used in the final image. Adjust port via `ASPNETCORE_URLS` if needed.

### Future Enhancements (Deferred)
- Switch to EF Core migrations later if schema evolution becomes necessary.
- Blob storage image provider via `IImageStore` abstraction.
- OpenTelemetry instrumentation.
	- Implemented (see Observability section).

### Troubleshooting
- If images 404: verify `IMAGE_ROOT_PATH` and that filenames in DB match actual PNG files.
- If startup import does nothing: ensure `SKIP_STARTUP_IMPORT` is not `true` and DB is empty.

### License / Generated Assets
Generated images & metadata are for instructional use only.

### Performance Test Endpoint
For load testing without establishing Blazor Server circuits you can hit a dedicated HTTP endpoint that returns the full catalog list (all figures) in a single JSON response.

Endpoint:
```
GET /perftest/catalog
Header: x-api-key: <key>
```

Security:
- Protected by an API key passed in header `x-api-key`.
- Default key: `Azure12346578` (defined in `appsettings.json` under `PerfTest:ApiKey`).
- Override via environment variable `PERFTEST_API_KEY` for production / real tests.

Environment precedence for key:
1. `PERFTEST_API_KEY` env var
2. `PerfTest:ApiKey` in configuration (e.g., `appsettings.json`)
3. Built-in fallback constant `Azure12346578`

Example (PowerShell) manual test:
```powershell
Invoke-RestMethod -Uri 'http://localhost:5000/perftest/catalog' -Headers @{ 'x-api-key' = 'Azure12346578' }
```

Use this endpoint in Azure Load Testing / JMeter / k6 to drive database + serialization load without needing to script the SignalR negotiate/WebSocket steps of Blazor Server.
