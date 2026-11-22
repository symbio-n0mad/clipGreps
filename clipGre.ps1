<#
.SYNOPSIS
    Search, filter and replace text in the clipboard or in files (grep/sed-like).

.DESCRIPTION
    clipGre.ps1 reads the clipboard (or the files given with -Path) and
      - filters it like grep: matching lines, highlighted matches, optional context, and/or
      - substitutes text like sed (literal text or .NET regex) and puts the result back
        into the clipboard (or into a file, or into the input files with -InPlace).
    Run "clipGre.ps1 -h" for an overview of all options.

.NOTES
    Must run on Windows PowerShell 5.1. Keep this file ASCII-only: PowerShell 5.1 reads
    script files without BOM in the ANSI code page, so non-ASCII literals would break.
#>
[CmdletBinding()]
param (
    # ---- Patterns (the first three may be given without option name) ----
    [Parameter(Position = 0)]
    [string[]]$Search = @(),

    [Parameter(Position = 1)]
    [string[]]$Replace = @(),

    [Parameter(Position = 2)]
    [Alias('flags')]
    [string]$RegexFlags = '',

    [string[]]$SearchFile = @(),
    [string[]]$ReplaceFile = @(),
    [string[]]$SearchFolder = @(),
    [string[]]$ReplaceFolder = @(),
    [string[]]$PairFile = @(),
    [switch]$PatternPerFile,

    # ---- Matching ----
    [Alias('r')]
    [switch]$Regex,
    [Alias('i')]
    [switch]$IgnoreCase,

    # ---- Operation mode (usually inferred, see Resolve-OperationMode) ----
    [switch]$Grep,
    [switch]$Substitute,
    [switch]$Delete,
    [Alias('reverse')]
    [switch]$Swap,

    # ---- Input files instead of the clipboard ----
    [Alias('files', 'inputPath')]
    [string[]]$Path = @(),
    [switch]$Recurse,
    [switch]$IncludeBinary,

    # ---- Grep output ----
    [int]$A = 0,
    [int]$B = 0,
    [int]$C = 0,
    [switch]$OnlyMatching,
    [string]$Separator = '',
    [switch]$CountOnly,
    [switch]$FilesWithMatches,
    [switch]$InvertMatch,

    # ---- Result output ----
    [string]$OutFile = '',
    [switch]$Save,
    [switch]$InPlace,

    # ---- Text analysis ----
    [switch]$Stats,
    [switch]$ExtendedStats,
    [switch]$CharMap,
    [ValidateSet('Count', 'Char')]
    [string]$SortBy = 'Count',
    [switch]$ShowWhitespace,
    [switch]$TextMetrics,
    [switch]$Benchmark,

    # ---- Flow control ----
    [Alias('ia')]
    [switch]$Interactive,
    [string]$Delay = '0',
    [switch]$DelayFirst,
    [Alias('pause')]
    [switch]$PauseAtEnd,
    [int]$Repeat = 1,
    [Alias('oo')]
    [switch]$Endless,

    [Alias('h')]
    [switch]$Help
)


#region Console helpers ---------------------------------------------------------------

$script:Esc = [char]27
$script:UseAnsi = $false   # set at program start, see Test-AnsiSupport

function Test-AnsiSupport {
    # Bold text needs ANSI escape sequences. The Windows 10+ console and Windows Terminal
    # understand them; other hosts fall back to plain console colors.
    try {
        if ($Host.UI.SupportsVirtualTerminal) { return $true }
    }
    catch { }
    return [bool]$env:WT_SESSION
}

function Write-Highlight([string]$Text) {
    # Prints a match: red and bold where possible, without line break.
    if ($Text.Length -eq 0) { return }
    if ($script:UseAnsi) {
        Write-Host "$($script:Esc)[1;31m$Text$($script:Esc)[0m" -NoNewline
    }
    else {
        Write-Host $Text -ForegroundColor Red -NoNewline
    }
}

function Write-Rule([string]$Title = '', [ConsoleColor]$Color = 'DarkGray') {
    # Horizontal separator line, optionally with a title: "-- Title -------".
    $width = 60
    if ($Title) {
        $line = "-- $Title "
        $line += '-' * [Math]::Max(3, $width - $line.Length)
    }
    else {
        $line = '-' * $width
    }
    Write-Host $line -ForegroundColor $Color
}

function Wait-ForKeyPress {
    Write-Host 'Press any key to continue...'
    try {
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    }
    catch {
        $null = Read-Host   # hosts without raw console access (e.g. PowerShell ISE)
    }
}

function Confirm-Continue([string]$Warning) {
    Write-Warning $Warning
    $null = Read-Host 'Press Enter to continue or Ctrl+C to abort'
}

function Write-ErrorMessage([string]$Message) {
    Write-Host "Error: $Message" -ForegroundColor Red
}

#endregion

#region Small converters --------------------------------------------------------------

function ConvertTo-DelaySeconds([string]$Value) {
    # Accepts "1.5" as well as "1,5" (decimal comma). Negative values are allowed.
    $normalized = $Value.Trim() -replace ',', '.'
    $seconds = 0.0
    $style = [Globalization.NumberStyles]::Float
    $culture = [Globalization.CultureInfo]::InvariantCulture
    if (-not [double]::TryParse($normalized, $style, $culture, [ref]$seconds)) {
        throw "Invalid delay '$Value'. Use a number of seconds, e.g. 2 or 0.5"
    }
    return $seconds
}

function Wait-Delay([double]$Seconds) {
    $milliseconds = [int][Math]::Round([Math]::Abs($Seconds) * 1000)
    if ($milliseconds -gt 0) { Start-Sleep -Milliseconds $milliseconds }
}

function ConvertFrom-EscapedText([string]$Text) {
    # Turns \t, \n, \r and \\ into the real characters. Needed wherever PowerShell does
    # not interpret escapes itself: single quotes, desktop shortcuts, "powershell -File".
    $evaluator = {
        param($match)
        switch -CaseSensitive ($match.Groups[1].Value) {
            'n' { "`n" }
            'r' { "`r" }
            't' { "`t" }
            default { '\' }
        }
    }
    return [regex]::Replace($Text, '\\([\\nrt])', $evaluator)
}

#endregion

#region File helpers ------------------------------------------------------------------

function Resolve-FullPath([string]$Path) {
    # .NET file APIs do not know the PowerShell location, so always hand them full paths.
    return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}

function Test-BinaryFile([string]$FilePath) {
    # Heuristic like GNU grep: a NUL byte within the first 64 KB marks a file as binary.
    # UTF-16 files (recognized by their BOM) contain NUL bytes but are text.
    $buffer = New-Object byte[] 65536
    $stream = [System.IO.File]::OpenRead($FilePath)
    try {
        $bytesRead = $stream.Read($buffer, 0, $buffer.Length)
    }
    finally {
        $stream.Dispose()
    }
    if ($bytesRead -ge 2) {
        $isUtf16LE = $buffer[0] -eq 0xFF -and $buffer[1] -eq 0xFE
        $isUtf16BE = $buffer[0] -eq 0xFE -and $buffer[1] -eq 0xFF
        if ($isUtf16LE -or $isUtf16BE) { return $false }
    }
    return [Array]::IndexOf($buffer, [byte]0, 0, $bytesRead) -ge 0
}

function Read-TextFile([string]$FilePath) {
    # Reads a text file and remembers its encoding, so -InPlace can write it back unchanged.
    # Files without BOM are read as UTF-8.
    $bytes = [System.IO.File]::ReadAllBytes($FilePath)
    $bomLength = 0
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $encoding = New-Object System.Text.UTF8Encoding($true)
        $bomLength = 3
    }
    elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        $encoding = New-Object System.Text.UnicodeEncoding($false, $true)
        $bomLength = 2
    }
    elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
        $encoding = New-Object System.Text.UnicodeEncoding($true, $true)
        $bomLength = 2
    }
    else {
        $encoding = New-Object System.Text.UTF8Encoding($false)
    }
    return [pscustomobject]@{
        Text     = $encoding.GetString($bytes, $bomLength, $bytes.Length - $bomLength)
        Encoding = $encoding
    }
}

