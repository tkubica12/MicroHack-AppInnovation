<#!
    App_install.ps1

    Purpose:
    * Install .NET SDK (channel 8.0) if missing
      * Download application source zip
      * Create start script using static SQL port 1433
      * Update status file (stage: app)
!#>

param(
    [string]$StatusFile = 'C:\install_status.txt',
    [string]$LogDir = 'C:\InstallLogs'
)

[CmdletBinding()]
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
$LogFile = Join-Path $LogDir 'App_install.log'
$ProgressPreference = 'SilentlyContinue'  # Suppress progress bar to speed downloads
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

###########################################################################
# Configuration
###########################################################################
$DotnetChannel   = '8.0'
$AppDbName       = 'LegoCatalog'
$AppLogin        = 'legoapp'
$AppPassword     = 'Azure12345678'
$SqlPort         = 1433
$SqlServer       = "localhost,$SqlPort"
$ZipUrl          = 'https://github.com/tkubica12/MicroHack-AppInnovation/archive/refs/heads/main.zip'
$ZipFile         = 'C:\source.zip'

###########################################################################
# Helpers
###########################################################################
function LogLine([string]$Level,[string]$Msg){ $ts=(Get-Date).ToString('s'); Add-Content -Path $LogFile -Value "$ts [$Level] $Msg" }
function Info($m){ Write-Host "[APP] $m"; LogLine 'INFO' $m }
function Warn($m){ Write-Warning "[APP] $m"; LogLine 'WARN' $m }
function Fail($m){ Write-Error "[APP] $m"; LogLine 'ERROR' $m; Update-StageStatus -Stage 'app' -State 'failed'; exit 1 }
function Download($Url,$Dest){
    Info "Downloading $Url -> $Dest"
    try {
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile($Url,$Dest)
    } catch {
        Info 'Fallback to Invoke-WebRequest'
        Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing
    }
}
function Update-StageStatus { param([string]$Stage,[string]$State)
    if (-not (Test-Path $StatusFile)) { "sql=pending`napp=pending`ndev=pending`ndevpost=pending" | Out-File -FilePath $StatusFile -Encoding ascii }
    $content = Get-Content $StatusFile
    $updated = $false
    $content = $content | ForEach-Object { if ($_ -match "^$Stage=") { $updated=$true; "$Stage=$State" } else { $_ } }
    if (-not $updated) { $content += "$Stage=$State" }
    $content | Set-Content -Path $StatusFile -Encoding ascii
}

Update-StageStatus -Stage 'app' -State 'running'

###########################################################################
# 1. Install .NET SDK if needed
###########################################################################
if (Get-Command dotnet -ErrorAction SilentlyContinue) {
    $existing = & dotnet --list-sdks 2>$null | Select-String "^$DotnetChannel" -SimpleMatch
    if ($existing) { Info ".NET $DotnetChannel SDK already present" } else { $needInstall=$true }
} else { $needInstall=$true }

if ($needInstall) {
    $dotnetScript = "$env:TEMP\\dotnet-install.ps1"
    Download 'https://dot.net/v1/dotnet-install.ps1' $dotnetScript
    & powershell -ExecutionPolicy Bypass -File $dotnetScript -Channel $DotnetChannel -InstallDir 'C:\Program Files\dotnet'
    if ($LASTEXITCODE -ne 0) { Fail ".NET install failed code $LASTEXITCODE" }
    $env:PATH += ';C:\Program Files\dotnet'
    Info '.NET installed.'
}

# Persist path
$dotnetDir = 'C:\Program Files\dotnet'
try {
    $machinePath = [Environment]::GetEnvironmentVariable('Path','Machine')
    if (-not ($machinePath -split ';' | ForEach-Object { $_.TrimEnd('\\') } | Where-Object { $_ -ieq $dotnetDir })) {
        [Environment]::SetEnvironmentVariable('Path', ($machinePath.TrimEnd(';') + ';' + $dotnetDir), 'Machine')
    }
    [Environment]::SetEnvironmentVariable('DOTNET_ROOT', $dotnetDir, 'Machine')
} catch { Warn "Failed to persist dotnet path: $($_.Exception.Message)" }

###########################################################################
# 2. Download source
###########################################################################
Download $ZipUrl $ZipFile
Expand-Archive -Path $ZipFile -DestinationPath 'C:\' -Force

###########################################################################
# 3. Create start script
###########################################################################
$connStr = "Server=$SqlServer;Database=$AppDbName;User Id=$AppLogin;Password=$AppPassword;Encrypt=True;TrustServerCertificate=True"
$startScriptLines = @(
    '# Auto-generated start script'
    "Set-Location 'C:\\MicroHack-AppInnovation-main\\dotnet'"
    "`$env:SQL_CONNECTION_STRING = '$connStr'"
    "`$env:ASPNETCORE_URLS = 'http://localhost:5000'"
    'dotnet run --project src/LegoCatalog.App/LegoCatalog.App.csproj'
)
$startScriptLines | Set-Content -Path 'C:\start-app.ps1' -Encoding UTF8
Info 'Start script created at C:\start-app.ps1'

Update-StageStatus -Stage 'app' -State 'success'
Info 'App stage completed successfully.'
exit 0
