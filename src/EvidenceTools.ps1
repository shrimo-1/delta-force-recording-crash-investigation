function Select-EvidenceFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Source,
        [string]$Filter = '*.log',
        [ValidateRange(0, 100)]
        [int]$RecentCount = 4,
        [Nullable[datetime]]$ReferenceTime = $null,
        [ValidateRange(0, 1440)]
        [int]$ReferenceWindowMinutes = 15
    )

    if (-not (Test-Path -LiteralPath $Source)) { return }

    $allFiles = @(
        Get-ChildItem -LiteralPath $Source -File -Filter $Filter -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending
    )
    $selected = @($allFiles | Select-Object -First $RecentCount)

    if ($null -ne $ReferenceTime) {
        $windowStart = ([datetime]$ReferenceTime).AddMinutes(-$ReferenceWindowMinutes)
        $windowEnd = ([datetime]$ReferenceTime).AddMinutes($ReferenceWindowMinutes)
        $selected += @(
            $allFiles | Where-Object {
                $_.LastWriteTime -ge $windowStart -and
                $_.LastWriteTime -le $windowEnd
            }
        )
    }

    $seen = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $selected | Where-Object { $seen.Add($_.FullName) }
}

function Protect-SensitiveText {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Text,
        [string]$ComputerName = $env:COMPUTERNAME,
        [string]$UserName = $env:USERNAME,
        [string]$UserProfile = $env:USERPROFILE
    )

    if ($null -eq $Text) { return $null }
    $result = $Text

    if (-not [string]::IsNullOrWhiteSpace($UserProfile)) {
        $result = [regex]::Replace(
            $result,
            [regex]::Escape($UserProfile),
            '<USERPROFILE>',
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        )
    }
    if (-not [string]::IsNullOrWhiteSpace($ComputerName)) {
        $result = [regex]::Replace(
            $result,
            [regex]::Escape($ComputerName),
            '<COMPUTER>',
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        )
    }
    if (-not [string]::IsNullOrWhiteSpace($UserName)) {
        $result = [regex]::Replace(
            $result,
            [regex]::Escape($UserName),
            '<USER>',
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        )
    }

    $result = [regex]::Replace(
        $result,
        '(?<![0-9A-Za-z])\d{15,20}(?![0-9A-Za-z])',
        '<LONG_ID>'
    )
    return $result
}

function Get-MinidumpExceptionInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [ValidateRange(1, 512)]
        [int]$MaximumSizeMiB = 64
    )

    try {
        $file = Get-Item -LiteralPath $Path -ErrorAction Stop
        if ($file.Length -gt ($MaximumSizeMiB * 1MB)) { return $null }

        $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
        if ($bytes.Length -lt 32 -or
            [System.Text.Encoding]::ASCII.GetString($bytes, 0, 4) -ne 'MDMP') {
            return $null
        }

        $streamCount = [System.BitConverter]::ToUInt32($bytes, 8)
        $directoryRva = [System.BitConverter]::ToUInt32($bytes, 12)
        $exceptionRva = $null
        $moduleListRva = $null

        for ($index = 0; $index -lt $streamCount; $index++) {
            $entry = [int]$directoryRva + ($index * 12)
            if (($entry + 12) -gt $bytes.Length) { return $null }
            $streamType = [System.BitConverter]::ToUInt32($bytes, $entry)
            $streamRva = [System.BitConverter]::ToUInt32($bytes, $entry + 8)
            if ($streamType -eq 6) { $exceptionRva = $streamRva }
            if ($streamType -eq 4) { $moduleListRva = $streamRva }
        }
        if ($null -eq $exceptionRva -or ([int]$exceptionRva + 32) -gt $bytes.Length) {
            return $null
        }

        $exceptionCode = [System.BitConverter]::ToUInt32($bytes, [int]$exceptionRva + 8)
        $exceptionAddress = [System.BitConverter]::ToUInt64($bytes, [int]$exceptionRva + 24)
        $moduleName = $null
        $moduleOffset = $null

        if ($null -ne $moduleListRva -and ([int]$moduleListRva + 4) -le $bytes.Length) {
            $moduleCount = [System.BitConverter]::ToUInt32($bytes, [int]$moduleListRva)
            for ($index = 0; $index -lt $moduleCount; $index++) {
                $moduleEntry = [int]$moduleListRva + 4 + ($index * 108)
                if (($moduleEntry + 108) -gt $bytes.Length) { break }
                $moduleBase = [System.BitConverter]::ToUInt64($bytes, $moduleEntry)
                $moduleSize = [System.BitConverter]::ToUInt32($bytes, $moduleEntry + 8)
                if ($exceptionAddress -lt $moduleBase -or
                    $exceptionAddress -ge ($moduleBase + $moduleSize)) {
                    continue
                }

                $nameRva = [System.BitConverter]::ToUInt32($bytes, $moduleEntry + 20)
                if (([int]$nameRva + 4) -gt $bytes.Length) { break }
                $nameLength = [System.BitConverter]::ToUInt32($bytes, [int]$nameRva)
                if (([int]$nameRva + 4 + [int]$nameLength) -gt $bytes.Length) { break }
                $modulePath = [System.Text.Encoding]::Unicode.GetString(
                    $bytes,
                    [int]$nameRva + 4,
                    [int]$nameLength
                )
                $moduleName = [System.IO.Path]::GetFileName($modulePath)
                $moduleOffset = $exceptionAddress - $moduleBase
                break
            }
        }

        [pscustomobject]@{
            ExceptionCode = $exceptionCode
            ExceptionAddress = $exceptionAddress
            ModuleName = $moduleName
            ModuleOffset = $moduleOffset
        }
    } catch {
        return $null
    }
}

function Get-CrashClassification {
    [CmdletBinding()]
    param(
        [string]$ModuleName,
        [Nullable[uint64]]$ModuleOffset = $null,
        [Nullable[uint32]]$ExceptionCode = $null
    )

    $offsetText = if ($null -eq $ModuleOffset) {
        'unknown offset'
    } else {
        '0x{0:X}' -f [uint64]$ModuleOffset
    }
    $codeText = if ($null -eq $ExceptionCode) {
        'unknown exception'
    } else {
        '0x{0:X8}' -f [uint32]$ExceptionCode
    }

    if ($ModuleName -match '(?i)^graphics-hook64\.dll$' -and
        [uint64]$ModuleOffset -in 0x1AB42, 0x1AB89) {
        return "Known signature: graphics-hook64.dll+$offsetText, $codeText. " +
            'The overlay D3D12 upload path dereferenced a null COM pointer after an unchecked creation failure.'
    }
    if ($ModuleName -match '(?i)^graphics-hook64\.dll$') {
        return "graphics-hook64.dll+$offsetText, $codeText; this offset needs further analysis."
    }
    if ([string]::IsNullOrWhiteSpace($ModuleName)) {
        return 'No exception module was recovered; the crash needs further analysis.'
    }
    return "$ModuleName+$offsetText, $codeText; this signature needs further analysis."
}