function Get-OutputFilePath {
    # Builds "<dir>\<name>_[<suffix>_][<run>-]<timestamp><ext>". Directory and extension of
    # -OutFile are kept; without -OutFile the name is "Output_..." in the current directory.
    param(
        [string]$OutFile,
        [string]$Suffix = '',
        [int]$RunNumber = 0
    )
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    if ($RunNumber -gt 0) { $stamp = "$RunNumber-$stamp" }

    if ([string]::IsNullOrWhiteSpace($OutFile)) {
        $directory = (Get-Location).ProviderPath
        $baseName = 'Output'
        $extension = '.txt'
    }
    else {
        $fullPath = Resolve-FullPath $OutFile
        $directory = [System.IO.Path]::GetDirectoryName($fullPath)
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($fullPath)
        $extension = [System.IO.Path]::GetExtension($fullPath)
        if (-not $extension) { $extension = '.txt' }
    }
    if ($Suffix) { $baseName = "${baseName}_$Suffix" }
    return [System.IO.Path]::Combine($directory, "${baseName}_$stamp$extension")
}

function Save-TextToFile {
    param(
        [string]$Text,
        [string]$FilePath,
        [switch]$Quiet
    )
    [System.IO.File]::WriteAllText($FilePath, $Text, (New-Object System.Text.UTF8Encoding($true)))
    if (-not $Quiet) {
        Write-Host 'Results saved in file: ' -NoNewline
        Write-Host $FilePath -ForegroundColor Cyan
    }
}

function Get-InputFiles {
    # Expands the -Path entries (files, folders, wildcards) to a list of full file paths.
    param(
        [string[]]$Paths,
        [bool]$Recurse
    )
    foreach ($entry in $Paths) {
        if ([string]::IsNullOrWhiteSpace($entry)) { continue }
        if (Test-Path -LiteralPath $entry) {
            $items = @(Get-Item -LiteralPath $entry -Force)
        }
        else {
            $items = @(Get-Item -Path $entry -ErrorAction SilentlyContinue)   # wildcards, e.g. *.log
        }
        if ($items.Count -eq 0) {
            Write-Warning "Invalid path: $entry"
            continue
        }
        foreach ($item in $items) {
            if ($item.PSIsContainer) {
                Get-ChildItem -LiteralPath $item.FullName -File -Recurse:$Recurse -ErrorAction SilentlyContinue |
                    ForEach-Object { $_.FullName }
            }
            else {
                $item.FullName
            }
        }
    }
}

#endregion

#region Patterns ----------------------------------------------------------------------

function Get-RegexOptions {
    # Converts the flag string (e.g. "imx") into RegexOptions.
    param(
        [string]$Flags,
        [switch]$IgnoreCase
    )
    $flagNames = @{
        'i' = 'IgnoreCase'
        'm' = 'Multiline'
        's' = 'Singleline'
        'x' = 'IgnorePatternWhitespace'
        'n' = 'ExplicitCapture'
        'c' = 'Compiled'
        'u' = 'CultureInvariant'
        'j' = 'ECMAScript'
        'r' = 'RightToLeft'
        'b' = 'NonBacktracking'
    }
    $options = [System.Text.RegularExpressions.RegexOptions]::None
    if ($IgnoreCase) { $options = $options -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase }

    foreach ($flag in $Flags.ToCharArray()) {
        $name = $flagNames[[string]$flag]
        if (-not $name) {
            Write-Warning "Unknown regex flag '$flag' ignored."
            continue
        }
        if (-not [enum]::IsDefined([System.Text.RegularExpressions.RegexOptions], $name)) {
            throw "Regex flag '$flag' ($name) needs PowerShell 7 or newer; it is not available in PowerShell $($PSVersionTable.PSVersion)."
        }
        $options = $options -bor [System.Text.RegularExpressions.RegexOptions]$name
    }

    # .NET rejects these combinations only when the regex is built; fail early and clearly.
    $ecmaScriptCompatible = [int]([System.Text.RegularExpressions.RegexOptions]'IgnoreCase, Multiline, Compiled, ECMAScript')
    if (($options -band [System.Text.RegularExpressions.RegexOptions]::ECMAScript) -and ([int]$options -band (-bnot $ecmaScriptCompatible))) {
        throw "Regex flag 'j' (ECMAScript) can only be combined with 'i', 'm' and 'c'."
    }
    if ($Flags -match 'b' -and $Flags -match 'r') {
        throw "Regex flags 'b' (NonBacktracking) and 'r' (RightToLeft) cannot be combined."
    }
    return $options
}

function Get-TxtFilesInFolder([string]$Folder) {
    # Pattern folders: all *.txt files directly inside the folder, sorted by name.
    Get-ChildItem -LiteralPath $Folder -Filter *.txt -File | Sort-Object Name | ForEach-Object { $_.FullName }
}

function Resolve-PatternSourceFiles {
    # Pattern files first, then the *.txt files of the pattern folders.
    param(
        [string[]]$Files,
        [string[]]$Folders
    )
    foreach ($file in $Files) {
        if ([string]::IsNullOrWhiteSpace($file)) { continue }
        if (Test-Path -LiteralPath $file -PathType Leaf) { Resolve-FullPath $file }
        else { Write-Warning "Pattern file not found: $file" }
    }
    foreach ($folder in $Folders) {
        if ([string]::IsNullOrWhiteSpace($folder)) { continue }
        if (Test-Path -LiteralPath $folder -PathType Container) { Get-TxtFilesInFolder (Resolve-FullPath $folder) }
        else { Write-Warning "Pattern folder not found: $folder" }
    }
}

function Read-PatternFile {
    # Returns the patterns of a file: one per line, or the whole file as one pattern
    # (without its final line break) with -WholeFile.
    param(
        [string]$FilePath,
        [switch]$WholeFile
    )
    $text = (Read-TextFile $FilePath).Text
    if ($WholeFile) { return ($text -replace '\r?\n\z', '') }
    if ($text.Length -eq 0) { return }

    $lines = $text -split '\r?\n'
    if ($text.EndsWith("`n")) { $lines = $lines[0..($lines.Count - 2)] }   # final line break ends the last line
    $lines
}

