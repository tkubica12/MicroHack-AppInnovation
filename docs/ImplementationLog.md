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
### 2025-08-29 (Infrastructure - setup.ps1 winget removal & simplification)
- Rewrote provisioning script to eliminate `winget` dependency (not available during Custom Script Extension under SYSTEM) using direct downloads:
	- .NET SDK via `dotnet-install.ps1` channel 8.0
	- SQL Server 2022 Express bootstrap with silent arguments enabling mixed mode + TCP 1433
	- Modern `sqlcmd` (go-sqlcmd) GitHub release zip (pinned version 1.7.0)
- Structured into numbered steps with concise helper functions (Step / Retry / Wait-For) for clarity.
- Moved configuration constants to a single block at top; removed previous multifallback logic and legacy variable section.
- Database & login provisioning now performed using SA credential established at install, then tested with application login.
- Start script generation unchanged in behavior (updated to use new config variables).
### 2025-08-29 (Infrastructure - persist .NET PATH)
- Updated `setup.ps1` to append `C:\Program Files\dotnet` to Machine PATH and set `DOTNET_ROOT` so `dotnet` CLI is available after VM reboot (fixes post-restart 'dotnet not found' issue under new sessions / scheduled tasks).
### 2025-08-29 (Infrastructure - delayed app auto-start)
- Added `start-app-delayed.ps1` wrapper (60s sleep) and updated scheduled task in `setup.ps1` to invoke it, mitigating race where first logon occurs before user profile & PATH (with dotnet) are fully initialized.
### 2025-08-29 (Infrastructure - WSL enablement)
- `setup.ps1` now always enables `Microsoft-Windows-Subsystem-Linux` and `VirtualMachinePlatform` (idempotent) and schedules a reboot (60s) only if features were newly enabled. Prepares for dev tooling (e.g., Rancher Desktop) requiring WSL.
### 2025-08-29 (Infrastructure - dev tools post-logon installer)
- Added Step 8 creating one-time scheduled task `DevToolsInstallOnce` plus `C:\dev-tools-install.ps1` to install VS Code, Azure CLI, Rancher Desktop, and SSMS via winget on first interactive logon; task self-unregisters after success and writes marker file.
### 2025-08-29 (Infrastructure - simplify startup & dev tools execution)
- Removed scheduled tasks (auto-start & dev tools). Retained plain scripts `C:\start-app.ps1` and `C:\dev-tools-install.ps1` for manual execution. Eliminated delayed wrapper. DISM 3010 exit code now treated as success requiring reboot.
### 2025-08-30 (Infrastructure - dev tools script update)
- Added Git (`Git.Git`) installation to `C:\dev-tools-install.ps1` script.
### 2025-09-01 (Challenge 01 - Azure SQL serverless template)
- Added `solutions/ch01/bicep/main.bicep` to deploy Azure SQL logical server + single serverless database (General Purpose tier) with auto-pause 60 minutes and max 2 vCores (implicit min 0.5).
- Implemented unique server naming via `uniqueString(resourceGroup().id)` and firewall rule parameterizing application public IP.
- Included example parameters file `main.bicepparam` and README with deployment instructions & rationale for omitted explicit `minCapacity`.
### 2025-09-01 (Challenge 01 - Bicep fixes & lint cleanup)
- Replaced incorrect `securestring` ARM-style type with Bicep secure decorator (`@secure() param administratorLoginPassword string`).
- Simplified child database resource syntax using `parent` property; removed unnecessary `dependsOn` and updated output to still surface names (no functional change).
- Addressed linter warnings: removed quotes around tag key `workload` (left quotes for `managed-by` which contains a hyphen) and eliminated `use-parent-property` & `no-unnecessary-dependson` warnings.
- Left API version at preview per original template (only warning-level diagnostics); consider moving to latest stable typed version in future hardening pass.
### 2025-09-01 (App - Dockerfile for Blazor Server)
- Added multi-stage Linux Dockerfile (`dotnet/Dockerfile`) targeting .NET 8 (SDK -> aspnet runtime).
- Uses Debian-based images (not Alpine) to avoid additional native dependency installs for `Microsoft.Data.SqlClient`.
- Sets default `ASPNETCORE_URLS=http://0.0.0.0:8080`, exposes 8080, and creates non-root `appuser`.
- README updated with build/run instructions including volume mounts for images & seed catalog.
### 2025-09-01 (App - Dockerfile publish fix)
- Removed `--no-restore` from publish to prevent intermittent `NETSDK1064` (missing analyzer package) during layered build; publish now performs final restore ensuring completeness.
### 2025-09-01 (Challenge 01 - Add Azure Container Registry)
- Extended `solutions/ch01/bicep/main.bicep` to provision Azure Container Registry with unique name (`acr${uniqueString(resourceGroup().id)}`) and configurable SKU (Basic default; allowed Standard/Premium).
- Added outputs for registry name & login server; disabled admin user (prefer AAD) and documented usage in README.
- Updated parameter file and Bicep README to reflect new `acrSku` parameter and combined scope (SQL + ACR).
### 2025-09-01 (Challenge 01 - Allow Azure services firewall rule)
- Added `AllowAzureServices` firewall rule (0.0.0.0 start/end) to SQL server in `solutions/ch01/bicep/main.bicep` to permit connections from Azure services when app lacks fixed outbound IP.
### 2025-09-01 (Challenge 01 - Container Apps deployment)
- Extended `solutions/ch01/bicep/main.bicep` with Azure Container Apps managed environment (consumption workload profile) and container app referencing ACR image `lego-catalog/app:latest`.
- Added storage account + two Azure Files shares (seed + images) mounted at `/mnt/seed` and `/mnt/images`; env vars `IMAGE_ROOT_PATH` and `SEED_DATA_PATH` updated accordingly.
- Implemented secret for `SQL_CONNECTION_STRING` and AcrPull role assignment via system-assigned identity.
- Configured HTTP ingress (external) on port 8080 and HTTP-based autoscale 0..3 replicas (concurrentRequests=50 threshold).
### 2025-09-01 (Challenge 01 - Container Apps deployment fix)
- Fixed Bicep compile issues: replaced fractional CPU (0.5) with integer 1 due to Bicep numeric literal limitation; added explanatory comment.
- Adjusted role assignment resource name to exclude runtime principalId (now deterministic GUID using ACR id + app name) resolving BCP120.
### 2025-09-01 (Challenge 01 - ACR image pull hardening)
- Switched Container App from system-assigned to user-assigned managed identity for ACR pulls following official guidance (pre-create identity, grant AcrPull before app deploy) to avoid cold-start race where image pull occurs before role assignment propagates.
- Added `userAssignedIdentityName` parameter & identity resource, updated role assignment to use identity principalId, configured container registry block with identity resource ID.
- Exposed identity resource ID in outputs for diagnostics.
### 2025-09-03 (CI/CD - Simple GitHub Actions workflow)
- Added `.github/workflows/simple.yaml` triggering on `push` to `main` affecting `dotnet/**` and manual `workflow_dispatch`.
- Implements OIDC Azure login (id-token permission) using repository variables (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`).
- Builds Docker image from `dotnet/Dockerfile` tagging only with workflow run ID (`<GITHUB_RUN_ID>`), no `latest` tag to enforce explicit version pinning, pushes to ACR `${{ vars.ACR_NAME }}` under repository `lego-catalog/app`.
- Updates Azure Container App `lego-catalog-app` in resource group `${{ vars.RESOURCE_GROUP_NAME }}` with new image and sets `IMAGE_VERSION` env var.
- Notes: placeholder disabled docker/login-action kept for future direct push optimization; relies on `az acr login` after Azure CLI OIDC auth.
### 2025-09-03 (CI/CD - GitHub Actions Managed Identity in Bicep)
- Extended `solutions/ch03/bicep/main.bicep` with GitHub Actions user-assigned managed identity + federated identity credential (issuer `token.actions.githubusercontent.com`).
- Added parameters: `githubOrg`, `githubRepo`, `githubBranch`, `githubActionsIdentityName` (defaults set to repository details and `main`).
- Added Contributor role assignment for identity at resource group scope (guid derived) enabling infrastructure + container app updates.
- Outputs now include `ghActionsIdentityClientId` / principal & resource IDs for populating GitHub repository variables (`AZURE_CLIENT_ID`).
- Updated Bicep README documenting new parameters, outputs, and setup instructions for OIDC.
### 2025-09-03 (Container Apps - Enable multiple revisions)
- Changed `activeRevisionsMode` from `Single` to `Multiple` in `solutions/ch03/bicep/main.bicep` to support advanced deployment workflow (parallel revisions, manual promotion / traffic splitting).
- Added inline comment explaining rationale; groundwork for upcoming multi-step GitHub Actions pipeline (blue/green or canary style) described in challenge README.
### 2025-09-03 (CI/CD - Multi-environment GitHub federation)
- Added two additional federated identity credentials to GitHub Actions managed identity for environments `staging` and `production` (subjects `repo:<org>/<repo>:environment:staging|production`).
- Allows using GitHub Environments with protection rules & approvals while reusing the same Azure Managed Identity.
- Updated README (ch03) with instructions on referencing environment-based OIDC in workflows.
### 2025-09-03 (CI/CD - Multi-revision staged promotion workflow)
- Refactored `.github/workflows/simple.yaml` into two jobs: `build_and_stage` (environment: staging) and `promote_production` (environment: production with approval).
- Staging job builds & pushes image (tag = run id), creates new revision, forces 0% traffic to new revision (old stays 100%) and exports revision names.
- Production job (after manual approval) shifts traffic to new revision (100%) and deactivates previous revision to reduce drift.
- Supports blue/green style promotion using Azure Container Apps multiple revisions mode and GitHub Environments gating.
### 2025-09-03 (CI/CD - Production cleanup enhancement)
- Updated production promotion step to deactivate all previously active revisions (not just the immediately prior one) after shifting traffic to the new revision.
- Ensures a single active revision remains, simplifying rollback logic and reducing resource usage.
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
