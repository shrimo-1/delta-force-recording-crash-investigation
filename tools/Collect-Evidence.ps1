[CmdletBinding()]
param(
    [string]$GameRoot = $env:DELTA_FORCE_ROOT,
    [string]$OutputRoot = '',
    [ValidateRange(1, 720)]
    [int]$LookbackHours = 168,
    [switch]$IncludeLogTails,
    [switch]$IncludeDumps,
    [ValidateRange(1, 128)]
    [int]$MaximumDumpMiB = 32
)

$ErrorActionPreference = 'Continue'
$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $repoRoot 'src\EvidenceTools.ps1')

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $repoRoot 'evidence'
}
$runRoot = Join-Path $OutputRoot (Get-Date -Format 'yyyyMMdd_HHmmss')
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null

function Write-SafeText {
    param(
        [Parameter(Mandatory)][string]$Path,
        [AllowEmptyString()][string]$Text
    )
    Protect-SensitiveText -Text $Text |
        Set-Content -LiteralPath $Path -Encoding UTF8
}

function Write-SafeSection {
    param(
        [Parameter(Mandatory)][string]$Title,
        [object]$Data,
        [Parameter(Mandatory)][string]$Path
    )
    $text = "===== $Title =====`r`n" + ($Data | Out-String -Width 4096)
    Write-SafeText -Path $Path -Text $text
}

function Get-RecentFiles {
    param(
        [string]$Root,
        [string]$Filter,
        [datetime]$Since,
        [int]$Count = 8
    )
    if (-not (Test-Path -LiteralPath $Root -ErrorAction SilentlyContinue)) { return }
    Get-ChildItem -LiteralPath $Root -File -Filter $Filter -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $Since } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First $Count
}

function Copy-OptionalDump {
    param(
        [System.IO.FileInfo]$File,
        [string]$Destination
    )
    if (-not $IncludeDumps -or $null -eq $File) { return $false }
    if ($File.Length -gt ($MaximumDumpMiB * 1MB)) { return $false }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Copy-Item -LiteralPath $File.FullName -Destination $Destination -Force
    return $true
}

function Export-RedactedLogTail {
    param(
        [System.IO.FileInfo]$File,
        [string]$Destination,
        [int]$LineCount = 4000
    )
    if ($null -eq $File) { return }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    $tail = Get-Content -LiteralPath $File.FullName -Tail $LineCount -ErrorAction SilentlyContinue |
        Out-String -Width 4096
    $target = Join-Path $Destination ($File.BaseName + '.redacted.txt')
    Write-SafeText -Path $target -Text $tail
}

$since = (Get-Date).AddHours(-$LookbackHours)
$summary = @(
    "Collected: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')"
    "LookbackHours: $LookbackHours"
    'Mode: read-only system queries; output is written only to the selected evidence directory.'
    'Privacy: computer name, user name, user profile and 15-20 digit IDs are redacted from text.'
    "Raw log tails requested: $([bool]$IncludeLogTails)"
    "Raw dumps requested: $([bool]$IncludeDumps)"
    'Raw dumps may contain private data and are never copied unless -IncludeDumps is supplied.'
)
Write-SafeText -Path (Join-Path $runRoot 'summary.txt') -Text ($summary -join "`r`n")

$systemInfo = @()
$systemInfo += Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue |
    Select-Object Caption, Version, BuildNumber, LastBootUpTime
$systemInfo += Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue |
    Select-Object Name, NumberOfCores, NumberOfLogicalProcessors
$systemInfo += Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
    Select-Object Name, DriverVersion, DriverDate, AdapterRAM
Write-SafeSection -Title 'System and graphics' -Data $systemInfo `
    -Path (Join-Path $runRoot 'system-info.txt')

$applicationEvents = Get-WinEvent -FilterHashtable @{
    LogName = 'Application'
    StartTime = $since
} -ErrorAction SilentlyContinue | Where-Object {
    $_.Id -in 1000, 1001, 1002 -and
    $_.Message -match 'DeltaForceClient-Win64-Shipping|graphics-hook64|icreate|nvwgf2umx'
} | Select-Object TimeCreated, Id, ProviderName, LevelDisplayName, Message
Write-SafeSection -Title 'Relevant application events' -Data $applicationEvents `
    -Path (Join-Path $runRoot 'application-events.txt')