function Get-PatternPairs {
    # Collects all search/replace pairs.
    # Search texts, search files and search folders form one list, replacement texts, files
    # and folders another; both are paired by position. A missing replacement means ''.
    # Pair files hold their own pairs (search line, replace line, ...) and are appended.
    param(
        [string[]]$SearchText,
        [string[]]$ReplaceText,
        [string[]]$SearchFile,
        [string[]]$ReplaceFile,
        [string[]]$SearchFolder,
        [string[]]$ReplaceFolder,
        [string[]]$PairFile,
        [switch]$PatternPerFile
    )
    $searchList = New-Object System.Collections.Generic.List[string]
    $replaceList = New-Object System.Collections.Generic.List[string]

    foreach ($text in $SearchText) { $searchList.Add($text) }
    foreach ($text in $ReplaceText) { $replaceList.Add($text) }
    foreach ($file in @(Resolve-PatternSourceFiles -Files $SearchFile -Folders $SearchFolder)) {
        foreach ($pattern in @(Read-PatternFile $file -WholeFile:$PatternPerFile)) { $searchList.Add($pattern) }
    }
    foreach ($file in @(Resolve-PatternSourceFiles -Files $ReplaceFile -Folders $ReplaceFolder)) {
        foreach ($pattern in @(Read-PatternFile $file -WholeFile:$PatternPerFile)) { $replaceList.Add($pattern) }
    }

    if ($replaceList.Count -gt $searchList.Count) {
        throw "There are more replacements ($($replaceList.Count)) than search patterns ($($searchList.Count)). Every replacement needs a search pattern - check your input."
    }

    $pairs = New-Object System.Collections.Generic.List[object]
    for ($index = 0; $index -lt $searchList.Count; $index++) {
        $replacement = ''
        if ($index -lt $replaceList.Count) { $replacement = $replaceList[$index] }
        $pairs.Add([pscustomobject]@{ Search = $searchList[$index]; Replace = $replacement })
    }

    foreach ($entry in $PairFile) {
        if ([string]::IsNullOrWhiteSpace($entry)) { continue }
        if (Test-Path -LiteralPath $entry -PathType Container) {
            $files = @(Get-TxtFilesInFolder (Resolve-FullPath $entry))
        }
        elseif (Test-Path -LiteralPath $entry -PathType Leaf) {
            $files = @(Resolve-FullPath $entry)
        }
        else {
            Write-Warning "Pair file not found: $entry"
            continue
        }
        foreach ($file in $files) {
            $lines = @(Read-PatternFile $file)
            if ($lines.Count % 2 -eq 1) {
                Write-Warning "Pair file '$file' has an odd number of lines: the last search pattern '$($lines[-1])' has no replacement, its matches will be deleted."
            }
            for ($index = 0; $index -lt $lines.Count; $index += 2) {
                $replacement = ''
                if ($index + 1 -lt $lines.Count) { $replacement = $lines[$index + 1] }
                $pairs.Add([pscustomobject]@{ Search = $lines[$index]; Replace = $replacement })
            }
        }
    }
    $pairs.ToArray()
}

function New-PatternRegex {
    # Builds the regex for a pattern; literal patterns are escaped. Invalid ones -> $null.
    param(
        [string]$Pattern,
        [bool]$IsRegex,
        [System.Text.RegularExpressions.RegexOptions]$Options
    )
    $expression = $Pattern
    if (-not $IsRegex) { $expression = [regex]::Escape($Pattern) }
    try {
        return New-Object System.Text.RegularExpressions.Regex($expression, $Options)
    }
    catch {
        $reason = $_.Exception.Message
        if ($_.Exception.InnerException) { $reason = $_.Exception.InnerException.Message }
        Write-Warning "Skipping invalid pattern '$Pattern': $reason"
        return $null
    }
}

function ConvertTo-CompiledPairs {
    # Adds the ready-to-use regex and replacement string to every pair.
    param(
        [object[]]$Pairs,
        [bool]$IsRegex,
        [System.Text.RegularExpressions.RegexOptions]$Options
    )
    foreach ($pair in $Pairs) {
        if ($pair.Search.Length -eq 0) {
            Write-Warning 'Empty search pattern: it matches at every position (between all characters).'
        }
        $regex = New-PatternRegex -Pattern $pair.Search -IsRegex $IsRegex -Options $Options
        if ($null -eq $regex) { continue }

        $replacement = [string]$pair.Replace
        if (-not $IsRegex) { $replacement = $replacement.Replace('$', '$$') }   # literal: no group references
        [pscustomobject]@{
            Search      = $pair.Search
            Replace     = [string]$pair.Replace
            Regex       = $regex
            Replacement = $replacement
        }
    }
}

#endregion

#region Grep --------------------------------------------------------------------------

function Get-LineStarts([string]$Text) {
    # Start index of every line; computed once per text so line lookups are cheap.
    $starts = New-Object System.Collections.Generic.List[int]
    $starts.Add(0)
    $index = $Text.IndexOf([char]10)
    while ($index -ge 0) {
        $starts.Add($index + 1)
        $index = $Text.IndexOf([char]10, $index + 1)
    }
    return , $starts.ToArray()
}

function Get-LineNumber([int[]]$LineStarts, [int]$Position) {
    # 1-based number of the line containing $Position (binary search).
    $index = [Array]::BinarySearch($LineStarts, $Position)
    if ($index -lt 0) { $index = (-bnot $index) - 1 }
    return $index + 1
}

function Get-StringLineInfo {
    # Position and line metadata for the text range [Position, Position + Length).
    param(
        [int[]]$LineStarts,
        [int]$Position,
        [int]$Length
    )
    $lastPosition = $Position
    if ($Length -gt 0) { $lastPosition = $Position + $Length - 1 }
    return [pscustomobject]@{
        StartPosition = $Position
        EndPosition   = $Position + $Length   # exclusive
        StartLine     = Get-LineNumber $LineStarts $Position
        EndLine       = Get-LineNumber $LineStarts $lastPosition
        TotalLines    = $LineStarts.Length
    }
}

function Find-AllMatches {
    # Matches of all patterns, ordered by position.
    param(
        [string]$Text,
        [object[]]$CompiledPairs
    )
    $allMatches = New-Object System.Collections.Generic.List[object]
    foreach ($pair in $CompiledPairs) {
        foreach ($match in $pair.Regex.Matches($Text)) { $allMatches.Add($match) }
    }
    $allMatches | Sort-Object Index, Length
}

function Write-GrepLine {
    # Prints "  12: text" (match line) or "  11- text" (context line) with highlighted matches.
    param(
        [int]$Number,
        [string]$Text,
        [bool]$IsMatch,
        [System.Collections.Generic.List[int[]]]$Ranges   # [start, end) of matches within the line
    )
    if ($IsMatch) {
        Write-Host ('{0,6}' -f $Number) -ForegroundColor Yellow -NoNewline
        Write-Host ': ' -ForegroundColor DarkGray -NoNewline
    }
    else {
        Write-Host ('{0,6}' -f $Number) -ForegroundColor DarkGray -NoNewline
        Write-Host '- ' -ForegroundColor DarkGray -NoNewline
    }

    # Merge overlapping ranges (several patterns may match the same text).
    $merged = New-Object System.Collections.Generic.List[int[]]
    if ($Ranges) {
        $Ranges.Sort([Comparison[int[]]] { param($x, $y) $x[0].CompareTo($y[0]) })
        foreach ($range in $Ranges) {
            $start = [Math]::Min($range[0], $Text.Length)
            $end = [Math]::Min($range[1], $Text.Length)
            if ($end -le $start) { continue }
            if ($merged.Count -gt 0 -and $start -le $merged[$merged.Count - 1][1]) {
                $last = $merged[$merged.Count - 1]
                $last[1] = [Math]::Max($last[1], $end)
            }
            else {
                $merged.Add([int[]]@($start, $end))
            }
        }
    }

    $position = 0
    foreach ($range in $merged) {
        if ($range[0] -gt $position) { Write-Host $Text.Substring($position, $range[0] - $position) -NoNewline }
        Write-Highlight $Text.Substring($range[0], $range[1] - $range[0])
        $position = $range[1]
    }
    Write-Host $Text.Substring($position)
}

