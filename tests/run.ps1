$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $repoRoot 'src\EvidenceTools.ps1'
if (-not (Test-Path -LiteralPath $modulePath)) {
    throw "Missing implementation: $modulePath"
}
. $modulePath

function Assert-Equal {
    param(
        [Parameter(Mandatory)]$Actual,
        [Parameter(Mandatory)]$Expected,
        [Parameter(Mandatory)][string]$Message
    )
    if ($Actual -ne $Expected) {
        throw "$Message`nExpected: $Expected`nActual:   $Actual"
    }
}

function Assert-Contains {
    param(
        [Parameter(Mandatory)][string]$Actual,
        [Parameter(Mandatory)][string]$Expected,
        [Parameter(Mandatory)][string]$Message
    )
    if (-not $Actual.Contains($Expected)) {
        throw "$Message`nExpected substring: $Expected`nActual: $Actual"
    }
}

$fakeProfile = 'C:' + '\Users\' + 'Alice'
$fakeLongId = '1234567890' + '12345678'
$redacted = Protect-SensitiveText `
    -Text "host=GAMING-PC user=Alice path=$fakeProfile\AppData account=$fakeLongId" `
    -ComputerName 'GAMING-PC' `
    -UserName 'Alice' `
    -UserProfile $fakeProfile
Assert-Equal `
    -Actual $redacted `
    -Expected 'host=<COMPUTER> user=<USER> path=<USERPROFILE>\AppData account=<LONG_ID>' `
    -Message 'Sensitive text was not redacted as expected.'

$classification = Get-CrashClassification `
    -ModuleName 'graphics-hook64.dll' `
    -ModuleOffset 0x1AB89 `
    -ExceptionCode ([uint32]::Parse('C0000005', [System.Globalization.NumberStyles]::HexNumber))
Assert-Contains $classification 'graphics-hook64.dll+0x1AB89' 'Known overlay crash signature was not recognized.'
Assert-Contains $classification 'null COM pointer' 'Classification did not identify the confirmed null-pointer failure.'

$unknown = Get-CrashClassification `
    -ModuleName 'unknown.dll' `
    -ModuleOffset 0x42 `
    -ExceptionCode ([uint32]::Parse('C0000005', [System.Globalization.NumberStyles]::HexNumber))
Assert-Contains $unknown 'needs further analysis' 'Unknown signature must not be misclassified as confirmed.'

$fixtureRoot = Join-Path $PSScriptRoot 'runtime-fixture'
if (Test-Path -LiteralPath $fixtureRoot) {
    $resolvedFixture = [System.IO.Path]::GetFullPath($fixtureRoot)
    $resolvedTests = [System.IO.Path]::GetFullPath($PSScriptRoot)
    if (-not $resolvedFixture.StartsWith($resolvedTests, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to clean outside the test directory: $resolvedFixture"
    }
    Remove-Item -LiteralPath $resolvedFixture -Recurse -Force
}
New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
try {
    $baseTime = [datetime]'2026-07-25 11:43:47'
    0..5 | ForEach-Object {
        $name = if ($_ -eq 0) { 'crash-correlated.log' } else { "newest-$_.log" }
        $path = Join-Path $fixtureRoot $name
        "fixture-$_" | Set-Content -LiteralPath $path -Encoding UTF8
        (Get-Item -LiteralPath $path).LastWriteTime = if ($_ -eq 0) {
            $baseTime
        } else {
            $baseTime.AddHours($_)
        }
    }
    $selected = @(
        Select-EvidenceFiles `
            -Source $fixtureRoot `
            -Filter '*.log' `
            -RecentCount 4 `
            -ReferenceTime $baseTime `
            -ReferenceWindowMinutes 15
    )
    Assert-Equal $selected.Count 5 'Expected four newest files plus one crash-correlated file.'
    if ($selected.Name -notcontains 'crash-correlated.log') {
        throw 'Crash-correlated log was omitted.'
    }
} finally {
    if (Test-Path -LiteralPath $fixtureRoot) {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
    }
}

$collector = Join-Path $repoRoot 'tools\Collect-Evidence.ps1'
$collectorOutput = Join-Path $PSScriptRoot 'runtime-evidence'
if (Test-Path -LiteralPath $collectorOutput) {
    $resolvedCollectorOutput = [System.IO.Path]::GetFullPath($collectorOutput)
    $resolvedTests = [System.IO.Path]::GetFullPath($PSScriptRoot)
    if (-not $resolvedCollectorOutput.StartsWith($resolvedTests, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to clean outside the test directory: $resolvedCollectorOutput"
    }
    Remove-Item -LiteralPath $resolvedCollectorOutput -Recurse -Force
}
try {
    $runPath = @(
        & $collector -GameRoot '' -OutputRoot $collectorOutput -LookbackHours 1
    ) | Select-Object -Last 1
    if (-not (Test-Path -LiteralPath $runPath)) {
        throw "Collector did not create its output directory: $runPath"
    }
    if (Test-Path -LiteralPath (Join-Path $runPath 'raw-dumps')) {
        throw 'Default collector run copied raw dumps.'
    }
    if (Test-Path -LiteralPath (Join-Path $runPath 'redacted-log-tails')) {
        throw 'Default collector run exported log tails.'
    }
    $allText = Get-ChildItem -LiteralPath $runPath -File |
        ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw } |
        Out-String
    foreach ($privateValue in @($env:COMPUTERNAME, $env:USERNAME, $env:USERPROFILE)) {
        if (-not [string]::IsNullOrWhiteSpace($privateValue) -and
            $allText.IndexOf($privateValue, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            throw "Collector output contains an unredacted environment value: $privateValue"
        }
    }
} finally {
    if (Test-Path -LiteralPath $collectorOutput) {
        Remove-Item -LiteralPath $collectorOutput -Recurse -Force
    }
}

& (Join-Path $PSScriptRoot 'test-publication-safety.ps1')
Write-Host 'PASS: all tests'