$displayEvents = Get-WinEvent -FilterHashtable @{
    LogName = 'System'
    StartTime = $since
} -ErrorAction SilentlyContinue | Where-Object {
    $_.Id -in 141, 153, 4101 -or
    $_.ProviderName -match 'Display|nvlddmkm|WHEA'
} | Select-Object TimeCreated, Id, ProviderName, LevelDisplayName, Message
Write-SafeSection -Title 'GPU, display and WHEA events' -Data $displayEvents `
    -Path (Join-Path $runRoot 'display-events.txt')

$crashDumps = @()
$latestDump = $null
if (-not [string]::IsNullOrWhiteSpace($GameRoot)) {
    $crashDumpRoot = Join-Path $GameRoot 'Binaries\Win64\CrashSight64\dump'
    $crashDumps = @(Get-RecentFiles -Root $crashDumpRoot -Filter '*.dmp' -Since $since -Count 8)
    $latestDump = $crashDumps | Select-Object -First 1
}

$dumpRows = foreach ($dump in $crashDumps) {
    [pscustomobject]@{
        Path = $dump.FullName
        Length = $dump.Length
        LastWriteTime = $dump.LastWriteTime
        SHA256 = (Get-FileHash -LiteralPath $dump.FullName -Algorithm SHA256).Hash
    }
}
Write-SafeSection -Title 'CrashSight dump index' -Data $dumpRows `
    -Path (Join-Path $runRoot 'crash-dump-index.txt')

$classification = if ($latestDump) {
    $info = Get-MinidumpExceptionInfo -Path $latestDump.FullName
    if ($info) {
        Get-CrashClassification `
            -ModuleName $info.ModuleName `
            -ModuleOffset $info.ModuleOffset `
            -ExceptionCode $info.ExceptionCode
    } else {
        'Latest dump could not be parsed by the lightweight parser; use WinDbg for further analysis.'
    }
} else {
    'No recent CrashSight dump was found. Set -GameRoot or DELTA_FORCE_ROOT if the game is installed elsewhere.'
}
Write-SafeText -Path (Join-Path $runRoot 'classification.txt') -Text $classification

if ($latestDump) {
    [void](Copy-OptionalDump -File $latestDump -Destination (Join-Path $runRoot 'raw-dumps'))
}

$watchdogRoot = Join-Path $env:SystemRoot 'LiveKernelReports\WATCHDOG'
$watchdogs = @(Get-RecentFiles -Root $watchdogRoot -Filter 'WATCHDOG-*.dmp' -Since $since -Count 3)
$watchdogRows = foreach ($dump in $watchdogs) {
    [pscustomobject]@{
        Path = $dump.FullName
        Length = $dump.Length
        LastWriteTime = $dump.LastWriteTime
        SHA256 = (Get-FileHash -LiteralPath $dump.FullName -Algorithm SHA256).Hash
    }
}
Write-SafeSection -Title 'WATCHDOG dump index' -Data $watchdogRows `
    -Path (Join-Path $runRoot 'watchdog-dump-index.txt')
foreach ($dump in $watchdogs) {
    [void](Copy-OptionalDump -File $dump -Destination (Join-Path $runRoot 'raw-dumps'))
}

$processes = Get-Process -ErrorAction SilentlyContinue | Where-Object {
    $_.ProcessName -match 'DeltaForce|WeGame|icreate|NVIDIA|nvcontainer'
} | Select-Object ProcessName, Id, StartTime, Path
Write-SafeSection -Title 'Related process snapshot' -Data $processes `
    -Path (Join-Path $runRoot 'process-snapshot.txt')

if ($IncludeLogTails) {
    $iCreateRoot = Join-Path $env:LOCALAPPDATA 'icreate-sdk\deltaforce'
    $iCreateLogs = @(
        Get-RecentFiles -Root $iCreateRoot -Filter '*.txt' -Since $since -Count 4
        Get-RecentFiles -Root (Join-Path $iCreateRoot 'iCreateLogs') -Filter '*.txt' -Since $since -Count 4
        Get-RecentFiles -Root (Join-Path $iCreateRoot 'iCreateLogs\rec\logs') -Filter '*.txt' -Since $since -Count 4
    ) | Sort-Object FullName -Unique
    foreach ($log in $iCreateLogs) {
        Export-RedactedLogTail -File $log -Destination (Join-Path $runRoot 'redacted-log-tails')
    }
}

Write-Host "Evidence saved to: $runRoot"
Write-Output $runRoot
