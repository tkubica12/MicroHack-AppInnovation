### 2025-08-28 (Infrastructure - network redesign with Bastion)
- Adjusted per-user VNet to /22 CIDR with dedicated `vms` /24 and `AzureBastionSubnet` /26.
- Removed public IP from VM NIC; Standard Public IP now attached to Azure Bastion (Basic SKU) for secure RDP.
- Replaced permissive NSG rules with single rule allowing RDP only from VirtualNetwork (Bastion access path).
- Added Bastion host deployment and set Public IP SKU to Standard to satisfy Bastion requirements.
### 2025-08-28 (Infrastructure - inline Public IP)
- Removed separate `pip.bicep` module; inlined Public IP resource into `workload.bicep` (Standard SKU Static) simplifying module graph.
- Updated Bastion host to reference inlined `publicIp` resource id directly.
- README updated (removed module reference, clarified NSG restriction & subnet layout).
### 2025-08-28 (Infrastructure - VM provisioning script)
- Added `baseInfra/scripts/setup.ps1` headless provisioning script (Git, .NET SDK, SQL Express, clone repo, publish app, create Windows Service, firewall rule, env vars). Intended for later Custom Script Extension integration.
### 2025-08-28 (Infrastructure - provisioning script simplification)
- Removed parameters from `setup.ps1`; replaced with top-of-file configuration block for simpler manual tweaking during early testing phase.
### 2025-08-28 (Infrastructure - Git install fallback)
- Enhanced `setup.ps1` Git installation: tries winget, then Chocolatey, then direct silent installer download (pinned version) for Windows Server environments lacking winget.
### 2025-08-28 (Infrastructure - .NET install robustness)
- Improved .NET SDK detection & installation in `setup.ps1` (graceful failure handling, removed invalid -Verbose switch, added PATH refresh and post-install verification).
### 2025-08-28 (Infrastructure - SQL Express arg quoting fix)
- Corrected quoting for `/SQLSVCACCOUNT` in SQL Express silent install args to avoid PowerShell parser error; added log echo of arguments.
### 2025-08-28 (Infrastructure - SQL Express installer robustness)
- Added multi-URL download strategy, bootstrap detection, two-step media download, improved silent install args & timeout loop in `setup.ps1`.
### 2025-08-28 (Infrastructure - SQL Express bootstrap simplification)
- Removed two-step ACTION=Download path; bootstrap now invoked directly with install args and exit code checked.
### 2025-08-28 (Infrastructure - SQL Express extraction install)
- Adjusted `setup.ps1` to always self-extract installer then run inner setup.exe with minimal supported flags (resolving unrecognized settings errors).
### 2025-08-28 (Infrastructure - SQL Express multi-strategy)
- Replaced extraction approach with tiered install (winget -> Chocolatey -> manual bootstrap) plus extended polling.
### 2025-08-28 (Infrastructure - provisioning simplification - Chocolatey baseline)
- Simplified `setup.ps1` by ensuring Chocolatey is installed first, then using it uniformly for Git, .NET SDK, and SQL Server Express (removed multi-strategy logic & manual bootstrap fallback to reduce complexity on Server images lacking winget).
### 2025-08-28 (Infrastructure - service creation diagnostics)
- Added verbose diagnostics & error handling around Windows Service creation in `setup.ps1` (captures sc.exe output, validates existence, fails fast if missing).
### 2025-08-28 (Infrastructure - service creation fallback & self-contained option)
- Added fallback using `New-Service` if `sc.exe create` doesn't materialize service; introduced optional self-contained publish mode to simplify service binPath.
### 2025-08-28 (Infrastructure - pin .NET SDK 8.0.0)
- Modified provisioning script to install exact .NET 8.0.0 (SDK 8.0.100) via dotnet-install script instead of major version heuristic.
### 2025-08-28 (Infrastructure - switch .NET pin to Chocolatey)
- Adjusted provisioning script to use Chocolatey for pinned .NET 8.0 SDK installation (tries multiple package IDs, removes dotnet-install script usage as per requirement).
### 2025-08-28 (Infrastructure - exact .NET SDK 8.0.413 pin)
- Updated provisioning script to require and install only .NET SDK 8.0.413 via Chocolatey (fails fast if not available or mismatched).
### 2025-08-28 (Infrastructure - simplify .NET 8.0.413 install)
- Reduced .NET SDK install logic to a single Chocolatey install attempt (removed multi-package loop, added concise validation).
### 2025-08-28 (Infrastructure - simplify runtime startup)
- Removed service / publish / env var configuration from provisioning script; added startup scheduled task executing `dotnet run` in repo directory for auto-start after reboot.
### 2025-08-28 (Infrastructure - desktop shortcut & browser launch)
- Replaced scheduled task approach with creation of desktop shortcut invoking `start-app.ps1`.
- `start-app.ps1` now sets ASPNETCORE_URLS to http://localhost:5000, starts the app in background, and opens default browser to that URL after short delay.
### 2025-08-28 (Infrastructure - VM Custom Script Extension)
- Added Custom Script Extension to `workload.bicep` executing `setup.ps1` from GitHub URL during VM provisioning (installs dependencies, creates desktop shortcut & browser launch script).
### 2025-08-29 (Infrastructure - NAT Gateway)
### 2025-08-29 (App / Infra - DB creation responsibility shift)
- Removed unconditional `EnsureCreated()` database creation from application startup (now guarded and only creates tables if DB reachable; no CREATE DATABASE attempt).
- Added `SKIP_DB_INIT` env var gate (default '0'); infra/script now pre-creates database aligning with Azure SQL model where database is provisioned separately.
- Updated `setup.ps1` to add config variables for `$DatabaseName`, optional SQL login creation, and to idempotently create the database via `sqlcmd`.
- Rationale: principle of least privilege & forward compatibility with Azure SQL where server-level CREATE DATABASE may not be permitted to app principal.
### 2025-08-29 (Infrastructure - sqlcmd handling simplification)
- Simplified `Ensure-SqlCmd` to probe only two observed install locations and perform a single winget install attempt, removing multi-fallback complexity for clarity on Server 2025 hosts.
### 2025-08-29 (Infrastructure - sqlcmd robustness follow-up)
- Enhanced `Ensure-SqlCmd` to: verify execution (`sqlcmd -?`), persist discovered directory to Machine PATH, and fall back to classic `Microsoft.SQLServer.CommandLineTools` if modern package present but non-functional.
## Implementation Log

