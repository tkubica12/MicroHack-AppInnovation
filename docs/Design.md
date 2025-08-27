## 1. Overview

Lego Catalog is a learning application demonstrating modernization of a simple ASP.NET Core Blazor app. Phase 1 runs on a single VM with:
– ASP.NET Core Blazor Server (initial) or WASM-hosted (decision below)
– Microsoft SQL Server Express (local)
– Images stored as files on local filesystem

Subsequent labs progressively containerize and migrate to Azure services (Azure Container Apps, Azure SQL Database Serverless, Azure Blob Storage), then introduce scaling to zero, advanced monitoring, and optional AI features (semantic search, chatbot).

## 2. Goals & Non‑Goals
Goals:
1. Simple, clear starting architecture students can understand quickly.
2. Clean separation of concerns to enable incremental refactors (storage, auth, search, image handling) without large rewrites.
3. Deterministic bootstrap: if DB empty, auto-create schema & import seed JSON + images.
4. Configurable purely via environment variables (for easy container + Azure deployment).
5. Ready (not implemented yet) for: managed identity, Blob Storage, embeddings, chatbot.

Non‑Goals (initial phase):
– User authentication / multi-tenant security (catalog is read-only for lab users).
– Complex domain relationships (single table + lookup suffices initially).
– Real licensing of generated images (training-only assets; ensure prompts avoid trademarked logos—handled in generation guidance, not runtime code).

## 3. Functional Requirements (Initial)
– Display list/grid of Lego figures (name, category, image thumbnail, short description).
– Filter by category (client or server side).
– Simple contains search by name (case-insensitive).
– Detail view (full description + full-size image).
– Automatic import of seed data when DB starts empty.

## 4. Non‑Functional Requirements
– Simplicity > micro-optimizations.
– Predictable startup time (<5s on modest VM).
– Observability hooks (logging + metrics baseline) from day 1 to show evolution to OpenTelemetry.
– Cloud portability: minimal local path assumptions (use abstraction for image access).

## 5. Domain Model
Core entities:
LegoFigure: (Id GUID/ULID or deterministic string), Name, CategoryId (FK), Description (Markdown/plain), ImageFileName, CreatedUtc, LastUpdatedUtc.
Category: (Id, Name, Slug).

Future-ready attributes (deferred until needed):
– VectorEmbedding (varbinary / external store) referenced by LegoFigureId.
– ImageUri (for Blob) replacing or complementing ImageFileName.

## 6. Data Generation Pipeline (Python Script Design)
Purpose: Produce ~200 synthetic catalog items with realistic variety: professions (doctor, firefighter, engineer, chef), animals (cow, dog, cat), miscellaneous (astronaut, medieval knight, botanist). Each item has:
– Unique product id (e.g. "LF-0001" sequential) also used as image base filename.
– Name (3–6 words max)
– Category (one from category list; categories themselves generated first ~12–18 categories)
– Description (2–4 sentences; neutral tone; no trademarks; no personal data)
– Image prompt (base prompt for gpt-image-1); script then requests image and saves as PNG named <productId>.png

High-Level Steps:
1. Generate category list via GPT-5 (prompt template enforcing format JSON lines).
2. For each desired figure count: ask GPT-5 to produce structured JSON for N new items referencing existing categories.
3. Deduplicate names; if collision, regenerate.
4. For each item: build an image prompt (template + item specific traits) and call gpt-image-1 to retrieve image.
5. Persist metadata JSON (array) AND images folder.
6. Validate JSON against schema (jsonschema lib) before finalizing.

Script Output Structure:
– data/catalog.json
– images/<productId>.png (200 files)

Execution Idempotency: If images already exist for an item id, skip regeneration unless --force flag.

