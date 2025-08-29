<#
    setup.ps1  (no winget version)

    Purpose:
        - Install .NET 8 SDK
        - Install SQL Server 2022 Express (mixed mode, instance name, SQL Browser)
        - Install modern sqlcmd (go-sqlcmd) without winget
        - Create application database + login
        - Download repository & create start script

    Design goals:
        * No dependency on winget / Chocolatey (works under Custom Script Extension SYSTEM context)
        * Minimal branching; clear numbered steps
        * Hardcoded paths & versions for predictability (adjust near top)
        * Idempotent where practical
#>

###########################################################################
# 0. Configuration (adjust if needed)
###########################################################################
$DotnetChannel   = '8.0'                # dotnet-install channel
$SqlExpressUrl   = 'https://download.microsoft.com/download/3/8/d/38de7036-2433-4207-8eae-06e247e17b25/SQLEXPR_x64_ENU.exe'  # Full SQL 2022 Express package (supports setup switches)
$SqlInstanceName = 'SQLEXPRESS'
$SaPassword      = 'Azure12345678!'     # Strong SA password (required for mixed mode). DO NOT use in production.
$AppDbName       = 'LegoCatalog'
$AppLogin        = 'legoapp'
$AppPassword     = 'Azure12345678'
$SqlCmdVersion   = '1.7.0'              # modern sqlcmd pinned version (MSI)
$SqlCmdInstallDir= 'C:\Program Files\sqlcmd'

$ProgressPreference  = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

###########################################################################
# Helper Functions
###########################################################################
function Step($n,$msg){ Write-Host "`n=== STEP ${n}: $msg ===" }
function Info($m){ Write-Host "[INFO] $m" }
function Warn($m){ Write-Warning $m }
function Fail($m){ throw $m }
function Download($Url,$Dest){
    Info "Downloading $Url -> $Dest"
    Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing
}
function Wait-For {
    param([scriptblock]$Test,[string]$Description,[int]$TimeoutSec=900,[int]$IntervalSec=5)
    $sw=[Diagnostics.Stopwatch]::StartNew()
    while($sw.Elapsed.TotalSeconds -lt $TimeoutSec){ if((& $Test)){ Info "Ready: $Description"; return }; Start-Sleep -Seconds $IntervalSec }
    Fail "Timeout waiting for $Description"
}
function Retry($Description,[scriptblock]$Action,[int]$Retries=20,[int]$Delay=5){
    for($i=1;$i -le $Retries;$i++){ try { & $Action; Info "$Description succeeded (attempt $i)"; return } catch { Warn "$Description failed attempt $i/$Retries : $($_.Exception.Message)"; if($i -eq $Retries){ Fail "$Description failed after $Retries attempts" }; Start-Sleep -Seconds $Delay } }
}

###########################################################################
# 1. Install .NET SDK (dotnet-install)
###########################################################################
Step 1 'Install .NET SDK'
if (Get-Command dotnet -ErrorAction SilentlyContinue) {
    $existing = & dotnet --list-sdks 2>$null | Select-String "^$DotnetChannel" -SimpleMatch
    if ($existing) { Info ".NET $DotnetChannel SDK already present: $existing" } else { $needInstall=$true }
} else { $needInstall=$true }

if ($needInstall) {
    $dotnetScript = "$env:TEMP\dotnet-install.ps1"
    Download "https://dot.net/v1/dotnet-install.ps1" $dotnetScript
    & powershell -ExecutionPolicy Bypass -File $dotnetScript -Channel $DotnetChannel -InstallDir 'C:\Program Files\dotnet'
    if ($LASTEXITCODE -ne 0) { Fail ".NET install failed with code $LASTEXITCODE" }
    $env:PATH += ';C:\Program Files\dotnet'
    Info ".NET installed. SDKs:`n$(dotnet --list-sdks)"
}

# Persist dotnet path for future sessions (machine-wide) even if already installed
$dotnetDir = 'C:\Program Files\dotnet'
try {
    $machinePath = [Environment]::GetEnvironmentVariable('Path','Machine')
    if (-not ($machinePath -split ';' | ForEach-Object { $_.TrimEnd('\\') } | Where-Object { $_ -ieq $dotnetDir })) {
        [Environment]::SetEnvironmentVariable('Path', ($machinePath.TrimEnd(';') + ';' + $dotnetDir), 'Machine')
        Info "Added $dotnetDir to Machine PATH"
    } else { Info "$dotnetDir already present in Machine PATH" }
    [Environment]::SetEnvironmentVariable('DOTNET_ROOT', $dotnetDir, 'Machine')
    Info 'DOTNET_ROOT machine environment variable set.'
} catch { Warn "Failed to persist dotnet path: $($_.Exception.Message)" }