function Invoke-Grep {
    # Searches $Text and prints the result (unless -Silent).
    # Returns MatchCount, LineCount (matching lines, or non-matching ones with -InvertMatch)
    # and Report (the printed output as plain text, for -Save/-OutFile).
    param(
        [string]$Text,
        [object[]]$CompiledPairs,
        [int]$Before = 0,
        [int]$After = 0,
        [switch]$OnlyMatching,
        [string]$Separator = "`n",
        [switch]$InvertMatch,
        [switch]$Silent
    )
    $report = New-Object System.Text.StringBuilder
    $matchList = @(Find-AllMatches -Text $Text -CompiledPairs $CompiledPairs)

    if ($OnlyMatching) {
        if (-not $Silent) {
            foreach ($match in $matchList) {
                Write-Highlight $match.Value
                Write-Host $Separator -NoNewline
                $null = $report.Append($match.Value).Append($Separator)
            }
            if ($matchList.Count -gt 0 -and -not $Separator.EndsWith("`n")) { Write-Host '' }
        }
        return [pscustomobject]@{ MatchCount = $matchList.Count; LineCount = 0; Report = $report.ToString() }
    }

    $lineStarts = Get-LineStarts $Text
    $lines = $Text -split "`n"
    $lastLine = $lineStarts.Length
    if ($lastLine -gt 1 -and $Text.EndsWith("`n")) { $lastLine-- }   # final line break opens no new line

    # Mark the lines touched by a match and remember which part of each line to highlight.
    $isMatchLine = New-Object bool[] ($lineStarts.Length + 2)
    $highlights = @{}
    foreach ($match in $matchList) {
        $info = Get-StringLineInfo -LineStarts $lineStarts -Position $match.Index -Length $match.Length
        Write-Verbose ("Match '{0}' at index {1}, length {2}, line {3}" -f $match.Value, $match.Index, $match.Length, $info.StartLine)
        $lastLine = [Math]::Max($lastLine, $info.EndLine)
        for ($line = $info.StartLine; $line -le $info.EndLine; $line++) {
            $isMatchLine[$line] = $true
            $lineStart = $lineStarts[$line - 1]
            $from = [Math]::Max($info.StartPosition, $lineStart) - $lineStart
            $to = [Math]::Min($info.EndPosition, $lineStart + $lines[$line - 1].Length) - $lineStart
            if ($to -le $from) { continue }
            if (-not $highlights.ContainsKey($line)) { $highlights[$line] = New-Object System.Collections.Generic.List[int[]] }
            $highlights[$line].Add([int[]]@($from, $to))
        }
    }

    # Decide which lines to print.
    $printLine = New-Object bool[] ($lastLine + 2)
    $lineCount = 0
    for ($line = 1; $line -le $lastLine; $line++) {
        if ($InvertMatch) {
            if (-not $isMatchLine[$line]) { $printLine[$line] = $true; $lineCount++ }
            continue
        }
        if (-not $isMatchLine[$line]) { continue }
        $lineCount++
        $first = [Math]::Max(1, $line - $Before)
        $last = [Math]::Min($lastLine, $line + $After)
        for ($contextLine = $first; $contextLine -le $last; $contextLine++) { $printLine[$contextLine] = $true }
    }

    if (-not $Silent) {
        $useGroupSeparator = ($Before -gt 0 -or $After -gt 0) -and -not $InvertMatch
        $previousLine = 0
        for ($line = 1; $line -le $lastLine; $line++) {
            if (-not $printLine[$line]) { continue }
            if ($useGroupSeparator -and $previousLine -gt 0 -and $line -gt $previousLine + 1) {
                Write-Host '    --' -ForegroundColor DarkGray
                $null = $report.AppendLine('--')
            }
            $lineText = $lines[$line - 1].TrimEnd([char]13)
            # With -InvertMatch every printed line is a result line (and has nothing to highlight).
            $isResultLine = $isMatchLine[$line] -or $InvertMatch
            Write-GrepLine -Number $line -Text $lineText -IsMatch $isResultLine -Ranges $highlights[$line]
            $marker = '-'
            if ($isResultLine) { $marker = ':' }
            $null = $report.AppendLine("$line$marker$lineText")
            $previousLine = $line
        }
    }
    return [pscustomobject]@{ MatchCount = $matchList.Count; LineCount = $lineCount; Report = $report.ToString() }
}

function Write-GrepSummary {
    param(
        [int]$MatchCount,
        [int]$LineCount,
        [switch]$InvertMatch
    )
    if ($InvertMatch) {
        Write-Host "$LineCount line(s) without matches" -ForegroundColor Green
    }
    elseif ($MatchCount -eq 0) {
        Write-Host 'No matches.' -ForegroundColor Yellow
    }
    else {
        Write-Host 'Matches: ' -NoNewline
        Write-Host " $MatchCount " -ForegroundColor Green -BackgroundColor DarkRed -NoNewline
        Write-Host " in $LineCount line(s)"
    }
    Write-Host ''
}

#endregion

#region Substitution ------------------------------------------------------------------

function Invoke-Substitution {
    # Applies all pairs one after another.
    param(
        [string]$Text,
        [object[]]$CompiledPairs
    )
    foreach ($pair in $CompiledPairs) {
        try {
            $Text = $pair.Regex.Replace($Text, $pair.Replacement)
        }
        catch {
            Write-Warning "Skipping substitution of '$($pair.Search)': $($_.Exception.Message)"
        }
    }
    return $Text
}

function Publish-Result {
    # Puts a substitution result into the clipboard or, with -Save/-OutFile, into a file.
    param(
        [string]$Result,
        [object]$Settings,
        [int]$RunNumber
    )
    if ($Settings.WriteToFile) {
        $filePath = Get-OutputFilePath -OutFile $Settings.OutFile -RunNumber $RunNumber
        Save-TextToFile -Text $Result -FilePath $filePath
        return
    }
    if ($Result.Length -eq 0) {
        $null | Set-Clipboard   # Set-Clipboard does not accept an empty string as -Value
        Write-Host 'Clipboard is empty now.' -ForegroundColor Blue
    }
    else {
        Set-Clipboard -Value $Result
    }
    Write-Host 'Clipboard successfully modified.' -ForegroundColor Green
}

#endregion

#region Text analysis (-Stats, -ExtendedStats, -CharMap, -TextMetrics) -------------------

function Get-CodePointList([string]$Text) {
    # Unicode code points; a surrogate pair is one code point, a lone surrogate counts as one, too.
    $codePoints = New-Object System.Collections.Generic.List[int]
    $index = 0
    while ($index -lt $Text.Length) {
        if ([char]::IsSurrogatePair($Text, $index)) {
            $codePoints.Add([char]::ConvertToUtf32($Text, $index))
            $index += 2
        }
        else {
            $codePoints.Add([int]$Text[$index])
            $index++
        }
    }
    return , $codePoints
}

function Format-TextElement {
    # Makes a character printable in a table: control characters as \n, \t, \x1B, ...
    # With -ShowWhitespace space, tab, CR and LF are shown as the Unicode symbols for them.
    param(
        [string]$Element,
        [switch]$ShowWhitespace
    )
    $builder = New-Object System.Text.StringBuilder
    foreach ($character in $Element.ToCharArray()) {
        $code = [int]$character
        if ($ShowWhitespace -and $code -eq 32) { $null = $builder.Append([char]0x2420) }
        elseif ($ShowWhitespace -and $code -eq 9) { $null = $builder.Append([char]0x2409) }
        elseif ($ShowWhitespace -and $code -eq 13) { $null = $builder.Append([char]0x240D) }
        elseif ($ShowWhitespace -and $code -eq 10) { $null = $builder.Append([char]0x240A) }
        elseif ($code -eq 9) { $null = $builder.Append('\t') }
        elseif ($code -eq 13) { $null = $builder.Append('\r') }
        elseif ($code -eq 10) { $null = $builder.Append('\n') }
        elseif ([char]::IsControl($character)) { $null = $builder.Append(('\x{0:X2}' -f $code)) }
        else { $null = $builder.Append($character) }
    }
    return $builder.ToString()
}

