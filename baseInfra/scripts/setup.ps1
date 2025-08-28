<#!
.SYNOPSIS
Headless provisioning script for per-user Windows VM (LegoCatalog).

.DESCRIPTION
Installs prerequisites (Git, .NET SDK 9+), SQL Server Express, clones the repository, publishes the app,
creates & configures a Windows Service, opens firewall port, and sets required environment variables.
Designed for manual step‑by‑step testing and later automation via VM Extension.

.NOTES
Idempotent where practical (re-run updates repo & service). Requires elevated PowerShell session.
#>

## -----------------------------------------------------------------------------
## Configuration (edit values here as needed; no script parameters)
## -----------------------------------------------------------------------------
$RepoUrl        = "https://github.com/tkubica12/MicroHack-AppInnovation.git"
$Branch         = "main"
$InstallRoot    = "C:\Apps\LegoCatalog"
$ServiceName    = "LegoCatalog"
$SqlInstanceName= "SQLEXPRESS"
$UseSqlAuth     = $false          # Set to $true to enable mixed mode + SA user
$SqlSaPassword  = ""              # If blank & $UseSqlAuth=$true a random one will be generated
$AppPort        = 80  # (Unused now; keeping for potential future explicit binding)

$ErrorActionPreference = 'Stop'

function Write-Info($m) { Write-Host "[INFO] $m" -ForegroundColor Cyan }
function Write-Warn($m) { Write-Warning $m }
function Ensure-Admin {
  if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    throw "Run elevated (Administrator)."
  }
}

# Ensure Chocolatey (primary package manager for simplicity on Server editions)
function Ensure-Choco {
  if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    Write-Info "Chocolatey not found – installing (official bootstrap script)"
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    try {
      iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    } catch {
      throw "Chocolatey installation failed: $($_.Exception.Message)"
    }
    # Refresh PATH so 'choco' is available in current session
    $env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path','User')
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) { throw "Chocolatey still not found after installation." }
  }
  Write-Info "Chocolatey present (version: $((choco --version) 2>$null))"
}

Write-Info "Validating elevation"
Ensure-Admin

Write-Info "Preparing passwords (if SQL auth requested)"
if ($UseSqlAuth -and [string]::IsNullOrWhiteSpace($SqlSaPassword)) {
  $SqlSaPassword = [System.Web.Security.Membership]::GeneratePassword(20,4)
  Write-Info "Generated SA password: $SqlSaPassword"
}

Write-Info "Preparing folder structure"
$publishDir = Join-Path $InstallRoot "publish"
$tempDir    = Join-Path $env:TEMP "lego_provision"
New-Item -ItemType Directory -Force -Path $InstallRoot,$publishDir,$tempDir | Out-Null

Write-Info "Ensuring package manager (Chocolatey) is available"
Ensure-Choco

Write-Info "Ensuring Git is installed (via Chocolatey)"
if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
  choco install git --yes --no-progress
  $env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path','User')
  if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) { throw "Git installation failed via Chocolatey." }
}

# ----------------------------------------------------------------------------------
# .NET SDK Installation (exact pin via Chocolatey) – require 8.0.413 only (simplified)
# ----------------------------------------------------------------------------------
$requiredSdk = '8.0.413'

function Get-DotnetSdks { (& dotnet --list-sdks 2>$null) | ForEach-Object { ($_ -split "\s+")[0] } }

$hasRequired = $false
if (Get-Command dotnet -ErrorAction SilentlyContinue) {
  $hasRequired = (Get-DotnetSdks | Where-Object { $_ -eq $requiredSdk }) -ne $null
}

if (-not $hasRequired) {
  Write-Info ".NET SDK $requiredSdk not present. Installing (single Chocolatey attempt)."
  try {
    choco install dotnet-sdk --version $requiredSdk --yes --no-progress
  } catch { throw ".NET SDK $requiredSdk Chocolatey install failed: $($_.Exception.Message)" }
  # Refresh PATH and re-check
  $env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path','User')
  if (-not (Get-Command dotnet -ErrorAction SilentlyContinue) -or -not ((Get-DotnetSdks) -contains $requiredSdk)) {
    throw ".NET SDK $requiredSdk not found after install."
  }
  Write-Info ".NET SDK $requiredSdk installed."
} else {
  Write-Info ".NET SDK $requiredSdk already present."
}