###########################################################################
# 2. Install SQL Server 2022 Express (silent)
###########################################################################
Step 2 'Install SQL Server Express'
if (-not (Get-Service -Name "MSSQL`$${SqlInstanceName}" -ErrorAction SilentlyContinue)) {
    $bootstrap = "$env:TEMP\sqlexpress.exe"
    Download $SqlExpressUrl $bootstrap
    # Quiet install; enable TCP, set mixed mode, start Browser (full package, not lightweight downloader)
    $args = @(
        '/Q','/ACTION=Install','/FEATURES=SQLENGINE',
        "/INSTANCENAME=$SqlInstanceName",
        '/SECURITYMODE=SQL',"/SAPWD=$SaPassword",
        '/SQLSVCACCOUNT="NT AUTHORITY\\NETWORK SERVICE"',
        '/TCPENABLED=1','/NPENABLED=0','/BROWSERSVCSTARTUPTYPE=Automatic','/IACCEPTSQLSERVERLICENSETERMS'
    )
    Info "Starting SQL Express installer"
    $p = Start-Process -FilePath $bootstrap -ArgumentList $args -Wait -PassThru -WindowStyle Hidden
    if ($p.ExitCode -ne 0) { Fail "SQL Express installer exit code $($p.ExitCode)" }
    Info 'SQL Express installation process finished, waiting for service...'
} else { Info 'SQL Express already installed; skipping install.' }

Wait-For { Get-Service -Name "MSSQL`$${SqlInstanceName}" -ErrorAction SilentlyContinue } "SQL Service MSSQL$$SqlInstanceName present"
Wait-For { (Get-Service -Name "MSSQL`$${SqlInstanceName}").Status -eq 'Running' } 'SQL Service running'

###########################################################################
# 3. (Removed static port configuration – relying on SQL Browser & instance name)
###########################################################################
Step 3 'Skip static port (using instance name via SQL Browser)'
Info 'Static port configuration skipped; connections will use Server=localhost\SQLEXPRESS'

###########################################################################
# 4. Install modern sqlcmd (MSI download)
###########################################################################
Step 4 'Install modern sqlcmd'
if (-not (Test-Path $SqlCmdInstallDir)) { New-Item -ItemType Directory -Path $SqlCmdInstallDir | Out-Null }
$sqlcmdMsi = "$env:TEMP\sqlcmd-$SqlCmdVersion.msi"
$sqlcmdUrl = "https://github.com/microsoft/go-sqlcmd/releases/download/v$SqlCmdVersion/sqlcmd-amd64.msi"
if (-not (Get-Command sqlcmd -ErrorAction SilentlyContinue)) {
    Download $sqlcmdUrl $sqlcmdMsi
    $msiArgs = "/i `"$sqlcmdMsi`" /qn /norestart"
    Info "Installing sqlcmd MSI silently"
    $p = Start-Process msiexec.exe -ArgumentList $msiArgs -Wait -PassThru
    if ($p.ExitCode -ne 0) { Fail "sqlcmd MSI install failed with code $($p.ExitCode)" }
}

# Ensure path (typical install path contains sqlcmd.exe). Add default if not already accessible.
if (-not (Get-Command sqlcmd -ErrorAction SilentlyContinue)) {
    $possible = @(
        'C:\Program Files\sqlcmd',
        'C:\Program Files\Microsoft Sqlcmd'
    )
    foreach ($d in $possible) { if (Test-Path (Join-Path $d 'sqlcmd.exe')) { $env:PATH += ";$d" } }
}
Retry 'sqlcmd basic invocation' { & sqlcmd -? | Out-Null }
Info "sqlcmd version check succeeded."

###########################################################################
# 5. Create application DB + login
###########################################################################
Step 5 'Provision database & login'
$SqlServerInstance = "localhost\$SqlInstanceName"  # single backslash instance notation
Wait-For { Get-Service -Name 'SQLBrowser' -ErrorAction SilentlyContinue } 'SQL Browser service registered'
Wait-For { (Get-Service -Name 'SQLBrowser' -ErrorAction SilentlyContinue).Status -eq 'Running' } 'SQL Browser running'
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
Retry 'database/login provisioning' { 
    $provisionSql | & "$SqlCmdInstallDir\sqlcmd.exe" -S $SqlServerInstance -U sa -P $SaPassword -b
    if ($LASTEXITCODE -ne 0) { Fail "Provisioning sqlcmd exit code $LASTEXITCODE" }
}
Info 'Database and login provisioning completed.'

###########################################################################
# 6. Download application source
###########################################################################
Step 6 'Download application source'
$zipUrl  = 'https://github.com/tkubica12/MicroHack-AppInnovation/archive/refs/heads/main.zip'
$zipFile = 'C:\source.zip'
Download $zipUrl $zipFile
Expand-Archive -Path $zipFile -DestinationPath 'C:\' -Force

###########################################################################
# 7. Create start script
###########################################################################
Step 7 'Create start script'
$connStr = "Server=localhost\$SqlInstanceName;Database=$AppDbName;User Id=$AppLogin;Password=$AppPassword;Encrypt=True;TrustServerCertificate=True"
$startScriptLines = @(
    '# Auto-generated start script'
    "Set-Location 'C:\\MicroHack-AppInnovation-main\\dotnet'"
    "`$env:SQL_CONNECTION_STRING = '$connStr'"
    "`$env:ASPNETCORE_URLS = 'http://localhost:5000'"
    'dotnet run --project src/LegoCatalog.App/LegoCatalog.App.csproj'
)
$startScriptLines | Set-Content -Path 'C:\start-app.ps1' -Encoding UTF8
Info 'Start script created at C:\start-app.ps1'

