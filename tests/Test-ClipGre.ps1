<#
.SYNOPSIS
    Self-contained tests for clipGre.ps1 (no Pester needed).

.DESCRIPTION
    Runs clipGre.ps1 with many option combinations and checks console output, clipboard
    and written files. The clipboard is simulated, your real clipboard is not touched.
    Works with Windows PowerShell 5.1 and PowerShell 7.

        powershell -ExecutionPolicy Bypass -File tests\Test-ClipGre.ps1

    Exit code = number of failed checks. Interactive prompts are not covered.
#>
param(
    [string]$ScriptPath = (Join-Path (Join-Path $PSScriptRoot '..') 'clipGre.ps1')
)

$ScriptPath = (Resolve-Path -LiteralPath $ScriptPath).ProviderPath
$script:Failed = 0
$script:Passed = 0

# ---- Simulated clipboard: functions take precedence over the cmdlets ----
function global:Get-Clipboard { param([switch]$Raw) $global:TestClipboard }
function global:Set-Clipboard { param([Parameter(ValueFromPipeline = $true)]$Value) process { $global:TestClipboard = $Value } }

function Invoke-ClipGre {
    # Runs the script and returns its console output (without color codes) and the clipboard.
    param(
        [string]$Clipboard = '',
        [object[]]$Arguments = @(),
        [hashtable]$Options = @{}
    )
    $global:TestClipboard = $Clipboard
    # Rebuild the console text: Write-Host -NoNewline must not start a new line.
    $builder = New-Object System.Text.StringBuilder
    foreach ($record in (& $ScriptPath @Arguments @Options 6>&1 4>&1 3>&1 2>&1)) {
        $hostMessage = $null
        if ($record -is [System.Management.Automation.InformationRecord]) { $hostMessage = $record.MessageData }
        if ($hostMessage -is [System.Management.Automation.HostInformationMessage]) {
            $null = $builder.Append($hostMessage.Message)
            if (-not $hostMessage.NoNewLine) { $null = $builder.Append("`n") }
        }
        elseif ($record -is [System.Management.Automation.VerboseRecord] -or $record -is [System.Management.Automation.WarningRecord]) {
            $null = $builder.Append($record.Message).Append("`n")
        }
        else {
            $null = $builder.Append([string]$record).Append("`n")
        }
    }
    $output = $builder.ToString() -replace "$([char]27)\[[0-9;]*m", ''
    return [pscustomobject]@{ Output = $output; Clipboard = $global:TestClipboard }
}

function Assert-That {
    param([bool]$Condition, [string]$Name, [string]$Details = '')
    if ($Condition) {
        $script:Passed++
        Write-Host "  [ok]   $Name" -ForegroundColor Green
    }
    else {
        $script:Failed++
        Write-Host "  [FAIL] $Name" -ForegroundColor Red
        if ($Details) { Write-Host ($Details -replace '(?m)^', '         | ') -ForegroundColor DarkGray }
    }
}

function Assert-Contains([string]$Text, [string]$Expected, [string]$Name) {
    Assert-That ($Text.Contains($Expected)) $Name $Text
}

function Assert-Equal($Actual, $Expected, [string]$Name) {
    Assert-That ([string]::CompareOrdinal([string]$Actual, [string]$Expected) -eq 0) $Name "expected: [$Expected]`nactual:   [$Actual]"
}

# ---- Test data in a temporary folder ----
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('clipGreTests_' + [guid]::NewGuid().ToString('N'))
$dataDir = Join-Path $testRoot 'data'
$null = New-Item -ItemType Directory -Path (Join-Path $dataDir 'sub') -Force
$utf8 = New-Object System.Text.UTF8Encoding($false)
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText((Join-Path $dataDir 'a.txt'), "alpha foo`nbeta`n", $utf8)
[System.IO.File]::WriteAllText((Join-Path (Join-Path $dataDir 'sub') 'b.txt'), "foo in sub`n", $utf8)
[System.IO.File]::WriteAllText((Join-Path $dataDir 'bom.txt'), "BOM foo $([char]0xE4)`r`n", $utf8Bom)
[System.IO.File]::WriteAllBytes((Join-Path $dataDir 'bin.dat'), [byte[]](98, 105, 110, 0, 102, 111, 111))
[System.IO.File]::WriteAllText((Join-Path $testRoot 'pairs.txt'), "foo`nFOO`nbar`n", $utf8)
[System.IO.File]::WriteAllText((Join-Path $testRoot 'search.txt'), "line1`nline2`n", $utf8)
[System.IO.File]::WriteAllText((Join-Path $testRoot 'replace.txt'), "ONE`n", $utf8)