function Show-CharacterMap {
    # Frequency table of all user-perceived characters (grapheme clusters).
    param(
        [string]$Text,
        [ValidateSet('Count', 'Char')]
        [string]$SortBy = 'Count',
        [switch]$ShowWhitespace
    )
    $counts = @{}
    $enumerator = [System.Globalization.StringInfo]::GetTextElementEnumerator($Text)
    while ($enumerator.MoveNext()) {
        $element = [string]$enumerator.Current
        if ($counts.ContainsKey($element)) { $counts[$element]++ } else { $counts[$element] = 1 }
    }
    $total = 0
    foreach ($count in $counts.Values) { $total += $count }

    if ($SortBy -eq 'Char') {
        $sortedEntries = $counts.GetEnumerator() | Sort-Object { $_.Key }
    }
    else {
        $sortedEntries = $counts.GetEnumerator() | Sort-Object @{ Expression = { $_.Value }; Descending = $true }, @{ Expression = { $_.Key } }
    }

    Write-Host ('Character map (total: {0})' -f $total) -ForegroundColor Cyan
    $header = '{0,-12}  {1,7}  {2,8}  {3}' -f 'Char', 'Count', 'Percent', 'Code points'
    Write-Host $header
    Write-Host ('-' * $header.Length) -ForegroundColor DarkGray
    foreach ($entry in $sortedEntries) {
        $codePointNames = foreach ($codePoint in (Get-CodePointList $entry.Key)) { 'U+{0:X4}' -f $codePoint }
        $codePoints = @($codePointNames) -join ', '
        $percent = 100.0 * $entry.Value / $total
        Write-Host ('{0,-12}  {1,7}  {2,6:N2} %  {3}' -f (Format-TextElement $entry.Key -ShowWhitespace:$ShowWhitespace), $entry.Value, $percent, $codePoints)
    }
    Write-Host ''
}

function Get-TextMetrics([string]$Text) {
    # Encoding and Unicode structure metrics.
    $nonAsciiCount = [regex]::Matches($Text, '[^\x00-\x7F]').Count
    return [pscustomobject]@{
        Utf8Bytes       = [System.Text.Encoding]::UTF8.GetByteCount($Text)
        Utf16Bytes      = [System.Text.Encoding]::Unicode.GetByteCount($Text)
        Utf16CodeUnits  = $Text.Length
        CodePoints      = (Get-CodePointList $Text).Count
        Graphemes       = (New-Object System.Globalization.StringInfo($Text)).LengthInTextElements
        AsciiCharacters = $Text.Length - $nonAsciiCount
        ContainsNonAscii = $nonAsciiCount -gt 0
    }
}

function Show-TextMetrics([string]$Text) {
    $metrics = Get-TextMetrics $Text
    $rows = @(
        @('UTF-8 bytes', $metrics.Utf8Bytes, 'Yellow'),
        @('UTF-16 bytes', $metrics.Utf16Bytes, 'Cyan'),
        @('UTF-16 code units', $metrics.Utf16CodeUnits, 'Green'),
        @('Unicode code points', $metrics.CodePoints, 'Magenta'),
        @('Grapheme clusters', $metrics.Graphemes, 'Blue'),
        @('ASCII characters', $metrics.AsciiCharacters, 'DarkYellow')
    )
    Write-Host 'Text metrics' -ForegroundColor Cyan
    foreach ($row in $rows) {
        Write-Host ('{0,-20}: ' -f $row[0]) -NoNewline -ForegroundColor Gray
        Write-Host $row[1] -ForegroundColor $row[2]
    }
    Write-Host ('{0,-20}: ' -f 'Contains non-ASCII') -NoNewline -ForegroundColor Gray
    if ($metrics.ContainsNonAscii) { Write-Host 'True' -ForegroundColor Red } else { Write-Host 'False' -ForegroundColor Green }
    Write-Host ''
}

# Counted with regexes; shown with the regex, so it can be reused with this script.
$script:BasicStatistics = @(
    @{ Label = 'Characters (incl. line breaks)'; Pattern = '.'; Options = 'Singleline' },
    @{ Label = 'Digits'; Pattern = '\d'; Options = 'None' },
    @{ Label = 'URLs'; Pattern = '\bhttps?://[^\s)"]+'; Options = 'None' },
    @{ Label = 'E-mail addresses'; Pattern = '\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b'; Options = 'None' },
    @{ Label = 'Sentences'; Pattern = '[^.!?\s][^.!?]*(?:[.!?]+|$)'; Options = 'None' },
    @{ Label = 'Lines'; Pattern = '^'; Options = 'Multiline' },
    @{ Label = 'Non-empty lines'; Pattern = '^(?=.*\S).+$'; Options = 'Multiline' },
    @{ Label = 'Words'; Pattern = '\b\w+\b'; Options = 'None' },
    @{ Label = 'Fields, whitespace separated'; Pattern = '\S+'; Options = 'None' },
    @{ Label = 'Fields, comma separated'; Pattern = ','; Options = 'None'; Offset = 1 }
)
$script:ExtendedStatistics = @(
    @{ Label = 'Integer numbers'; Pattern = '(?<![\p{L}\p{M}])[-+]?\d+(?![\p{L}\p{M}])'; Options = 'None' },
    @{ Label = 'Decimal numbers (. or ,)'; Pattern = '(?<![\p{L}\p{M}])[-+]?\d+([.,]\d+)?(?![\p{L}\p{M}])'; Options = 'None' },
    @{ Label = 'Words (Unicode letters)'; Pattern = '\b[\p{L}\p{M}\p{N}]+\b'; Options = 'None' },
    @{ Label = 'Currency symbols'; Pattern = '\p{Sc}'; Options = 'None' },
    @{ Label = 'Math symbols'; Pattern = '\p{Sm}'; Options = 'None' },
    @{ Label = 'Multiple spaces'; Pattern = ' {2,}'; Options = 'None' },
    @{ Label = 'Line breaks'; Pattern = '\r?\n'; Options = 'None' }
)

function Show-TextStatistics {
    param(
        [string]$Text,
        [object[]]$CompiledPairs,
        [bool]$IsRegex,
        [switch]$Extended
    )
    $definitions = $script:BasicStatistics
    if ($Extended) { $definitions = $definitions + $script:ExtendedStatistics }

    Write-Host 'Statistics' -ForegroundColor Cyan
    foreach ($definition in $definitions) {
        $options = [System.Text.RegularExpressions.RegexOptions]$definition.Options
        $count = [regex]::Matches($Text, $definition.Pattern, $options).Count
        if ($definition.Offset) { $count += $definition.Offset }
        Write-Host ('{0,-32}' -f $definition.Label) -NoNewline
        Write-Host ('{0,8}' -f $count) -ForegroundColor Magenta -NoNewline
        $optionText = ''
        if ($definition.Options -ne 'None') { $optionText = " ($($definition.Options))" }
        Write-Host "   $($definition.Pattern)$optionText" -ForegroundColor DarkGray
    }

    $patternMatches = 0
    foreach ($pair in $CompiledPairs) { $patternMatches += $pair.Regex.Matches($Text).Count }
    $patternKind = 'literal text'
    if ($IsRegex) { $patternKind = 'regex' }
    Write-Host ''
    Write-Host 'Your ' -NoNewline
    Write-Host @($CompiledPairs).Count -ForegroundColor Yellow -NoNewline
    Write-Host " search pattern(s) ($patternKind) matched " -NoNewline
    Write-Host $patternMatches -ForegroundColor Red -NoNewline
    Write-Host ' time(s).'
    Write-Host ''
}

