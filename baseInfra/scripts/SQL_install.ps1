<#!
    SQL_install.ps1

    Purpose:
      * Install / configure SQL Server 2022 Express (mixed mode)
      * Enable static TCP 1433 + open firewall for remote access
      * Install modern sqlcmd (go-sqlcmd MSI)
      * Create application database + login
      * Update shared status file (stage: sql)

    Notes:
      * Idempotent where feasible
      * Executed by orchestrator setup.ps1 under SYSTEM or admin context
      * Keeps its own constants (simple, predictable)
!#>

param(
    [string]$StatusFile = 'C:\install_status.txt',
    [string]$LogDir = 'C:\InstallLogs'
)

[CmdletBinding()]
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # Suppress progress bar for faster large file downloads
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
$LogFile = Join-Path $LogDir 'SQL_install.log'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

###########################################################################
# Configuration
###########################################################################
$SqlExpressUrl    = 'https://download.microsoft.com/download/3/8/d/38de7036-2433-4207-8eae-06e247e17b25/SQLEXPR_x64_ENU.exe'
$SqlInstanceName  = 'SQLEXPRESS'
$SaPassword       = 'Azure12345678!'         # Demo only - do not use in production
$AppDbName        = 'LegoCatalog'
$AppLogin         = 'legoapp'
$AppPassword      = 'Azure12345678'
$SqlCmdVersion    = '1.7.0'
$SqlCmdInstallDir = 'C:\Program Files\sqlcmd'
$StaticTcpPort    = 1433

###########################################################################
# Helpers
###########################################################################
function LogLine([string]$Level,[string]$Msg){ $ts=(Get-Date).ToString('s'); Add-Content -Path $LogFile -Value "$ts [$Level] $Msg" }
function Info($m){ Write-Host "[SQL] $m"; LogLine 'INFO' $m }
function Warn($m){ Write-Warning "[SQL] $m"; LogLine 'WARN' $m }
function Fail($m){ Write-Error "[SQL] $m"; LogLine 'ERROR' $m; Update-StageStatus -Stage 'sql' -State 'failed'; exit 1 }
function Download($Url,$Dest){
    Info "Downloading $Url -> $Dest"
    try {
        # Use WebClient for reduced overhead vs Invoke-WebRequest progress framing
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile($Url,$Dest)
    } catch {
        Info 'Fallback to Invoke-WebRequest'
        Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing
    }
}
function Retry($Description,[scriptblock]$Action,[int]$Retries=15,[int]$Delay=5){
    for($i=1;$i -le $Retries;$i++){ try { & $Action; Info "$Description succeeded (attempt $i)"; return } catch { Warn "$Description failed attempt $i/$Retries : $($_.Exception.Message)"; if($i -eq $Retries){ Fail "$Description failed after $Retries attempts" }; Start-Sleep -Seconds $Delay } }
}
function Update-StageStatus { param([string]$Stage,[string]$State)
    if (-not (Test-Path $StatusFile)) { "sql=pending`napp=pending`ndev=pending`ndevpost=pending" | Out-File -FilePath $StatusFile -Encoding ascii }
    $content = Get-Content $StatusFile
    $updated = $false
    $content = $content | ForEach-Object { if ($_ -match "^$Stage=") { $updated=$true; "$Stage=$State" } else { $_ } }
    if (-not $updated) { $content += "$Stage=$State" }
    $content | Set-Content -Path $StatusFile -Encoding ascii
}

Update-StageStatus -Stage 'sql' -State 'running'

###########################################################################
# 1. Install SQL Server Express (if missing)
###########################################################################
if (-not (Get-Service -Name "MSSQL`$${SqlInstanceName}" -ErrorAction SilentlyContinue)) {
    $bootstrap = "$env:TEMP\\sqlexpress.exe"
    Download $SqlExpressUrl $bootstrap
    $args = @(
        '/Q','/ACTION=Install','/FEATURES=SQLENGINE',
        "/INSTANCENAME=$SqlInstanceName",
        '/SECURITYMODE=SQL',"/SAPWD=$SaPassword",
        '/SQLSVCACCOUNT="NT AUTHORITY\\NETWORK SERVICE"',
        '/TCPENABLED=1','/NPENABLED=0','/BROWSERSVCSTARTUPTYPE=Automatic','/IACCEPTSQLSERVERLICENSETERMS'
    )
    Info 'Starting SQL Express installer'
    $p = Start-Process -FilePath $bootstrap -ArgumentList $args -Wait -PassThru -WindowStyle Hidden
    if ($p.ExitCode -ne 0) { Fail "SQL Express installer exit code $($p.ExitCode)" }
    Info 'SQL Express installation finished.'
} else { Info 'SQL Express already installed.' }

Retry 'Wait for SQL service registration' { Get-Service -Name "MSSQL`$${SqlInstanceName}" -ErrorAction Stop | Out-Null }
Retry 'Wait for SQL service running' { (Get-Service -Name "MSSQL`$${SqlInstanceName}").Status -eq 'Running' | ForEach-Object { if(-not $_){ throw 'Not running'} } }

