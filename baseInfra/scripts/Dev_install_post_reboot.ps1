<#!
    Dev_install_post_reboot.ps1

    Purpose:
    * Run after reboot to install development tools via winget
      * Update status file (stage: devpost)
      * Remove scheduled task + sentinel
!#>

param(
    [string]$StatusFile = 'C:\install_status.txt',
    [string]$SentinelFile = 'C:\dev_reboot_required.txt',
    [string]$ScheduledTaskName = 'DevPostInstall',
    [string]$LogDir = 'C:\InstallLogs',
    [int]$WingetMaxRetries = 12,          # total attempts to locate winget (approx 2 min if 10s delay)
    [int]$WingetDelaySec   = 10           # delay between attempts
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
$LogFile = Join-Path $LogDir 'Dev_install_post_reboot.log'
$ProgressPreference = 'SilentlyContinue'

function LogLine([string]$Level,[string]$Msg){ $ts=(Get-Date).ToString('s'); Add-Content -Path $LogFile -Value "$ts [$Level] $Msg" }
function Info($m){ Write-Host "[DEV-POST] $m"; LogLine 'INFO' $m }
function Warn($m){ Write-Warning "[DEV-POST] $m"; LogLine 'WARN' $m }
function Fail($m){ Write-Error "[DEV-POST] $m"; LogLine 'ERROR' $m; Update-StageStatus -Stage 'devpost' -State 'failed'; exit 1 }
function Update-StageStatus { param([string]$Stage,[string]$State)
    if (-not (Test-Path $StatusFile)) { "sql=pending`napp=pending`ndev=pending`ndevpost=pending" | Out-File -FilePath $StatusFile -Encoding ascii }
    $content = Get-Content $StatusFile
    $updated = $false
    $content = $content | ForEach-Object { if ($_ -match "^$Stage=") { $updated=$true; "$Stage=$State" } else { $_ } }
    if (-not $updated) { $content += "$Stage=$State" }
    $content | Set-Content -Path $StatusFile -Encoding ascii
}

Update-StageStatus -Stage 'devpost' -State 'running'

function Resolve-WingetPath {
    try {
        $cmd = Get-Command winget -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    } catch {}
    $winApps = Join-Path $env:ProgramFiles 'WindowsApps'
    if (Test-Path $winApps) {
        $candidate = Get-ChildItem -Path $winApps -Filter 'winget.exe' -Recurse -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($candidate) { return $candidate.FullName }
    }
    return $null
}

function Install-Pkg {
    param(
        [string]$WingetPath,
        [string]$Id,
        [switch]$MachineScope,
        [string]$FallbackUrl
    )
    Write-Host "[DevTools] Installing $Id";
    $args = @('install', "--id=$Id", '-e', '--accept-package-agreements', '--accept-source-agreements', '-h')
    if ($MachineScope) { $args += '--scope'; $args += 'machine' }
    try {
        & $WingetPath @args
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "[DevTools] winget exit code $LASTEXITCODE for $Id"
            if ($MachineScope -and $FallbackUrl) {
                Write-Warning "[DevTools] Attempting fallback system installer for $Id from $FallbackUrl"
                $tmp = Join-Path $env:TEMP (Split-Path $FallbackUrl -Leaf)
                try {
                    Invoke-WebRequest -Uri $FallbackUrl -OutFile $tmp -UseBasicParsing -ErrorAction Stop
                    Start-Process $tmp -ArgumentList '/VERYSILENT','/NORESTART' -Wait -NoNewWindow
                } catch { Write-Warning "[DevTools] Fallback install failed for $Id : $($_.Exception.Message)" }
            }
        }
    } catch {
        Write-Warning "[DevTools] Exception installing $Id : $($_.Exception.Message)"
        if ($MachineScope -and $FallbackUrl) {
            Write-Warning "[DevTools] Attempting fallback system installer for $Id after exception"
            $tmp = Join-Path $env:TEMP (Split-Path $FallbackUrl -Leaf)
            try {
                Invoke-WebRequest -Uri $FallbackUrl -OutFile $tmp -UseBasicParsing -ErrorAction Stop
                Start-Process $tmp -ArgumentList '/VERYSILENT','/NORESTART' -Wait -NoNewWindow
            } catch { Write-Warning "[DevTools] Fallback install failed for $Id : $($_.Exception.Message)" }
        }
    }
}

# Retry to locate winget (may not yet be in PATH under SYSTEM at early boot)
$wingetPath = $null
for($attempt=1; $attempt -le $WingetMaxRetries; $attempt++){
    $wingetPath = Resolve-WingetPath
    if ($wingetPath) { Info "winget resolved at $wingetPath (attempt $attempt)"; break }
    Info "winget not found (attempt $attempt/$WingetMaxRetries); waiting $WingetDelaySec s"
    Start-Sleep -Seconds $WingetDelaySec
}

if (-not $wingetPath) {
    Fail "winget not found after $WingetMaxRetries attempts; leaving task & sentinel for retry."
}

Install-Pkg $wingetPath 'Microsoft.VisualStudioCode' -MachineScope -FallbackUrl 'https://update.code.visualstudio.com/latest/win32-x64-user/stable'
Install-Pkg $wingetPath 'Microsoft.AzureCLI'
Install-Pkg $wingetPath 'SUSE.RancherDesktop'
Install-Pkg $wingetPath 'Microsoft.SQLServerManagementStudio'
Install-Pkg $wingetPath 'Git.Git'
Install-Pkg $wingetPath 'Python.Python.3.13'
Install-Pkg $wingetPath 'astral-sh.uv'

Update-StageStatus -Stage 'devpost' -State 'success'
Info 'Dev post-reboot stage completed.'

if (Test-Path $SentinelFile) { Remove-Item $SentinelFile -Force }
try { schtasks /Delete /TN $ScheduledTaskName /F | Out-Null } catch { }

exit 0