function Show-TextAnalysis {
    # -Stats/-ExtendedStats show everything; -CharMap/-TextMetrics only their part.
    param(
        [string]$Text,
        [object]$Settings,
        [object[]]$CompiledPairs,
        [bool]$IsRegex
    )
    $showAll = $Settings.Stats -or $Settings.ExtendedStats
    if (-not ($showAll -or $Settings.CharMap -or $Settings.TextMetrics)) { return }

    Write-Host ''
    Write-Rule 'Text analysis' Cyan
    if ($showAll -or $Settings.CharMap) {
        Show-CharacterMap -Text $Text -SortBy $Settings.SortBy -ShowWhitespace:$Settings.ShowWhitespace
    }
    if ($showAll -or $Settings.TextMetrics) { Show-TextMetrics $Text }
    if ($showAll) {
        Show-TextStatistics -Text $Text -CompiledPairs $CompiledPairs -IsRegex $IsRegex -Extended:$Settings.ExtendedStats
    }
}

#endregion

#region Interactive input -------------------------------------------------------------

function Read-InteractiveInput {
    # Asks for everything the command line did not specify. $State (Grep, Substitute,
    # Delete, Regex, RegexFlags) is updated in place, so later runs do not ask again.
    # Returns the entered search and replacement text.
    param([hashtable]$State)

    if (-not $State.Grep -and -not $State.Substitute) {
        $choices = [System.Management.Automation.Host.ChoiceDescription[]]@(
            (New-Object System.Management.Automation.Host.ChoiceDescription '&Substitution', 'Replace matches with a replacement text'),
            (New-Object System.Management.Automation.Host.ChoiceDescription '&Grep (text filter)', 'Show the lines containing matches'),
            (New-Object System.Management.Automation.Host.ChoiceDescription '&Deletion', 'Delete matches (no replacement)')
        )
        switch ($Host.UI.PromptForChoice('Missing CLI options, please specify your intention', 'Choose what you want to do:', $choices, 0)) {
            0 { $State.Substitute = $true }
            1 { $State.Grep = $true }
            2 { $State.Substitute = $true; $State.Delete = $true }
        }
    }

    $flagPrompt = "Enter regex flags (i ignore case, m multiline, s dot matches newline, x ignore pattern whitespace; also n c u j r b; empty for none)"
    if (-not $State.Regex) {
        $choices = [System.Management.Automation.Host.ChoiceDescription[]]@(
            (New-Object System.Management.Automation.Host.ChoiceDescription '&Literal text', 'Search for the text exactly as entered'),
            (New-Object System.Management.Automation.Host.ChoiceDescription '&Regex without flags', 'Use a .NET regular expression'),
            (New-Object System.Management.Automation.Host.ChoiceDescription 'Regex &with flags', 'Use a .NET regular expression and enter flags')
        )
        switch ($Host.UI.PromptForChoice('Regular expression', 'Enable regex for the input?', $choices, 0)) {
            1 { $State.Regex = $true }
            2 { $State.Regex = $true; $State.RegexFlags = Read-Host $flagPrompt }
        }
    }
    elseif ($State.RegexFlags -eq '') {
        $State.RegexFlags = Read-Host $flagPrompt
    }

    if ($State.Regex) { $searchInput = Read-Host 'Please enter search text (.NET regex syntax allowed)' }
    else { $searchInput = Read-Host 'Please enter search text' }

    $replaceInput = ''
    if ($State.Substitute -and -not $State.Delete) {
        if ($State.Regex) { Write-Host 'You can reference capture groups via $1, $2, etc.' }
        $replaceInput = Read-Host 'Please enter replacement text'
    }
    return [pscustomobject]@{ Search = $searchInput; Replace = $replaceInput }
}

#endregion

#region Help --------------------------------------------------------------------------

function Show-HelpText {
    $helpText = @'

clipGre.ps1 - search, filter and replace text in the clipboard or in files

USAGE
  clipGre.ps1 [-Search] <pattern(s)> [[-Replace] <replacement(s)>] [[-RegexFlags] <flags>] [options]

  clipGre.ps1 'foo'               show lines of the clipboard containing 'foo'
  clipGre.ps1 'foo' 'bar'         replace 'foo' by 'bar' in the clipboard
  clipGre.ps1 '(\d+)' '[$1]' 'm'  regex substitution with flags (third value implies -Regex)

PATTERNS
  -Search <str[]>            Search pattern(s)                                  (position 1)
  -Replace <str[]>           Replacement(s), paired with -Search by position    (position 2)
  -RegexFlags, -flags <str>  .NET regex flags, implies -Regex                   (position 3)
  -SearchFile <path[]>       File(s) with search patterns, one per line
  -ReplaceFile <path[]>      File(s) with replacements, one per line
  -SearchFolder <path[]>     Folder(s): all *.txt files are search pattern files (sorted by name)
  -ReplaceFolder <path[]>    Folder(s): all *.txt files are replacement files (sorted by name)
  -PairFile <path[]>         File(s)/folder(s) with alternating lines: search, replace, search, ...
  -PatternPerFile            Each pattern file is ONE pattern (multi-line patterns)

MATCHING
  -Regex, -r                 Patterns are .NET regular expressions (default: literal text)
  -IgnoreCase, -i            Ignore case

MODE (usually inferred: search only = grep, search + replacement = substitution)
  -Grep                      Show matching lines
  -Substitute                Replace matches
  -Delete                    Delete matches
  -Swap, -reverse            Swap search and replacement (undo a literal substitution)

INPUT (default: clipboard)
  -Path, -files <path[]>     File(s), folder(s) or wildcards to process instead of the clipboard
  -Recurse                   Include subfolders
  -IncludeBinary             Also process files that look binary

GREP OUTPUT
  -A <n> / -B <n> / -C <n>   Show n lines after / before / around each matching line
  -OnlyMatching              Show only the matches, as a list
  -Separator <str>           Separator for -OnlyMatching (default: line break; implies it);
                             also joins file results of a substitution. \t \n \r \\ allowed
  -CountOnly                 Show only the number of matches (per file)
  -FilesWithMatches          Show only the names of files containing matches
  -InvertMatch               Show the lines WITHOUT matches

RESULT OUTPUT (default: substitution result goes to the clipboard)
  -Save                      Write result to a file "Output_<timestamp>.txt"
  -OutFile <path>            Write result to <path>, a timestamp is added to the name
  -InPlace                   Write substitutions back into the input files (backup: *.bak)

TEXT ANALYSIS
  -Stats                     Character map, text metrics and statistics of the input text
  -ExtendedStats             Like -Stats with additional statistics
  -CharMap                   Character map only; -SortBy Count|Char, -ShowWhitespace
  -TextMetrics               Byte sizes, code points, graphemes, ASCII check only
  -Benchmark                 Show execution times

FLOW CONTROL
  -Interactive, -ia          Ask for search/replacement text (automatic if no pattern given)
  -Delay <seconds>           Wait after each run (negative value: wait before each run)
  -DelayFirst                Wait before each run instead of after it
  -PauseAtEnd, -pause        Wait for a key press after each run
  -Repeat <n>                Run n times (patterns and files are re-read each run)
  -Endless, -oo              Run endlessly (stop with Ctrl+C)
  -Verbose                   Show index and length of every match
  -Help, -h                  Show this help

'@
    Write-Host $helpText
}

