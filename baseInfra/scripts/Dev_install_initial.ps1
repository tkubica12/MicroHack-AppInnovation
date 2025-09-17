<#!
    Dev_install_initial.ps1

    Purpose:
    * Enable WSL + VirtualMachinePlatform features
      * Mark status (stage: dev)
      * If reboot required create sentinel file for orchestrator scheduling
!#>

param(
    [string]$StatusFile = 'C:\install_status.txt',
    [string]$SentinelFile = 'C:\dev_reboot_required.txt',
    [string]$LogDir = 'C:\InstallLogs'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
$LogFile = Join-Path $LogDir 'Dev_install_initial.log'
$ProgressPreference = 'SilentlyContinue'

function LogLine([string]$Level,[string]$Msg){ $ts=(Get-Date).ToString('s'); Add-Content -Path $LogFile -Value "$ts [$Level] $Msg" }
function Info($m){ Write-Host "[DEV-INIT] $m"; LogLine 'INFO' $m }
function Warn($m){ Write-Warning "[DEV-INIT] $m"; LogLine 'WARN' $m }
function Fail($m){ Write-Error "[DEV-INIT] $m"; LogLine 'ERROR' $m; Update-StageStatus -Stage 'dev' -State 'failed'; exit 1 }
function Update-StageStatus { param([string]$Stage,[string]$State)
    if (-not (Test-Path $StatusFile)) { "sql=pending`napp=pending`ndev=pending`ndevpost=pending" | Out-File -FilePath $StatusFile -Encoding ascii }
    $content = Get-Content $StatusFile
    $updated = $false
    $content = $content | ForEach-Object { if ($_ -match "^$Stage=") { $updated=$true; "$Stage=$State" } else { $_ } }
    if (-not $updated) { $content += "$Stage=$State" }
    $content | Set-Content -Path $StatusFile -Encoding ascii
}

Update-StageStatus -Stage 'dev' -State 'running'

function Ensure-FeatureEnabled {
    param([string]$FeatureName)
    $info = & dism /online /Get-FeatureInfo /FeatureName:$FeatureName 2>&1
    if ($LASTEXITCODE -ne 0) { Warn "Cannot query $FeatureName (exit $LASTEXITCODE)"; return $false }
    if ($info -match 'State : Enabled') { Info "$FeatureName already enabled"; return $false }
    Info "Enabling $FeatureName"
    & dism /online /Enable-Feature /FeatureName:$FeatureName /All /NoRestart | Out-Null
    $ec = $LASTEXITCODE
    if ($ec -eq 3010) { Info "$FeatureName enabled (reboot required)"; return $true }
    elseif ($ec -ne 0) { Fail "Failed enabling $FeatureName (exit $ec)" }
    return $true
}

$changedWSL = Ensure-FeatureEnabled -FeatureName 'Microsoft-Windows-Subsystem-Linux'
$changedVMP = Ensure-FeatureEnabled -FeatureName 'VirtualMachinePlatform'
if ($changedWSL -or $changedVMP) {
    'reboot-required' | Out-File -FilePath $SentinelFile -Encoding ascii
    Info 'Reboot required sentinel created.'
} else { Info 'No reboot required for dev initial.' }

Update-StageStatus -Stage 'dev' -State 'success'
Info 'Dev initial stage completed.'
exit 0