### 2025-08-27
Initial implementation of Python data generator (`main.py`):
- Uses Azure OpenAI `AzureOpenAI` client & Responses API for structured text (categories/items) and image generation.
- Batch size default reduced to 20 per new requirement.
- Model now returns `imagePrompt`; no local heuristic assembly.
- Pydantic models for categories, generated items, and catalog items; basic validation (prefix + forbidden tokens).
- Simple resume logic (loads existing `catalog.json` if `--resume`).
- Concurrency for image generation via asyncio semaphore.
- Idempotent category generation unless `--force-categories`.

Future improvements (not yet implemented):
- Robust retry/backoff logic (current version relies on implicit SDK behavior only)
- Enhanced schema / banned token scanning & logging
- Partial save of images progress & failed images list
- More granular error handling & exponential backoff for rate limits

#### Later on 2025-08-27 (same day)
Adjustments & troubleshooting:
- Removed unsupported `response_format` / `modalities` parameters after SDK errors; switched to `responses.parse` with `text_format` using Pydantic models for structured outputs.
- Migrated from deprecated Pydantic v1 `@validator` to v2 `@field_validator` to remove deprecation warnings.
- Multiple failed attempts to generate images via Responses API (direct modalities, then tool invocation) resulted in HTTP 400; pivoted to dedicated `images.generate` API which succeeded for the majority of items.
- Added retry loop (simple exponential backoff) around image generation; still basic and could classify errors better.
- Generated full set target of 200 catalog entries; only 198 images produced (2 failures) during first pass.
- Implemented maintenance utility `prune_missing_images.py` to detect & optionally prune catalog entries whose images are missing. Ran with `--prune` producing backup `catalog.json.bak` and pruned catalog now at 198 entries.
- Environment cleanup: removed unused IMAGE_SIZE env var; batch size kept default 20 in code (note: earlier `.env` still had BATCH_SIZE=50; code path prefers explicit CLI or default constant).
- Logging still minimal; future improvement to record failed image requests with reason codes.