###########################################################################
# 8. Connectivity test using app login
###########################################################################
Step 8 'Test app login connectivity'
Retry 'app login connectivity' { 
    & "$SqlCmdInstallDir\sqlcmd.exe" -S $SqlServerInstance -U $AppLogin -P $AppPassword -d $AppDbName -Q "SELECT TOP 1 name FROM sys.tables" -b | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail "App login sqlcmd exit code $LASTEXITCODE" }
}
Info 'App login connectivity succeeded.'

###########################################################################
# 9. Ensure app launches on interactive user logon
###########################################################################
Step 9 'Configure auto-start on user logon'

$taskName = 'LegoAppAutoStart'
$taskExists = $false
try { if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) { $taskExists = $true } } catch {}
if (-not $taskExists) {
    try {
        $trigger = New-ScheduledTaskTrigger -AtLogOn
        $action  = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\start-app.ps1"'
        $principal = New-ScheduledTaskPrincipal -GroupId 'BUILTIN\\Users' -RunLevel Highest
        Register-ScheduledTask -TaskName $taskName -Trigger $trigger -Action $action -Principal $principal -Description 'Start LegoCatalog app at user logon' | Out-Null
        Info "Scheduled task '$taskName' created (runs for any Users group logon)."
    } catch {
        Warn "Failed to create scheduled task ($($_.Exception.Message)). Will attempt startup folder shortcut fallback."
    }
} else { Info "Scheduled task '$taskName' already exists; skipping creation." }

# Fallback: startup folder shortcut so app starts for interactive sessions even if task failed or lacks rights
$startupFolder = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\StartUp'
if (Test-Path $startupFolder) {
    $shortcutPath = Join-Path $startupFolder 'Start Lego App.lnk'
    if (-not (Test-Path $shortcutPath)) {
        try {
            $ws = New-Object -ComObject WScript.Shell
            $sc = $ws.CreateShortcut($shortcutPath)
            $sc.TargetPath = 'powershell.exe'
            $sc.Arguments  = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\start-app.ps1"'
            $sc.WorkingDirectory = 'C:\'
            $sc.IconLocation = 'powershell.exe,0'
            $sc.Save()
            Info 'Startup folder shortcut created.'
        } catch { Warn "Failed to create startup shortcut: $($_.Exception.Message)" }
    } else { Info 'Startup folder shortcut already present.' }
} else { Warn "Startup folder not found: $startupFolder" }

Write-Host "`nAll steps completed successfully." -ForegroundColor Green