# ----------------------------------------------------------------------------------
# SQL Server Express Installation (simplified via Chocolatey)
# ----------------------------------------------------------------------------------
$instanceServiceName = "MSSQL`$$SqlInstanceName"
if (-not (Get-Service -Name $instanceServiceName -ErrorAction SilentlyContinue)) {
  Write-Info "Installing SQL Server Express via Chocolatey"
  # sql-server-express installs default instance SQLEXPRESS
  try {
    choco install sql-server-express --yes --no-progress
  } catch { throw "Chocolatey SQL Server Express install failed: $($_.Exception.Message)" }
  # Poll up to 10 min for service to appear
  $pollSeconds = 0
  while (-not (Get-Service -Name $instanceServiceName -ErrorAction SilentlyContinue)) {
    Start-Sleep 5
    $pollSeconds += 5
    if ($pollSeconds % 60 -eq 0) { Write-Info "Waiting for SQL service ($pollSeconds s)..." }
    if ($pollSeconds -ge 600) { throw "SQL Express service $instanceServiceName not found after 600s" }
  }
  Start-Service $instanceServiceName -ErrorAction SilentlyContinue
  Write-Info "SQL Express installation detected (service present)"
} else {
  Write-Info "SQL Express already present"
}

# ----------------------------------------------------------------------------------
# Clone or Update Repository
# ----------------------------------------------------------------------------------
$repoFolder = $InstallRoot
if (Test-Path $repoFolder/.git) {
  Write-Info "Updating existing repository"
  Push-Location $repoFolder
  git fetch --all --prune
  git checkout $Branch
  git pull origin $Branch
  Pop-Location
} else {
  Write-Info "Cloning repository"
  git clone --branch $Branch --depth 1 $RepoUrl $repoFolder
}

# ----------------------------------------------------------------------------------
# Desktop Shortcut (manual launch) for 'dotnet run'
# ----------------------------------------------------------------------------------
$appProj = Join-Path $repoFolder "dotnet\src\LegoCatalog.App\LegoCatalog.App.csproj"  # corrected path
if (-not (Test-Path $appProj)) { throw "Project not found: $appProj" }

$startScript = Join-Path $InstallRoot 'start-app.ps1'
@"
# Auto-generated: runs the LegoCatalog app
Set-Location "C:\Apps\LegoCatalog\dotnet"
# Force explicit port
$env:ASPNETCORE_URLS = "http://localhost:5000"
# Launch app in background so we can open browser
Start-Process -FilePath dotnet -ArgumentList 'run --project src/LegoCatalog.App/LegoCatalog.App.csproj' -WorkingDirectory "C:\Apps\LegoCatalog\dotnet"
Write-Host "App starting... opening browser in a moment (http://localhost:5000)"
Start-Sleep 10
Start-Process "http://localhost:5000"
"@ | Set-Content -Path $startScript -Encoding UTF8

Write-Info "Creating desktop shortcut"
$shell = New-Object -ComObject WScript.Shell
$shortcutPaths = @([Environment]::GetFolderPath('Desktop'), (Join-Path $env:Public 'Desktop')) | Where-Object { Test-Path $_ }
foreach ($desk in $shortcutPaths) {
  $lnk = Join-Path $desk 'LegoCatalog App.lnk'
  $sc = $shell.CreateShortcut($lnk)
  $sc.TargetPath = 'powershell.exe'
  $sc.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$startScript`""
  $sc.WorkingDirectory = "C:\Apps\LegoCatalog\dotnet"
  $sc.WindowStyle = 1
  $sc.IconLocation = (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')
  $sc.Save()
}

Write-Info "Provisioning complete (use desktop shortcut to start app)"