Next potential enhancements:
- Add `--repair-missing-images` workflow to attempt regeneration before pruning.
- Persist a `failed_images.json` with error metadata for audit.
- Align `.env` BATCH_SIZE with default or read it explicitly to avoid confusion.
- Add simple tests under `tests/` for: category generation shape; item batch shape; missing image pruning logic.

### 2025-08-27 (later)
Added initial .NET Blazor Server application (`dotnet/`):
- net9.0 Blazor Server app with EF Core SqlServer; automatic `EnsureCreated` on startup.
- Environment variable overrides (`SQL_CONNECTION_STRING`, `SEED_DATA_PATH`, `IMAGE_ROOT_PATH`, `SKIP_STARTUP_IMPORT`).
- Repository + service layer (`FigureRepository`, `CategoryRepository`, `FigureCatalogService`).
- Startup hosted service to import seed data when DB empty.
- Import page (`/Import`) implemented as Razor Page for file upload of `catalog.json` (idempotent insert-only for new figure IDs).
- Static image serving endpoint `/images/{file}` backed by configurable root path.
- Basic UI: list, search, category filter, detail view.
- README with run instructions.

Deferred (documented for future): blob image store, telemetry.

#### 2025-08-27 (decision: keep simplicity)
- Reverted migration setup back to `EnsureCreated` to avoid external tooling steps.
- Removed Tools package & design-time factory; migrations deferred until schema changes justify complexity.

#### 2025-08-27 (import simplification)
- Removed manual Import page and button; startup import now always runs (idempotent) without SKIP/FORCE flags.
- Startup service logs only total parsed + newly added.

### 2025-08-27 (UI modernization pass)
- Replaced simplistic top bar with sticky header, navigation using `NavLink`, GitHub link, and theme toggle.
- Later same day: removed brand/logo & navigation links (single-page app) keeping only theme toggle + GitHub link in compact header.
- Added dark/light theme with persisted preference via localStorage and CSS custom properties.
- Introduced modern card grid with hover elevation, skeleton loading placeholders, responsive layout, and accessible keyboard interaction.
- Enhanced figure detail page layout (two-column responsive) and badge styles.
- Added Inter font, gradient brand text, refined buttons (primary/ghost) and toolbar styling.
- Implemented reset filters, improved empty state, and focus navigation (updated selector to `h1,h2,h3`).
- Updated CSS with light mode fallback, reduced-motion support, and improved scrollbar styling.
 - Removed obsolete Import navigation (automatic startup import only) and associated Razor Page.

### 2025-08-27 (Infrastructure - initial Bicep modules)
- Added base `bicep/` templates: `main.bicep` (subscription loop), `userInfra.bicep` (RG + pip per user), `pip.bicep` (Public IP resource group module).
- Implemented initial naming convention (later revised) `userNNN-rg` / `userNNN-pip` with zero-padded indices starting at 1.
- Added Deployment Stack CLI instructions to `baseInfra/README.md` for create/update, what-if, listing, and destroy operations.
- Chose `westeurope` default location (adjustable via parameter).
- Future: extend module to include VNET + VM + initialization scripts.

### 2025-08-27 (Infrastructure - naming revision & fix)
- Updated naming to CAF-style prefix ordering: `rg-userNNN`, `pip-userNNN`.
- Fixed Bicep BCP144 error by indexing module collection in output comprehension.

### 2025-08-27 (Infrastructure - per-user network + VM)
- Extended `userInfra.bicep` to provision VNet, Subnet, NSG (RDP/HTTP/HTTPS), NIC, and Windows Server 2022 VM per user.
- Added parameters for admin credentials, VM size, accelerated networking, and optional custom CIDRs.
- Updated `main.bicep` to pass secure admin credentials and fixed loop off-by-one (range now 1..n inclusive).
- README updated with new resource list & CLI examples including credentials.

### 2025-08-28 (Infrastructure - module refactor & lint fixes)
- Introduced `workload.bicep` (resource group scope) containing PIP, NSG, VNet, NIC, VM.
- Simplified `userInfra.bicep` to only create RG and call workload module.
- Addressed Bicep scope errors (BCP037/BCP139) and removed unnecessary dependsOn warnings.
- Updated README to document new module list.
