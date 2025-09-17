<#!
    setup.ps1 (orchestrator)

    Purpose:
      * Orchestrate modular installation scripts:
          - SQL_install.ps1 (stage: sql)
          - App_install.ps1 (stage: app)
          - Dev_install_initial.ps1 (stage: dev)
          - Dev_install_post_reboot.ps1 (stage: devpost - scheduled if reboot required)
      * Maintain status file C:\install_status.txt with simple key=value pairs
      * Schedule post-reboot task when WSL feature enablement requires reboot

    Status file format:
        sql= pending|running|failed|success
        app= ...
        dev= ...
        devpost= ...

    Notes:
        * This script itself performs no heavy installation logic.
        * Designed for idempotent / resumable execution - existing success statuses are skipped.
!#>

###########################################################################
# 0. Configuration (adjust if needed)
###########################################################################
param(
    [string]$LogDir = 'C:\InstallLogs'
)

## Basic configuration
$StatusFile          = 'C:\install_status.txt'
$SentinelFile        = 'C:\dev_reboot_required.txt'
$ScheduledTaskName   = 'DevPostInstall'
$ScriptRoot          = Split-Path -Parent $MyInvocation.MyCommand.Path
$SetupLog            = Join-Path $LogDir 'setup_orchestrator.log'
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

$ProgressPreference  = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

###########################################################################
# Helper Functions
###########################################################################
function Write-LogLine([string]$Level,[string]$Msg){ $ts = (Get-Date).ToString('s'); $line = "$ts [$Level] $Msg"; Add-Content -Path $SetupLog -Value $line }
function Info($m){ Write-Host "[SETUP] $m"; Write-LogLine 'INFO' $m }
function Warn($m){ Write-Warning "[SETUP] $m"; Write-LogLine 'WARN' $m }
function Fail($m){ Write-Error "[SETUP] $m"; Write-LogLine 'ERROR' $m; exit 1 }
# Update (or create) a single stage status line in the status file (atomic replacement)
function Update-StageStatus { param([string]$Stage,[string]$State)
    if (-not (Test-Path $StatusFile)) { "sql=pending`napp=pending`ndev=pending`ndevpost=pending" | Out-File -FilePath $StatusFile -Encoding ascii }
    $content = Get-Content $StatusFile
    $updated = $false
    $content = $content | ForEach-Object { if ($_ -match "^$Stage=") { $updated=$true; "$Stage=$State" } else { $_ } }
    if (-not $updated) { $content += "$Stage=$State" }
    $content | Set-Content -Path $StatusFile -Encoding ascii
}
function Get-StageStatus {
    param([string]$Stage)
    if (-not (Test-Path $StatusFile)) { return 'missing' }
    $line = (Get-Content $StatusFile | Where-Object { $_ -match "^$Stage=" })
    if (-not $line) { return 'missing' }
    return ($line -replace "^$Stage=","")
}
function Invoke-Stage {
    param([string]$Stage,[string]$Script)
    $current = Get-StageStatus -Stage $Stage
    if ($current -eq 'success') { Info "Stage $Stage already success - skipping."; return }
    Update-StageStatus -Stage $Stage -State 'running'
    $stageLog = Join-Path $LogDir ("${Stage}.log")
    Info "Starting stage $Stage ($Script) logging to $stageLog"
    $ps = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
    & $ps -NoLogo -NoProfile -ExecutionPolicy Bypass -File $Script -StatusFile $StatusFile -LogDir $LogDir *> $stageLog 2>&1
    $ec = $LASTEXITCODE
    if ($ec -ne 0) { Update-StageStatus -Stage $Stage -State 'failed'; Fail "Stage $Stage failed (exit $ec) - see $stageLog" }
    if ((Get-StageStatus -Stage $Stage) -ne 'success') { Update-StageStatus -Stage $Stage -State 'success' }
    Info "Stage $Stage completed."
}

###########################################################################
# Initialize status file if missing
###########################################################################
if (-not (Test-Path $StatusFile)) {
    Info "Creating initial status file."
    "sql=pending`napp=pending`ndev=pending`ndevpost=pending" | Out-File -FilePath $StatusFile -Encoding ascii
}

###########################################################################
# Execute stages
###########################################################################
Invoke-Stage -Stage 'sql' -Script (Join-Path $ScriptRoot 'SQL_install.ps1')
Invoke-Stage -Stage 'app' -Script (Join-Path $ScriptRoot 'App_install.ps1')
Invoke-Stage -Stage 'dev' -Script (Join-Path $ScriptRoot 'Dev_install_initial.ps1')

###########################################################################
# Schedule post-reboot dev tools installer if sentinel present
###########################################################################
if (Test-Path $SentinelFile) {
    if ((Get-StageStatus -Stage 'devpost') -ne 'success') {
        Info "Scheduling post-reboot dev tools stage."
        $postScript = (Join-Path $ScriptRoot 'Dev_install_post_reboot.ps1')
        # Create a short wrapper script to avoid exceeding schtasks /TR 261 char limit
        $runnerScript = 'C:\DevPostInstallRun.ps1'
        $runnerContent = @(
            '# Autogenerated wrapper for Dev_post stage'
            "& `"$postScript`" -StatusFile `"$StatusFile`" -LogDir `"$LogDir`""
        ) -join "`n"
        Set-Content -Path $runnerScript -Value $runnerContent -Encoding ASCII
        Info "Created wrapper script $runnerScript"
        # Use short command line
        schtasks /Create /TN $ScheduledTaskName /TR "powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $runnerScript" /SC ONSTART /RU SYSTEM /RL HIGHEST /F | Out-Null
        Info "Scheduled task $ScheduledTaskName with short /TR. Reboot in 60 seconds to continue with devpost stage."
        shutdown.exe /r /t 60 /c "Reboot after enabling WSL features" | Out-Null
    } else { Info "devpost already success - no scheduling needed." }
} else { Info "No reboot required for dev tools (devpost stage not scheduled)." }

Info "Orchestration complete."
exit 0