#endregion

#region Program flow ------------------------------------------------------------------

function Resolve-OperationMode {
    # Infers what to do from the given options:
    #  - no search pattern and no text analysis requested -> interactive input
    #  - substitution: requested (-Substitute, -Delete, -Swap) or any replacement given
    #  - grep: requested, implied by a grep output option, or search patterns without replacement
    # Grep and substitution may both be active: grep reports on the original text first.
    param(
        [bool]$HasSearch,
        [bool]$HasReplace,
        [bool]$AnalysisRequested,
        [bool]$InteractiveRequested,
        [bool]$GrepRequested,
        [bool]$SubstituteRequested
    )
    $substituteMode = $SubstituteRequested -or $HasReplace
    return [pscustomobject]@{
        Interactive = $InteractiveRequested -or (-not $HasSearch -and -not $AnalysisRequested)
        Substitute  = $substituteMode
        Grep        = $GrepRequested -or ($HasSearch -and -not $substituteMode)
    }
}

function Invoke-GrepForSource {
    # Greps one text (clipboard or file), prints the result and appends it to $Report.
    param(
        [object]$Settings,
        [object[]]$CompiledPairs,
        [string]$Text,
        [string]$SourceName,
        [System.Text.StringBuilder]$Report
    )
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    $result = Invoke-Grep -Text $Text -CompiledPairs $CompiledPairs `
        -Before $Settings.ContextBefore -After $Settings.ContextAfter `
        -OnlyMatching:$Settings.OnlyMatching -Separator $Settings.ListSeparator `
        -InvertMatch:$Settings.InvertMatch -Silent:($Settings.CountOnly -or $Settings.FilesWithMatches)
    $timer.Stop()

    $count = $result.MatchCount
    if ($Settings.InvertMatch) { $count = $result.LineCount }

    if ($Settings.FilesWithMatches) {
        if ($count -gt 0) {
            Write-Host $SourceName -ForegroundColor Cyan
            $null = $Report.AppendLine($SourceName)
        }
    }
    elseif ($Settings.CountOnly) {
        $line = "$count"
        if ($Settings.ReadFromFiles) { $line = "$SourceName`: $count" }
        Write-Host $line
        $null = $Report.AppendLine($line)
    }
    else {
        if ($Settings.ReadFromFiles -and -not $Settings.OnlyMatching -and $result.Report.Length -gt 0) {
            $null = $Report.AppendLine("=== FILE: $SourceName ===")
        }
        $null = $Report.Append($result.Report)
        if (-not $Settings.OnlyMatching) {
            Write-GrepSummary -MatchCount $result.MatchCount -LineCount $result.LineCount -InvertMatch:$Settings.InvertMatch
        }
    }
    if ($Settings.Benchmark) { Write-Host ('Grep took {0:F3} ms' -f $timer.Elapsed.TotalMilliseconds) }
    return $count
}

function Invoke-SingleRun {
    # One complete run: read patterns and input, grep and/or substitute, write results.
    param(
        [object]$Settings,
        [hashtable]$State,
        [int]$RunNumber
    )
    $patternPairs = New-Object System.Collections.Generic.List[object]
    if ($State.Interactive) {
        $patternPairs.Add((Read-InteractiveInput -State $State))
        Write-Rule
    }
    if ($Settings.DelayBeforeRun) { Wait-Delay $Settings.DelaySeconds }

    # ---- Patterns (re-read in every run) ----
    try {
        $pairs = @(Get-PatternPairs -SearchText $Settings.SearchText -ReplaceText $Settings.ReplaceText `
                -SearchFile $Settings.SearchFile -ReplaceFile $Settings.ReplaceFile `
                -SearchFolder $Settings.SearchFolder -ReplaceFolder $Settings.ReplaceFolder `
                -PairFile $Settings.PairFile -PatternPerFile:$Settings.PatternPerFile)
        foreach ($pair in $pairs) { $patternPairs.Add($pair) }
        $regexOptions = Get-RegexOptions -Flags $State.RegexFlags -IgnoreCase:$Settings.IgnoreCase
    }
    catch {
        Write-ErrorMessage $_.Exception.Message
        return
    }
    $isRegex = $State.Regex -or $State.RegexFlags.Length -gt 0
    foreach ($pair in $patternPairs) {
        if ($State.Delete) { $pair.Replace = '' }
        if ($Settings.Swap) { $pair.Search, $pair.Replace = $pair.Replace, $pair.Search }
    }
    $compiledPairs = @(ConvertTo-CompiledPairs -Pairs $patternPairs.ToArray() -IsRegex $isRegex -Options $regexOptions)

    $doGrep = $State.Grep
    $doSubstitute = $State.Substitute
    if (($doGrep -or $doSubstitute) -and $compiledPairs.Count -eq 0) {
        Write-Host 'No usable search pattern - nothing to search for.' -ForegroundColor Yellow
        $doGrep = $false
        $doSubstitute = $false
    }

    $outputRunNumber = 0
    if ($Settings.NumberOutputFiles) { $outputRunNumber = $RunNumber }
    $grepReport = New-Object System.Text.StringBuilder
    $substitutionTimer = New-Object System.Diagnostics.Stopwatch

    if (-not $Settings.ReadFromFiles) {
        # ---- Clipboard ----
        $clipboardText = Get-Clipboard -Raw
        if ([string]::IsNullOrEmpty($clipboardText)) {
            Write-Host 'Clipboard is empty. Nothing to do!' -ForegroundColor Magenta
            return
        }
        if ($doGrep) {
            $null = Invoke-GrepForSource -Settings $Settings -CompiledPairs $compiledPairs -Text $clipboardText -SourceName '(clipboard)' -Report $grepReport
        }
        if ($doSubstitute) {
            $substitutionTimer.Start()
            $newText = Invoke-Substitution -Text $clipboardText -CompiledPairs $compiledPairs
            $substitutionTimer.Stop()
            if ([string]::CompareOrdinal($clipboardText, $newText) -eq 0) {
                Write-Host 'Clipboard text has not changed.' -ForegroundColor Yellow
            }
            else {
                Publish-Result -Result $newText -Settings $Settings -RunNumber $outputRunNumber
            }
        }
        Show-TextAnalysis -Text $clipboardText -Settings $Settings -CompiledPairs $compiledPairs -IsRegex $isRegex
    }
    else {
        # ---- Files ----
        $files = @(Get-InputFiles -Paths $Settings.InputPaths -Recurse $Settings.Recurse)
        if ($files.Count -eq 0) { Write-Host 'No input files found.' -ForegroundColor Yellow }
        $showHeaders = -not ($Settings.CountOnly -or $Settings.FilesWithMatches)
        $substitutedTexts = New-Object System.Collections.Generic.List[string]
        $changedFiles = 0

        foreach ($filePath in $files) {
            try {
                if (-not $Settings.IncludeBinary -and (Test-BinaryFile $filePath)) {
                    if ($showHeaders) { Write-Host "`n=== BINARY FILE (skipped): $filePath ===" -ForegroundColor Yellow }
                    continue
                }
                $file = Read-TextFile $filePath
            }
            catch {
                Write-Warning "Skipping (not readable): $filePath - $($_.Exception.Message)"
                continue
            }
            if ($showHeaders) { Write-Host "`n=== FILE: $filePath ===" -ForegroundColor Cyan }
            if ($file.Text.Length -eq 0) {
                if ($showHeaders) { Write-Host 'Empty file.' -ForegroundColor Yellow }
                continue
            }

            if ($doGrep) {
                $null = Invoke-GrepForSource -Settings $Settings -CompiledPairs $compiledPairs -Text $file.Text -SourceName $filePath -Report $grepReport
            }
            if ($doSubstitute) {
                $substitutionTimer.Start()
                $newText = Invoke-Substitution -Text $file.Text -CompiledPairs $compiledPairs
                $substitutionTimer.Stop()
                $changed = [string]::CompareOrdinal($file.Text, $newText) -ne 0
                if ($changed) { $changedFiles++ }
                if ($Settings.InPlace) {
                    if ($changed) {
                        Copy-Item -LiteralPath $filePath -Destination "$filePath.bak" -Force
                        [System.IO.File]::WriteAllText($filePath, $newText, $file.Encoding)
                        Write-Host "Modified (backup: $filePath.bak)" -ForegroundColor Green
                    }
                    else {
                        Write-Host 'Unchanged.' -ForegroundColor DarkGray
                    }
                }
                else {
                    $substitutedTexts.Add($newText)
                }
            }
            Show-TextAnalysis -Text $file.Text -Settings $Settings -CompiledPairs $compiledPairs -IsRegex $isRegex
        }

        if ($doSubstitute -and -not $Settings.InPlace) {
            if ($changedFiles -eq 0) {
                Write-Host 'No file content has changed.' -ForegroundColor Yellow
            }
            else {
                Write-Host "Substituted content of $($substitutedTexts.Count) file(s), $changedFiles changed:"
                Publish-Result -Result ($substitutedTexts -join $Settings.JoinSeparator) -Settings $Settings -RunNumber $outputRunNumber
            }
        }
    }

    # ---- Grep result to file ----
    if ($doGrep -and $Settings.WriteToFile -and $grepReport.Length -gt 0) {
        $suffix = ''
        if ($doSubstitute -and -not $Settings.InPlace) { $suffix = 'grep' }   # keep it apart from the substitution result
        $filePath = Get-OutputFilePath -OutFile $Settings.OutFile -Suffix $suffix -RunNumber $outputRunNumber
        Save-TextToFile -Text $grepReport.ToString() -FilePath $filePath -Quiet:$Settings.OnlyMatching
    }
    if ($Settings.Benchmark -and $doSubstitute) {
        Write-Host ('Substitution took {0:F3} ms' -f $substitutionTimer.Elapsed.TotalMilliseconds)
    }
}