$sampleText = "Hallo Welt.`r`nfoo bar foo`r`nzeile drei`r`nnoch eine foo-zeile`r`nende`r`n"
$previousLocation = Get-Location
Set-Location -LiteralPath $testRoot

try {
    Write-Host "`nGrep" -ForegroundColor Cyan
    $r = Invoke-ClipGre -Clipboard $sampleText -Arguments @('foo') -Options @{ B = 1 }
    Assert-Contains $r.Output '     2: foo bar foo' 'line with two matches is printed once'
    Assert-Contains $r.Output '     1- Hallo Welt.' 'context line before match (-B)'
    Assert-Contains $r.Output 'Matches:  3  in 2 line(s)' 'match and line count'
    Assert-Equal $r.Clipboard $sampleText 'grep leaves the clipboard unchanged'

    $r = Invoke-ClipGre -Clipboard "a`nb`nc`nd`ne`nfoo`n" -Options @{ Search = @('a', 'foo'); A = 1 }
    Assert-Contains $r.Output '    --' 'group separator between distant context blocks'

    $r = Invoke-ClipGre -Clipboard $sampleText -Arguments @('foo') -Options @{ CountOnly = $true }
    Assert-Equal $r.Output.Trim() '3' '-CountOnly prints only the count'

    $r = Invoke-ClipGre -Clipboard $sampleText -Arguments @('foo') -Options @{ InvertMatch = $true }
    Assert-Contains $r.Output '3 line(s) without matches' '-InvertMatch counts lines without match'
    Assert-Contains $r.Output '     5: ende' '-InvertMatch prints non-matching line'

    $r = Invoke-ClipGre -Clipboard $sampleText -Arguments @('f\w+') -Options @{ Regex = $true; Separator = '\t' }
    Assert-Contains $r.Output "foo`tfoo`tfoo`t" '-Separator converts \t and implies -OnlyMatching'

    $r = Invoke-ClipGre -Clipboard "eins`nzwei drei`nvier" -Arguments @('zwei.*\n.*vi') -Options @{ r = $true }
    Assert-Contains $r.Output '     3: vier' 'multi-line match marks all its lines'

    $r = Invoke-ClipGre -Clipboard 'ab' -Arguments @('(') -Options @{ Regex = $true }
    Assert-Contains $r.Output 'Skipping invalid pattern' 'invalid regex in grep mode gives a warning'

    $r = Invoke-ClipGre -Clipboard 'aXa' -Arguments @('a') -Options @{ Verbose = $true }
    Assert-Contains $r.Output "Match 'a' at index 2, length 1, line 1" '-Verbose shows index and length'

    Write-Host "`nSubstitution" -ForegroundColor Cyan
    $r = Invoke-ClipGre -Clipboard 'foo bar' -Arguments @('foo', 'kostet $0')
    Assert-Equal $r.Clipboard 'kostet $0 bar' 'literal replacement keeps $ literally'

    $r = Invoke-ClipGre -Clipboard 'a1 b22' -Arguments @('(\d+)', '[$1]', 'i')
    Assert-Equal $r.Clipboard 'a[1] b[22]' 'third positional value = regex flags, groups work'

    $r = Invoke-ClipGre -Clipboard 'Foo foo' -Arguments @('foo', 'x') -Options @{ i = $true }
    Assert-Equal $r.Clipboard 'x x' '-i ignores case'

    $r = Invoke-ClipGre -Clipboard 'abcabc' -Arguments @('b', '')
    Assert-Equal $r.Clipboard 'acac' "empty replacement '' deletes"

    $r = Invoke-ClipGre -Clipboard 'abcabc' -Arguments @('b', 'X') -Options @{ Delete = $true }
    Assert-Equal $r.Clipboard 'acac' '-Delete ignores replacements'

    $r = Invoke-ClipGre -Clipboard 'xyz' -Arguments @('abc', 'y') -Options @{ Swap = $true }
    Assert-Equal $r.Clipboard 'xabcz' '-Swap swaps search and replacement'

    $r = Invoke-ClipGre -Clipboard 'C' -Options @{ Search = @('A', 'B'); Replace = @('B', 'C'); Swap = $true }
    Assert-Equal $r.Clipboard 'A' '-Swap undoes a chain in reverse order'

    $r = Invoke-ClipGre -Clipboard 'Y' -Options @{ Search = @('x', 'z'); Replace = @('Y', ''); Swap = $true }
    Assert-Equal $r.Clipboard 'x' '-Swap skips deletions'
    Assert-Contains $r.Output 'a deletion cannot be swapped' '-Swap warns about skipped deletions'

    $r = Invoke-ClipGre -Clipboard 'ab' -Arguments @('', '-')
    Assert-Equal $r.Clipboard '-a-b-' 'empty search pattern matches everywhere'
    Assert-Contains $r.Output 'Empty search pattern' 'empty search pattern gives a warning'

    $r = Invoke-ClipGre -Clipboard 'a' -Arguments @('a', @('b', 'c'))
    Assert-Contains $r.Output 'more replacements (2) than search patterns (1)' 'too many replacements is an error'

    $r = Invoke-ClipGre -Clipboard 'same' -Arguments @('x', 'y')
    Assert-Contains $r.Output 'Clipboard text has not changed.' 'unchanged text is reported'

    $r = Invoke-ClipGre -Clipboard 'aa' -Arguments @('a') -Options @{ RegexFlags = 'jx' }
    Assert-Contains $r.Output "can only be combined with 'i', 'm' and 'c'" 'invalid flag combination is reported'

    if (-not [enum]::IsDefined([System.Text.RegularExpressions.RegexOptions], 'NonBacktracking')) {
        $r = Invoke-ClipGre -Clipboard 'aa' -Arguments @('a') -Options @{ flags = 'b' }
        Assert-Contains $r.Output 'needs PowerShell 7' "flag 'b' reports that it needs PowerShell 7"
    }

    Write-Host "`nPattern files" -ForegroundColor Cyan
    $r = Invoke-ClipGre -Clipboard 'foo FOO bar' -Arguments @('bar', 'baz') -Options @{ PairFile = 'pairs.txt' }
    Assert-Equal $r.Clipboard 'FOO FOO baz' 'pair file stays paired next to inline patterns'
    Assert-Contains $r.Output 'odd number of lines' 'odd pair file gives a warning'

    $r = Invoke-ClipGre -Clipboard 'line1 line2' -Options @{ SearchFile = 'search.txt'; ReplaceFile = 'replace.txt' }
    Assert-Equal $r.Clipboard 'ONE ' 'search/replace files paired by line, missing replacement deletes'

    $r = Invoke-ClipGre -Clipboard "xx line1`nline2 yy" -Options @{ SearchFile = 'search.txt'; PatternPerFile = $true; Replace = 'Z' }
    Assert-Equal $r.Clipboard 'xx Z yy' '-PatternPerFile: whole file is one pattern without final line break'

    Write-Host "`nFiles" -ForegroundColor Cyan
    $r = Invoke-ClipGre -Arguments @('foo') -Options @{ Path = 'data'; Recurse = $true }
    Assert-Contains $r.Output 'BINARY FILE (skipped)' 'binary files are skipped'
    Assert-Contains $r.Output 'foo in sub' '-Recurse includes subfolders'

    $r = Invoke-ClipGre -Arguments @('foo') -Options @{ Path = 'data'; IncludeBinary = $true; CountOnly = $true }
    Assert-Contains $r.Output 'bin.dat: 1' '-IncludeBinary processes binary files'

    $r = Invoke-ClipGre -Arguments @('foo') -Options @{ files = 'data'; FilesWithMatches = $true }
    Assert-That (-not $r.Output.Contains('b.txt') -and $r.Output.Contains('a.txt')) '-FilesWithMatches lists files, no recursion without -Recurse' $r.Output

    $r = Invoke-ClipGre -Arguments @('foo') -Options @{ Path = (Join-Path 'data' '*.txt'); CountOnly = $true }
    Assert-Contains $r.Output 'a.txt: 1' 'wildcards in -Path'

    $r = Invoke-ClipGre -Arguments @('foo', 'XX') -Options @{ Path = @((Join-Path 'data' 'a.txt'), (Join-Path (Join-Path 'data' 'sub') 'b.txt')); Separator = '\n---\n' }
    Assert-Equal $r.Clipboard "alpha XX`nbeta`n`n---`nXX in sub`n" 'substituted files are joined with -Separator into the clipboard'

    Copy-Item -LiteralPath (Join-Path $dataDir 'bom.txt') -Destination (Join-Path $dataDir 'bom2.txt')
    $r = Invoke-ClipGre -Arguments @('foo', 'bar') -Options @{ Path = (Join-Path 'data' 'bom2.txt'); InPlace = $true }
    $bytes = [System.IO.File]::ReadAllBytes((Join-Path $dataDir 'bom2.txt'))
    Assert-That ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) '-InPlace keeps the BOM'
    Assert-Equal ([System.IO.File]::ReadAllText((Join-Path $dataDir 'bom2.txt'))) "BOM bar $([char]0xE4)`r`n" '-InPlace writes the substituted text'
    Assert-That (Test-Path -LiteralPath (Join-Path $dataDir 'bom2.txt.bak')) '-InPlace creates a .bak backup'

    $r = Invoke-ClipGre -Clipboard 'a' -Arguments @('a', 'b') -Options @{ InPlace = $true }
    Assert-Contains $r.Output '-InPlace needs input files' '-InPlace without -Path is an error'

    Write-Host "`nOutput files" -ForegroundColor Cyan
    $outDir = Join-Path $testRoot 'out'
    $null = New-Item -ItemType Directory -Path $outDir
    $r = Invoke-ClipGre -Clipboard 'foo' -Arguments @('foo', 'bar') -Options @{ OutFile = (Join-Path 'out' 'result.csv') }
    $written = @(Get-ChildItem -LiteralPath $outDir -Filter 'result_*.csv')
    Assert-That ($written.Count -eq 1) '-OutFile keeps folder and extension, adds timestamp' $r.Output
    Assert-Equal $r.Clipboard 'foo' '-OutFile leaves the clipboard unchanged'

    $r = Invoke-ClipGre -Clipboard 'foo x foo' -Arguments @('foo') -Options @{ OnlyMatching = $true; OutFile = (Join-Path 'out' 'list') }
    $list = @(Get-ChildItem -LiteralPath $outDir -Filter 'list_*.txt')
    Assert-That ($list.Count -eq 1 -and [System.IO.File]::ReadAllText($list[0].FullName) -eq "foo`nfoo`n") '-OnlyMatching list written to file'
    Assert-That (-not $r.Output.Contains('Results saved')) '-OnlyMatching saves quietly'

    $r = Invoke-ClipGre -Clipboard 'foo' -Arguments @('foo', 'bar') -Options @{ Grep = $true; Save = $true }
    Assert-That (@(Get-ChildItem -Filter 'Output_grep_*.txt').Count -eq 1 -and @(Get-ChildItem -Filter 'Output_2*.txt').Count -eq 1) 'grep + substitution with -Save write two separate files' $r.Output

    Write-Host "`nText analysis and flow" -ForegroundColor Cyan
    $r = Invoke-ClipGre -Clipboard "Hallo Welt. Wie geht's?`r`nmail a@b.de https://x.org" -Options @{ ExtendedStats = $true }
    Assert-Contains $r.Output 'Character map' '-ExtendedStats shows the character map'
    Assert-Contains $r.Output 'Grapheme clusters' '-ExtendedStats shows text metrics'
    Assert-That ($r.Output -match 'E-mail addresses\s+1\b') 'e-mail count'
    Assert-That ($r.Output -match 'Currency symbols') '-ExtendedStats shows extended counts'

    $r = Invoke-ClipGre -Clipboard "ab a`n" -Options @{ CharMap = $true; SortBy = 'Char' }
    Assert-Contains $r.Output '\n ' '-CharMap shows line breaks as \n'
    Assert-That (-not $r.Output.Contains('Grapheme clusters')) '-CharMap alone shows no metrics'

    $r = Invoke-ClipGre -Clipboard ("a`r`nb" + [char]::ConvertFromUtf32(0x1F642)) -Options @{ CharMap = $true }
    Assert-Contains $r.Output 'U+000D, U+000A' 'code points of CR LF'
    Assert-Contains $r.Output 'U+1F642' 'code point of an emoji'

    $r = Invoke-ClipGre -Clipboard '' -Arguments @('a') -Options @{ Repeat = 2 }
    Assert-That (([regex]::Matches($r.Output, 'Clipboard is empty')).Count -eq 2) 'empty clipboard skips each run of -Repeat' $r.Output

    $r = Invoke-ClipGre -Clipboard 'x' -Arguments @('x') -Options @{ Delay = 'abc' }
    Assert-Contains $r.Output "Invalid delay 'abc'" 'invalid -Delay is reported'

    $r = Invoke-ClipGre -Options @{ h = $true }
    Assert-Contains $r.Output 'GREP OUTPUT' '-h shows the help'
}
finally {
    Set-Location -LiteralPath $previousLocation
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item function:\Get-Clipboard, function:\Set-Clipboard -ErrorAction SilentlyContinue
}

Write-Host ''
$color = 'Green'
if ($script:Failed -gt 0) { $color = 'Red' }
Write-Host "Passed: $script:Passed  Failed: $script:Failed" -ForegroundColor $color
exit $script:Failed
