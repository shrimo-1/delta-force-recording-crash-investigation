$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$allowedExtensions = @(
    '', '.bat', '.gitignore', '.json', '.md', '.ps1', '.yml', '.yaml'
)
$failures = [System.Collections.Generic.List[string]]::new()

Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Force |
    Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' } |
    ForEach-Object {
        if ($allowedExtensions -notcontains $_.Extension.ToLowerInvariant()) {
            $failures.Add("Disallowed publication file type: $($_.FullName)")
            return
        }

        $text = Get-Content -LiteralPath $_.FullName -Raw -ErrorAction Stop
        if ($_.Extension -eq '.ps1') {
            $tokens = $null
            $parseErrors = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile(
                $_.FullName,
                [ref]$tokens,
                [ref]$parseErrors
            )
            foreach ($parseError in $parseErrors) {
                $failures.Add("PowerShell parse error in $($_.FullName): $($parseError.Message)")
            }
        }
        $checks = @(
            @{ Pattern = '(?i)github_pat_[A-Za-z0-9_]+'; Label = 'GitHub token' },
            @{ Pattern = '(?i)ghp_[A-Za-z0-9]{20,}'; Label = 'GitHub token' },
            @{ Pattern = '(?i)AKIA[0-9A-Z]{16}'; Label = 'AWS access key' },
            @{ Pattern = '(?i)C:\\Users\\(?!<USER>)'; Label = 'real user profile path' },
            @{ Pattern = '(?<![0-9A-Fa-f])\d{15,20}(?![0-9A-Fa-f])'; Label = 'possible account or device ID' },
            @{ Pattern = '(?<!\w)1[3-9]\d{9}(?!\w)'; Label = 'possible phone number' }
        )
        foreach ($check in $checks) {
            if ($text -match $check.Pattern) {
                $failures.Add("$($check.Label)：$($_.FullName)")
            }
        }
    }

if ($failures.Count -gt 0) {
    throw "Publication safety scan failed:`n$($failures -join "`n")"
}

Write-Host 'PASS: publication safety scan'