## 7. JSON Schema (Seed Data)
```json
{
	"$schema": "http://json-schema.org/draft-07/schema#",
	"title": "LegoCatalogSeed",
	"type": "array",
	"items": {
		"type": "object",
		"required": ["id", "name", "category", "description", "imageFile"],
		"properties": {
			"id": { "type": "string", "pattern": "^LF-[0-9]{4}$" },
			"name": { "type": "string", "minLength": 3, "maxLength": 80 },
			"category": { "type": "string", "minLength": 2, "maxLength": 40 },
			"description": { "type": "string", "minLength": 10, "maxLength": 1200 },
			"imageFile": { "type": "string", "pattern": "^LF-[0-9]{4}\.png$" },
			"prompt": { "type": "string" }
		}
	}
}
```

## 8. Application Architecture (Initial Monolith)
Pattern: Layered + Ports & Adapters for storage variability.

Layers:
1. Presentation: Blazor components (pages: List, Detail, NotFound; shared components: FigureCard, CategoryFilter). Minimal logic.
2. Application / Services: FigureCatalogService exposing query operations (ListAll, FilterByCategory, SearchByName, GetDetails) and ImportService for bootstrap.
3. Domain: Entities + simple value objects.
4. Infrastructure: Repositories (IFigureRepository, ICategoryRepository, IImageStore). Initial implementations: SqlFigureRepository (Dapper or EF Core), LocalFileImageStore.

Dependency Direction: Presentation -> Application -> Domain; Infrastructure only referenced via interfaces registered in DI container.

### Key Interfaces (illustrative only)
```csharp
public interface IFigureRepository {
	Task<bool> IsEmptyAsync(CancellationToken ct);
	Task BulkInsertAsync(IEnumerable<LegoFigure> figures, CancellationToken ct);
	Task<IReadOnlyList<LegoFigure>> ListAsync(string? category, string? nameSearch, CancellationToken ct);
	Task<LegoFigure?> GetAsync(string id, CancellationToken ct);
}

public interface IImageStore {
	Task<Stream> OpenReadAsync(string imageName, CancellationToken ct);
	string GetPublicUrl(string imageName); // For local file may synthesize /images/... path
}
```

Future: Add IVectorSearch / IChatService without touching existing UI pages except wiring new features.

## 9. Storage Strategy
Phase 1: SQL Express local DB (MDF file) + local images folder. Connection via environment variable.
Phase 2: Azure SQL Serverless (same schema). Migration path: ensure no instance-specific SQL features, enforce Id lengths & datatypes compatible with Azure SQL; use migrations (EF Core) or idempotent CREATE scripts.
Images Migration: Replace LocalFileImageStore implementation with BlobImageStore (container name from env). Because UI consumes only GetPublicUrl/OpenRead, minimal change.

## 10. Database Schema (Initial)
```sql
Table: Categories
	Id INT IDENTITY PK
	Name NVARCHAR(64) UNIQUE NOT NULL
	Slug NVARCHAR(64) UNIQUE NOT NULL

Table: LegoFigures
	Id NVARCHAR(16) PK -- e.g. LF-0001
	Name NVARCHAR(80) NOT NULL
	CategoryId INT NOT NULL FK -> Categories(Id)
	Description NVARCHAR(MAX) NOT NULL
	ImageFile NVARCHAR(64) NOT NULL
	CreatedUtc DATETIME2 NOT NULL
	LastUpdatedUtc DATETIME2 NOT NULL
	CONSTRAINT IX_Figures_Name INCLUDE(Name)
```

Future (deferred):
– Table: FigureEmbeddings (LegoFigureId FK, Vector VARBINARY(MAX) or external vector service ref, ModelVersion, UpdatedUtc)