#endregion

#region Main --------------------------------------------------------------------------

$scriptTimer = [System.Diagnostics.Stopwatch]::StartNew()

if ($Help) {
    Show-HelpText
    if ($PauseAtEnd) { Wait-ForKeyPress }
    return
}

$script:UseAnsi = Test-AnsiSupport

try {
    $delaySeconds = ConvertTo-DelaySeconds $Delay
}
catch {
    Write-ErrorMessage $_.Exception.Message
    return
}

$readFromFiles = $Path.Count -gt 0
$writeToFile = $Save -or -not [string]::IsNullOrWhiteSpace($OutFile)
$separatorGiven = $PSBoundParameters.ContainsKey('Separator')
$separatorText = ConvertFrom-EscapedText $Separator
$useRegex = $Regex -or $RegexFlags.Length -gt 0
if ($Repeat -lt 1) { $Repeat = 1 }

$hasSearch = $Search.Count -gt 0 -or $SearchFile.Count -gt 0 -or $SearchFolder.Count -gt 0 -or $PairFile.Count -gt 0
$hasReplace = $Replace.Count -gt 0 -or $ReplaceFile.Count -gt 0 -or $ReplaceFolder.Count -gt 0 -or $PairFile.Count -gt 0
$mode = Resolve-OperationMode -HasSearch $hasSearch -HasReplace $hasReplace `
    -AnalysisRequested ($Stats -or $ExtendedStats -or $CharMap -or $TextMetrics) `
    -InteractiveRequested $Interactive `
    -GrepRequested ($Grep -or $A -gt 0 -or $B -gt 0 -or $C -gt 0 -or $OnlyMatching -or $CountOnly -or $FilesWithMatches -or $InvertMatch) `
    -SubstituteRequested ($Substitute -or $Delete -or $Swap)

if ($InPlace -and -not $readFromFiles) {
    Write-ErrorMessage '-InPlace needs input files (-Path).'
    return
}
if ($InPlace -and $writeToFile) {
    Write-Warning '-InPlace writes into the input files; -Save/-OutFile only apply to grep results.'
}
if ($Endless -and $writeToFile) {
    Confirm-Continue 'Endless looping with file output creates a new file in every run.'
}
if ($Swap -and ($useRegex -or $Delete)) {
    Confirm-Continue 'Only literal substitutions (no regex, no -Delete) can be swapped meaningfully.'
}

$settings = [pscustomobject]@{
    SearchText        = $Search
    ReplaceText       = $Replace
    SearchFile        = $SearchFile
    ReplaceFile       = $ReplaceFile
    SearchFolder      = $SearchFolder
    ReplaceFolder     = $ReplaceFolder
    PairFile          = $PairFile
    PatternPerFile    = [bool]$PatternPerFile
    IgnoreCase        = [bool]$IgnoreCase
    Swap              = [bool]$Swap
    ReadFromFiles     = $readFromFiles
    InputPaths        = $Path
    Recurse           = [bool]$Recurse
    IncludeBinary     = [bool]$IncludeBinary
    ContextBefore     = [Math]::Max(0, $B + $C)
    ContextAfter      = [Math]::Max(0, $A + $C)
    OnlyMatching      = $OnlyMatching -or $separatorGiven
    ListSeparator     = $(if ($separatorGiven) { $separatorText } else { "`n" })
    JoinSeparator     = $separatorText
    CountOnly         = [bool]$CountOnly
    FilesWithMatches  = [bool]$FilesWithMatches
    InvertMatch       = [bool]$InvertMatch
    WriteToFile       = $writeToFile
    OutFile           = $OutFile
    InPlace           = [bool]$InPlace
    NumberOutputFiles = $Repeat -gt 1 -or $Endless
    Stats             = [bool]$Stats
    ExtendedStats     = [bool]$ExtendedStats
    CharMap           = [bool]$CharMap
    SortBy            = $SortBy
    ShowWhitespace    = [bool]$ShowWhitespace
    TextMetrics       = [bool]$TextMetrics
    Benchmark         = [bool]$Benchmark
    DelaySeconds      = $delaySeconds
    DelayBeforeRun    = $DelayFirst -or $delaySeconds -lt 0
}

# Mutable state: interactive input may change it, later runs keep the choices.
$state = @{
    Interactive = $mode.Interactive
    Grep        = $mode.Grep
    Substitute  = $mode.Substitute
    Delete      = [bool]$Delete
    Regex       = $useRegex
    RegexFlags  = $RegexFlags
}

$runNumber = 0
do {
    for ($iteration = 1; $iteration -le $Repeat; $iteration++) {
        $runNumber++
        if ($Repeat -gt 1) {
            Write-Host ''
            Write-Host " Begin run $runNumber " -BackgroundColor DarkGray -ForegroundColor White
        }

        Invoke-SingleRun -Settings $settings -State $state -RunNumber $runNumber

        if ($Benchmark) { Write-Host ('Whole script took {0:F5} s' -f $scriptTimer.Elapsed.TotalSeconds) }
        if ($Repeat -gt 1) { Write-Host " End run $runNumber " -BackgroundColor DarkGray -ForegroundColor White }
        if ($PauseAtEnd) { Wait-ForKeyPress }
        if (-not $settings.DelayBeforeRun) { Wait-Delay $settings.DelaySeconds }
    }
} until (-not $endless)
