[CmdletBinding()]
param (
    [Parameter(Position = 0)]
    [Alias('search', 'find', 'findText', 'st', 'ft')]
    [string[]]$searchText = @(),

    [Parameter(Position = 1)]
    [Alias('replace', 'displace', 'rt')]
    [string[]]$replaceText = @(),

    [Alias('modifier', 'm')]
    [string]$flags = '',

    [Alias('applyToFile', 'readFromFile', 'ff', 'files')]
    [string[]]$fromFile = @(),

    [Alias('ignoreCase', 'ic', 'noCase', 'i')]
    [switch]$ci,

    [Alias('regEx', 'regExP')]
    [switch]$r,

    [Alias('grep', 'filter', 'x', 'extract', 'g')]
    [switch]$extractMatch,

    [Alias('d', 'del', 'remove')]
    [switch]$delete,

    [Alias('fullFile', 'f')]
    [switch]$wholeFile,

    [Alias('raw', 'onlyMatches', 'plainGrep', 'pg', 'sep', 'separator')]
    [string]$plain,

    [Alias('w', 'save', 'write')]
    [switch]$fileOutput,

    [Alias('saveAs', 'o', 'out')]
    [string]$fileName = '',

    [Alias('h', 'hint', 'usage')]
    [switch]$Help
)

function Show-HelpText {
    @'
clipGre.ps1 - Search, filter, and replace clipboard or file text

Usage:
  clipGre.ps1 <search> [replacement] [-r] [-i] [-g] [-d] [-ff <path>]

Options:
  -search / -st       Search text (multiple patterns are supported)
  -replace / -rt      Replacement text(s), paired by index with search patterns
  -r                  Interpret search patterns as .NET regular expressions
  -m / -flags         Regex options: i, m, s, x (also enables regex mode)
  -i                  Ignore case
  -g                  Print matching lines (or exact matches with -plain)
  -d                  Delete matches
  -ff / -files        Read one or more files or directories instead of the clipboard
  -f                  Treat input as one whole text rather than line-oriented grep
  -w / -write         Save output to a file
  -o / -saveAs        Set the output filename (a timestamp is appended)
  -h / -help          Show this help
'@ | Write-Host
}

if ($Help) {
    Show-HelpText
    return
}

if ($flags) {
    $r = $true
}
if (-not $searchText -or $searchText.Count -eq 0) {
    throw 'Provide at least one search pattern.'
}
if ($delete) {
    $replaceText = @('') * $searchText.Count
}
elseif (-not $extractMatch -and $replaceText.Count -eq 0) {
    $extractMatch = $true
}
if (-not $extractMatch -and $replaceText.Count -lt $searchText.Count) {
    $replaceText += @('') * ($searchText.Count - $replaceText.Count)
}

$options = [System.Text.RegularExpressions.RegexOptions]::None
if ($ci -or $flags.Contains('i')) { $options = $options -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase }
if ($flags.Contains('m')) { $options = $options -bor [System.Text.RegularExpressions.RegexOptions]::Multiline }
if ($flags.Contains('s')) { $options = $options -bor [System.Text.RegularExpressions.RegexOptions]::Singleline }
if ($flags.Contains('x')) { $options = $options -bor [System.Text.RegularExpressions.RegexOptions]::IgnorePatternWhitespace }

$targets = @()
if ($fromFile.Count -gt 0) {
    foreach ($path in $fromFile) {
        if (-not (Test-Path -LiteralPath $path)) {
            Write-Warning "Path not found: $path"
            continue
        }
        $item = Get-Item -LiteralPath $path
        if ($item.PSIsContainer) {
            $targets += Get-ChildItem -LiteralPath $path -File -Recurse:$false | Select-Object -ExpandProperty FullName
        }
        else {
            $targets += $item.FullName
        }
    }
}

$inputTexts = @()
if ($targets.Count -gt 0) {
    foreach ($path in $targets) {
        try {
            $inputTexts += [pscustomobject]@{ Name = $path; Text = (Get-Content -LiteralPath $path -Raw -ErrorAction Stop) }
        }
        catch {
            Write-Warning "Could not read '$path': $_"
        }
    }
}
else {
    $clipboardText = Get-Clipboard -Raw
    $inputTexts += [pscustomobject]@{ Name = 'clipboard'; Text = [string]$clipboardText }
}

$results = foreach ($input in $inputTexts) {
    $text = [string]$input.Text
    if ($extractMatch) {
        if ($PSBoundParameters.ContainsKey('plain')) {
            $matches = foreach ($pattern in $searchText) {
                $effectivePattern = if ($r) { $pattern } else { [regex]::Escape($pattern) }
                [regex]::Matches($text, $effectivePattern, $options) | ForEach-Object { $_.Value }
            }
            $matches -join $plain
        }
        else {
            $lines = $text -split "`r?`n"
            for ($lineNumber = 0; $lineNumber -lt $lines.Count; $lineNumber++) {
                foreach ($pattern in $searchText) {
                    $effectivePattern = if ($r) { $pattern } else { [regex]::Escape($pattern) }
                    if ([regex]::IsMatch($lines[$lineNumber], $effectivePattern, $options)) {
                        '{0}: {1}' -f ($lineNumber + 1), $lines[$lineNumber]
                        break
                    }
                }
            }
        }
    }
    else {
        foreach ($index in 0..($searchText.Count - 1)) {
            $pattern = if ($r) { $searchText[$index] } else { [regex]::Escape($searchText[$index]) }
            $text = [regex]::Replace($text, $pattern, [string]$replaceText[$index], $options)
        }
        $text
    }
}

$resultText = $results -join [Environment]::NewLine
if ($fileOutput) {
    if ([string]::IsNullOrWhiteSpace($fileName)) {
        $fileName = 'Output'
    }
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
    $outputPath = '{0}_{1}.txt' -f $baseName, (Get-Date -Format 'yyyyMMdd_HHmmss')
    Set-Content -LiteralPath $outputPath -Value $resultText -Encoding UTF8
    Write-Host "Results saved in file: $outputPath"
}
elseif ($targets.Count -gt 0) {
    $resultText
}
else {
    Set-Clipboard -Value $resultText
    Write-Host 'Clipboard updated.'
}