###########################################################################
# 2. Configure static TCP port 1433 & firewall
###########################################################################
try {
    $instanceReg = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL' -ErrorAction Stop
    $instanceId = $instanceReg.$SqlInstanceName
    if (-not $instanceId) { throw "Instance id not found for $SqlInstanceName" }
    $ipAllPath = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\\$instanceId\MSSQLServer\SuperSocketNetLib\Tcp\IPAll"
    $current = Get-ItemProperty -Path $ipAllPath
    $changed = $false
    if ($current.TcpDynamicPorts) { Set-ItemProperty -Path $ipAllPath -Name 'TcpDynamicPorts' -Value '' ; $changed=$true }
    if ($current.TcpPort -ne $StaticTcpPort.ToString()) { Set-ItemProperty -Path $ipAllPath -Name 'TcpPort' -Value $StaticTcpPort ; $changed=$true }
    if ($changed) {
        Info "Static TCP port set to $StaticTcpPort (service restart)"
        Restart-Service -Name "MSSQL`$${SqlInstanceName}" -Force
        Retry 'Wait for SQL after restart' { (Get-Service -Name "MSSQL`$${SqlInstanceName}").Status -eq 'Running' | ForEach-Object { if(-not $_){ throw 'Not running'} } }
    } else { Info 'Static TCP port already configured.' }
} catch { Warn "Failed static port configuration: $($_.Exception.Message)" }

if (-not (Get-NetFirewallRule -DisplayName 'SQL Server 1433' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName 'SQL Server 1433' -Direction Inbound -Protocol TCP -LocalPort $StaticTcpPort -Action Allow -Profile Any | Out-Null
    Info 'Firewall rule created for TCP 1433.'
} else { Info 'Firewall rule for TCP 1433 already exists.' }

###########################################################################
# 3. Install modern sqlcmd (MSI) if absent
###########################################################################
if (-not (Test-Path $SqlCmdInstallDir)) { New-Item -ItemType Directory -Path $SqlCmdInstallDir | Out-Null }
if (-not (Get-Command sqlcmd -ErrorAction SilentlyContinue)) {
    $sqlcmdMsi = "$env:TEMP\\sqlcmd-$SqlCmdVersion.msi"
    $sqlcmdUrl = "https://github.com/microsoft/go-sqlcmd/releases/download/v$SqlCmdVersion/sqlcmd-amd64.msi"
    Download $sqlcmdUrl $sqlcmdMsi
    $msiArgs = "/i `"$sqlcmdMsi`" /qn /norestart"
    Info 'Installing sqlcmd MSI'
    $p = Start-Process msiexec.exe -ArgumentList $msiArgs -Wait -PassThru
    if ($p.ExitCode -ne 0) { Fail "sqlcmd MSI install failed with code $($p.ExitCode)" }
}
###########################################################################
# Locate sqlcmd.exe (PATH may not be refreshed in current session)
###########################################################################
$SqlCmdExe = $null
try {
    $existing = Get-Command sqlcmd -ErrorAction SilentlyContinue
    if ($existing) { $SqlCmdExe = $existing.Source }
} catch {}

if (-not $SqlCmdExe) {
    $candidates = @(
        'C:\Program Files\sqlcmd\sqlcmd.exe',
        'C:\Program Files\Microsoft Sqlcmd\sqlcmd.exe',
        'C:\Program Files\Microsoft SQLCmd\sqlcmd.exe'
    )
    foreach ($c in $candidates) { if (Test-Path $c) { $SqlCmdExe = $c; break } }
}

if (-not $SqlCmdExe) {
    Warn 'Unable to resolve sqlcmd.exe location immediately; will retry.'
}

Retry 'sqlcmd invocation' {
    if (-not $SqlCmdExe) {
        $existing = Get-Command sqlcmd -ErrorAction SilentlyContinue
        if ($existing) { $SqlCmdExe = $existing.Source }
    }
    if (-not $SqlCmdExe) { throw 'sqlcmd.exe not yet found' }
    & $SqlCmdExe -? | Out-Null
}

if ($SqlCmdExe) {
    Set-Alias -Name sqlcmd -Value $SqlCmdExe -Scope Script
    Info "sqlcmd resolved at $SqlCmdExe"
}
Info 'sqlcmd available.'

###########################################################################
# 4. Create DB + login
###########################################################################
$SqlServerEndpoint = "localhost,$StaticTcpPort"
$provisionSql = @"
IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = N'$AppDbName')
BEGIN
    CREATE DATABASE [$AppDbName];
END;
GO
USE [$AppDbName];
IF NOT EXISTS (SELECT 1 FROM sys.sql_logins WHERE name = N'$AppLogin')
BEGIN
    CREATE LOGIN [$AppLogin] WITH PASSWORD = N'$AppPassword', CHECK_POLICY = ON;
END;
GO
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'$AppLogin')
BEGIN
    CREATE USER [$AppLogin] FOR LOGIN [$AppLogin];
    EXEC sp_addrolemember N'db_owner', N'$AppLogin';
END;
GO
"@

Retry 'DB/login provisioning' {
    $provisionSql | & $SqlCmdExe -S $SqlServerEndpoint -U sa -P $SaPassword -b
    if ($LASTEXITCODE -ne 0) { throw "Provisioning exit code $LASTEXITCODE" }
}

Retry 'App login connectivity' {
    & $SqlCmdExe -S $SqlServerEndpoint -U $AppLogin -P $AppPassword -d $AppDbName -Q 'SELECT TOP 1 name FROM sys.tables' -b | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Connectivity exit $LASTEXITCODE" }
}

Update-StageStatus -Stage 'sql' -State 'success'
Info 'SQL stage completed successfully.'
exit 0