## 11. Startup / Import Flow
1. App starts, builds service provider.
2. ImportHostedService (background on startup) checks IFigureRepository.IsEmptyAsync.
3. If empty: read catalog.json (path from env), parse & validate; upsert categories first, then bulk insert figures.
4. Log metrics (#figures imported, duration). Errors fail fast (so lab sees issue early), but can be overridden with env SKIP_IMPORT=true.

Sequence (simplified):
User Request -> Blazor Page -> FigureCatalogService -> IFigureRepository -> SQL

## 12. Configuration (Environment Variables)
| Variable | Purpose | Example |
|----------|---------|---------|
| APP_ENV | Environment name | Development |
| SQL_CONNECTION_STRING | SQL Server connection | Server=.\\SQLEXPRESS;Database=Lego;Trusted_Connection=False;User Id=sa;Password=Pass123!;TrustServerCertificate=True |
| SQL_AUTH_MODE | password | password / managedIdentity (future) |
| IMAGE_ROOT_PATH | Local images folder (phase 1) | C:\\data\\lego-images |
| SEED_DATA_PATH | Path to catalog.json | C:\\data\\seed\\catalog.json |
| ENABLE_OTEL | Enable OpenTelemetry export | true |
| OTEL_EXPORTER_OTLP_ENDPOINT | OTLP collector endpoint | http://otel:4317 |
| BLOB_CONTAINER_NAME | Future blob container (optional now) | lego-images |
| BLOB_ACCOUNT_URL | Future storage account URL | https://acct.blob.core.windows.net |

Managed Identity Switch: When SQL_AUTH_MODE=managedIdentity, code acquires token via Azure.Identity (DefaultAzureCredential) and constructs SqlConnection with AccessToken.

## 13. Security & Secrets
– Do not bake credentials into code; rely on environment vars / managed identity.
– Validate & sanitize search input (simple parameterized queries via EF Core/Dapper prevents SQL injection).
– Restrict image prompt generation (generator script enforces safe adjectives; not runtime concern).
– HTTPS enforced in production deployments (Container Apps provides TLS at ingress).

## 14. Containerization Design
Dockerfile Outline (not implemented yet):
– Multi-stage: build (sdk image) -> runtime (aspnet image).
– Copy seed JSON & (optionally) images into /app/seed for first run OR mount volume.
– Use non-root user (Linux) for runtime.
– Expose 8080; health endpoint /healthz.

Environment injection via Azure Container Apps secrets & vars.

## 15. Azure Deployment (Target State)
Components:
– Azure Container Apps (revision-based, min replicas 0, max scale >1).
– Azure SQL Database (Serverless tier, auto-pause for cost). Connection resiliency (EnableRetryOnFailure in DbContext or transient policy).
– Azure Blob Storage (Hot tier) for images.
– (Optional later) Azure OpenAI for embeddings + chat.
– Log Analytics Workspace + Application Insights (via OpenTelemetry exporter).

Ingress: ACA HTTP -> Blazor app. Outbound: SQL, Blob, OpenAI.

Networking: Initially public endpoints; future exercise: restrict via VNet integration + private endpoints.

## 16. Scaling & Resiliency
– Horizontal scaling per concurrent HTTP requests & CPU (KEDA triggers inside ACA). Example rules: scale out if avg CPU > 60% or RPS > threshold.
– Scale to zero when idle (no requests for N minutes) to showcase cost optimization.
– Stateless app: no in-memory session reliance (facilitates scale-out & zero). Image storage externalized.
– Transient fault handling: Polly retry policies around repository operations.

## 17. Observability & Monitoring
Baseline (phase 1): Console + structured logging (Serilog or built-in). Minimal custom metrics (#FiguresListed, ImportDurationMs).
Modernized: Add OpenTelemetry SDK exporting traces, metrics, logs to OTLP endpoint in ACA (collected by Azure Monitor). Correlate DB calls automatically via instrumentation.
Dashboards: RPS, p95 latency, error rate, cold start time (time from replica activation to first successful request), import status.

## 18. Future Extensions (Planned Labs)
1. Blob Migration: Implement BlobImageStore using Azure.Storage.Blobs; toggle via IMAGE_STORE=blob.
2. Managed Identity: Set SQL_AUTH_MODE=managedIdentity; remove password secret; show connection token retrieval.
3. Semantic Search: Add EmbeddingService (wrap Azure OpenAI embedding API) + Vector store table or external Cognitive Search. Provide ISearchService that first tries vector similarity else fallback to name LIKE.
4. Chatbot: Introduce IChatService that uses retrieval (top-K similar figures) + ChatCompletion to answer questions referencing figure details.
5. Caching Layer: Add optional in-memory / distributed cache for popular queries.
6. CI/CD: GitHub Actions building container, pushing to ACR, deploying to ACA (pipeline design out-of-scope now).

## 19. Risks & Mitigations
| Risk | Impact | Mitigation |
|------|--------|-----------|
| GPT content variability | Inconsistent categories on multiple runs | Pin seed JSON; lock category list after first generation |
| Image generation delays | Long script runtime | Parallelize image requests (bounded concurrency) |
| Large descriptions bloating page | Slower list load | Use truncated description in list view |
| Scale-to-zero cold start | First request latency | Warmup ping (optional) or document behavior in lab |
| Blob eventual consistency (if using CDN) | Stale image after update | Cache-busting query param (future) |

## 20. Open Questions
1. Blazor Hosting Model: Start with Blazor Server (simpler real-time updates, smaller download) or WASM? Recommendation: Blazor Server initially for simplicity + lower asset complexity; future lab could convert to WASM to illustrate architecture change.
2. Choice of ORM: EF Core (easier for students) vs Dapper (lightweight). Recommendation: EF Core for readability & migrations.
3. Image size standardization: Apply resizing in generation script? (Recommended: script produce 512x512 PNG; UI generates thumbnail via CSS only.)

## 21. Minimal Sample JSON Entry
```json
{
	"id": "LF-0001",
	"name": "Spacewalking Robotics Engineer",
	"category": "Space Exploration",
	"description": "A skilled engineer equipped with advanced tools, specializing in maintaining robotic arms during extravehicular missions.",
	"imageFile": "LF-0001.png",
	"prompt": "LEGO minifigure style, spacewalking robotics engineer repairing a satellite, vibrant colors, clean background"
}
```

## 22. High-Level Modernization Timeline (Suggested Lab Sequence)
1. Baseline VM deployment & data import.
2. Add environment-based configuration & logging improvements.
3. Containerize (Dockerfile) & run locally.
4. Deploy to Azure Container Apps + Azure SQL (password auth).
5. Introduce Blob storage for images.
6. Switch SQL auth to Managed Identity.
7. Add OpenTelemetry & dashboards.
8. Implement semantic search (embeddings) & simple chatbot.
9. Optional: Convert to Blazor WASM + API backend separation.

## 23. Summary of Extension Points
| Concern | Interface / Abstraction | Initial Impl | Future Impl |
|---------|------------------------|--------------|-------------|
| Figures data | IFigureRepository | SQL Express | Azure SQL (same) |
| Images | IImageStore | LocalFileImageStore | BlobImageStore |
| Search | ISearchService (future) | Basic name LIKE | Vector similarity |
| Auth to SQL | Connection Factory | Password | Managed Identity |
| Telemetry | IHost instrumentation | Console logs | OpenTelemetry + Azure Monitor |

## 24. Rationale Highlights
– Interface-driven infra reduces churn when swapping storage/auth.
– Seed JSON ensures deterministic initialization across labs.
– Environment variable config aligns with Twelve-Factor & ACA deployment model.
– Early observability scaffolding makes later monitoring lab focused on configuration not refactor.
– EF Core chosen to accelerate learning & migrations demonstration.

## 25. Next Steps (Before Coding)
1. Confirm Blazor hosting model decision (default: Server).
2. Decide EF Core vs Dapper (default: EF Core).
3. Generate seed data and store under `data/` (not yet in repo until confirmed licensing + size constraints; maybe provide script only).
4. Draft environment variable naming in README.
5. Plan minimal initial project structure.

End of Design Document.
