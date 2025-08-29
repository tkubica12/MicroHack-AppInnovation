$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

function Write-Section($msg) { Write-Host "`n==== $msg ====`n" }

function Wait-ForCondition {
    param(
        [Parameter(Mandatory)] [scriptblock]$Condition,
        [Parameter(Mandatory)] [string]$Description,
        [int]$TimeoutSec = 900,
        [int]$IntervalSec = 10
    )
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
        try {
            if (& $Condition) { Write-Host "[OK] $Description"; return }
        } catch { }
        Start-Sleep -Seconds $IntervalSec
    }
    throw "Timeout waiting for: $Description"
}

function Invoke-WithRetry {
    param(
        [Parameter(Mandatory)] [scriptblock]$Action,
        [int]$Retries = 10,
        [int]$DelaySec = 10,
        [string]$Description = 'operation'
    )
    for ($i=1; $i -le $Retries; $i++) {
        try {
            & $Action
            Write-Host "[OK] $Description (attempt $i)"
            return
        } catch {
            Write-Warning "Failed $Description (attempt $i/$Retries): $($_.Exception.Message)"
            if ($i -eq $Retries) { throw }
            Start-Sleep -Seconds $DelaySec
        }
    }
}

Write-Section 'Installing .NET 8'
winget install Microsoft.DotNet.SDK.8 --accept-package-agreements --accept-source-agreements -e --silent 

Write-Section 'Installing SQL Server 2022 Express (may take several minutes)'
winget install --id=Microsoft.SQLServer.2022.Express --accept-package-agreements --accept-source-agreements -e --silent 

# Install modern sqlcmd
Write-Section 'Installing modern sqlcmd & prerequisites'
winget install sqlcmd --accept-package-agreements --accept-source-agreements -e --silent 
winget install "Microsoft ODBC Driver 18 for SQL Server" --accept-package-agreements --accept-source-agreements -e --silent
winget install "Microsoft.VCRedist.2015+.x64" --accept-package-agreements --accept-source-agreements -e --silent

# Add sqlcmd to PATH for current session (hardcoded path kept intentionally)
$env:PATH += ";C:\Program Files\sqlcmd"

# Registry path for TCP/IP settings (hardcoded path kept intentionally)
$tcpRegPath = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL16.SQLEXPRESS\MSSQLServer\SuperSocketNetLib\Tcp\IPAll"
Wait-ForCondition { Test-Path $tcpRegPath } "SQL Server TCP registry path present"

# Enable TCP/IP
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL16.SQLEXPRESS\MSSQLServer\SuperSocketNetLib\Tcp" -Name "Enabled" -Value 1

# Set static port 1433 and clear dynamic ports
Set-ItemProperty -Path $tcpRegPath -Name "TcpPort" -Value "1433"
Set-ItemProperty -Path $tcpRegPath -Name "TcpDynamicPorts" -Value ""

# Enable mixed mode
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL16.SQLEXPRESS\MSSQLServer" -Name "LoginMode" -Value 2

Wait-ForCondition { Get-Service -Name "MSSQL`$SQLEXPRESS" -ErrorAction SilentlyContinue } 'SQL Server service registered'

Write-Section 'Restarting SQL Server service'
Restart-Service -Name "MSSQL`$SQLEXPRESS" -Force
Wait-ForCondition { (Get-Service -Name "MSSQL`$SQLEXPRESS").Status -eq 'Running' } 'SQL Server service running'

# Test connection to SQL Server with retry
Invoke-WithRetry -Description 'basic SQL connectivity test' -Retries 30 -DelaySec 10 -Action {
    & sqlcmd -S localhost,1433 -E -Q "SELECT 1" 1>$null 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'sqlcmd returned non-zero exit code' }
}
Write-Host "SQL Server connection test succeeded."

# Define variables
$dbName = "LegoCatalog"
$sqlLogin = "legoapp"
$sqlPassword = "Azure12345678"

# SQL script to create DB, login, and user
$sql = @"
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = N'$dbName')
BEGIN
    CREATE DATABASE [$dbName];
END;

GO

USE [$dbName];

IF NOT EXISTS (SELECT name FROM sys.sql_logins WHERE name = N'$sqlLogin')
BEGIN
    CREATE LOGIN [$sqlLogin] WITH PASSWORD = N'$sqlPassword', CHECK_POLICY = ON;
END;

GO

IF NOT EXISTS (SELECT name FROM sys.database_principals WHERE name = N'$sqlLogin')
BEGIN
    CREATE USER [$sqlLogin] FOR LOGIN [$sqlLogin];
    EXEC sp_addrolemember N'db_owner', N'$sqlLogin';
END;

GO
"@

# Execute the SQL script with retry
Write-Host "Creating database '$dbName' and SQL login '$sqlLogin' (retry logic)."
Invoke-WithRetry -Description 'DB / login provisioning' -Retries 12 -DelaySec 10 -Action {
    $sql | sqlcmd -S localhost,1433 -E -b
    if ($LASTEXITCODE -ne 0) { throw "Provisioning script failed with code $LASTEXITCODE" }
}

$sqlTestQuery = "SELECT name FROM sys.databases WHERE name = '$dbName';"
$sqlcmdArgs = @(
    "-S", "localhost,1433",
    "-U", $sqlLogin,
    "-P", $sqlPassword,
    "-d", $dbName,
    "-Q", $sqlTestQuery
)

& sqlcmd @sqlcmdArgs 1>$null 2>$null

if ($LASTEXITCODE -eq 0) {
    Write-Host "SQL login test succeeded: user '$sqlLogin' can access database '$dbName'."
} else {
    Write-Warning "SQL login test failed: user '$sqlLogin' could not access database '$dbName'."
}


# Download app
Write-Host 'Downloading application source code'
$zipUrl  = 'https://github.com/tkubica12/MicroHack-AppInnovation/archive/refs/heads/main.zip'
$zipFile = 'C:\source.zip'
Invoke-WebRequest -Uri $ZipUrl -OutFile $zipFile -UseBasicParsing
Expand-Archive -Path $zipFile -DestinationPath 'C:\' -Force

# Start script
Write-Host 'Creating start script'
# Fixed connection string (removed stray dot, added explicit port)
$connStr = "Server=localhost,1433;Database=$dbName;User Id=$sqlLogin;Password=$sqlPassword;Encrypt=True;TrustServerCertificate=True"

# Build start script lines explicitly to avoid premature variable expansion inside here-strings
$startScriptLines = @(
    '# Auto-generated start script'
    "Set-Location 'C:\\MicroHack-AppInnovation-main\\dotnet'"
    "`$env:SQL_CONNECTION_STRING = '$connStr'"
    "`$env:ASPNETCORE_URLS = 'http://localhost:5000'"
    'dotnet run --project src/LegoCatalog.App/LegoCatalog.App.csproj'
)
$startScriptLines | Set-Content -Path 'C:\start-app.ps1' -Encoding UTF8
Write-Host "Start script created at C:\start-app.ps1"

Write-Host 'Provisioning complete.'
