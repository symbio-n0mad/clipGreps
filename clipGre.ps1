param (
    [Alias("search", "find", "findText", "st", "ft")]
    [string[]]$searchText = @(),   
    [Alias("replace", "displace", "rt")]          
    [string[]]$replaceText = @(),
    [Alias("modifier", "m")] 
    [string]$flags = "",
    [Alias("applyToFile", "readFromFile", "ff", "files")]    
    [string[]]$fromFile = @(),
    [Alias("overwrite", "ip")]          
    [switch]$inPlace = $false,  # planned: in-place substitutions for files
    [Alias("searchFile", "sfile", "sf")]
    [string[]]$searchFilePath = @(),    
    [Alias("replaceFile", "rfile", "rf")]          
    [string[]]$replaceFilePath = @(),
    [Alias("searchFolder", "sdir", "sd")]
    [string[]]$searchFolderPath = @(),   
    [Alias("replaceFolder", "rdir", "rd")]          
    [string[]]$replaceFolderPath = @(),
    [Alias("pairsFile", "lazyPairs", "lazyFile", "mf", "lf")]          
    [string[]]$mappingFile = @(),
    [Alias("readInput", "ri", "ia")] 
    [switch]$interactive,
    [Alias("allFiles", "readAll", "sb")] 
    [switch]$scanBinary,
    [Alias("wait", "delay", "t", "sleep")] 
    [string]$timeout = "0",
    [Alias("h", "hint", "usage")]          
    [switch]$Help = $false,
    [Alias("ignoreCase", "ic", "noCase", "i")]          
    [switch]$ci = $false,
    [Alias("w", "save", "write")]          
    [switch]$fileOutput = $false,
    [Alias("saveAs", "o", "out")]
    [string]$fileName = "",  
    [Alias("regEx", "regExP")]          
    [switch]$r,  
    [Alias("after")]          
    [int16]$A = 0,
    [Alias("before")]          
    [int16]$B = 0,
    [Alias("context", "combined")]          
    [int16]$C = 0,
    [Alias("fullFile", "f")]          
    [switch]$wholeFile = $false,  
    [Alias("stay","confirm", "p")]
    [switch]$persist = $false,  
    [Alias("grep", "filter", "x", "extract", "g")]    
    [switch]$extractMatch,
    [Alias("d", "del", "remove")]    
    [switch]$delete,
    [Alias("subfolder", "recursive", "subdirs")]    
    [switch]$recurse,
    [Alias("forever", "relentless", "oo")]    
    [switch]$endless,
    [Alias("repeat", "l")]    
    [int]$loop = 1,
    [Alias("measTim", "measure", "bm")]
    [switch]$benchmark = $false,
    [Alias("sub", "substitution", "s")]    
    [switch]$substitute,
    [Alias("count", "statistics", "n")]    
    [switch]$stats,
    [Alias("raw", "onlyMatches", "plainGrep", "pg", "sep", "separator")]    
    [string]$plain,
    [Alias("switch", "rev", "exchange", "e")]    
    [switch]$revert
)


function wait-Timeout([int]$additionalTime = 0) {
    # accepts additional timeout, for internals requiring waiting time (e.g. help text)
    $newDelay = [math]::Abs([int]([math]::Round(([double]($timeout -replace ',','.') * 1000)))) + $additionalTime #convert , to . then from string to double multiply 1k then round and convert to int and then take abs
    if ($newDelay -ne 0){
        Start-Sleep -Milliseconds ($newDelay)
    }
}

function confirm-exit() {
    if ($persist){
        # Write-Host "Press Enter to end run..."
        Write-Host "Press any key to continue..."
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        # [void][System.Console]::ReadLine()
    }
}

function Get-StringLineInfo {
    # copilot
    <#
    .SYNOPSIS
    Returns detailed line and position metadata for a substring inside a larger text.

    .DESCRIPTION
    Computes positional information (start/end positions, start/end line numbers,
    and total line count) for a selected substring within a given text.  
    The function scans the text for newline characters and derives line boundaries
    purely from character indices. This is useful when analyzing match objects, 
    editor selections, or text regions that need to be mapped to their line context.

    .PARAMETER Text
    The full input text in which position and line data should be evaluated.

    .PARAMETER Position
    The zero-based character index where the target substring begins.

    .PARAMETER Length
    The length (in characters) of the substring for which line metadata is requested.

    .OUTPUTS
    PSCustomObject
    A structured object containing:
    - StartPosition: Beginning index of the substring
    - EndPosition: Ending index (exclusive)
    - StartLine: Line number where the substring begins (1-based)
    - EndLine: Line number where the substring ends (1-based)
    - TotalLines: Total number of lines in the input text

    .EXAMPLE
    PS> Get-StringLineInfo -Text $content -Position 42 -Length 12
    Returns positional and line-number metadata for the 12-character region starting at index 42.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Text,

        [Parameter(Mandatory)]
        [int]$Position,

        [Parameter(Mandatory)]
        [int]$Length
    )

    $lineBreaks = New-Object System.Collections.Generic.List[int]

    for ($var = 0; $var -lt $Text.Length; $var++) {
        if ($Text[$var] -eq "`n") {
            $lineBreaks.Add($var)
        }
    }

    $totalLines  = $lineBreaks.Count + 1
    $endPosition = $Position + $Length

    $startLine = ($lineBreaks | Where-Object { $_ -lt $Position }).Count + 1
    $endLine   = ($lineBreaks | Where-Object { $_ -lt $endPosition }).Count + 1

    [PSCustomObject]@{
        StartPosition = $Position
        EndPosition   = $endPosition
        StartLine     = $startLine
        EndLine       = $endLine
        TotalLines    = $totalLines
    }
}
function Get-CharacterMap {
    # copilot
    <#
    .SYNOPSIS
    Generates a frequency map of all Unicode text elements in a string.

    .DESCRIPTION
    Enumerates grapheme clusters (full Unicode text elements, not individual UTF-16 code units)
    inside the input text and computes how often each element occurs.  
    The function supports optional sorting (by character or descending count), and can visualize
    whitespace characters using special symbols for debugging or text inspection.  
    It also reports Unicode codepoints for multi-code-unit characters such as emojis,
    diacritics, and surrogate pairs.

    .PARAMETER Text
    The input string whose Unicode elements should be analyzed.

    .PARAMETER SortBy
    Specifies the ordering of the output.  
    Accepted values:
    - "Count": Sort descending by frequency (default)
    - "Char": Sort lexicographically by the text element itself

    .PARAMETER ShowWhitespace
    If supplied, common whitespace characters (space, tab, carriage return, newline)
    are replaced with visible glyphs (␠, ␉, ␍, ␊) in the output table.

    .OUTPUTS
    String
    A formatted table showing:
    - Character (or visible whitespace glyph)
    - Count of occurrences
    - Percentage of total graphemes
    - Unicode codepoints (handles multi-code-unit characters)

    .EXAMPLE
    PS> Get-CharacterMap -Text "aä🙂🙂" -ShowWhitespace
    Displays counts and codepoints for all grapheme clusters, including emojis and diacritics.

    .EXAMPLE
    PS> Get-CharacterMap -Text $content -SortBy Char
    Sorts the map alphabetically by grapheme.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        # Optional: Sort order: Count (desc) or Char (asc)
        [ValidateSet('Count','Char')]
        [string]$SortBy = 'Count',

        # Optional: Render whitespace visibly (␠, ␉, ␍, ␊)
        [switch]$ShowWhitespace
    )

    # Count storage
    $counts = @{}

    # Enumerate Unicode text elements (graphemes)
    $enum = [System.Globalization.StringInfo]::GetTextElementEnumerator($Text)
    while ($enum.MoveNext()) {
        $g = [string]$enum.Current
        if ($counts.ContainsKey($g)) {
            $counts[$g] += 1
        } else {
            $counts[$g] = 1
        }
    }

    # Total elements
    $total = 0
    foreach ($v in $counts.Values) { $total += $v }

    # Sorting
    $keys =
        if ($SortBy -eq 'Char') {
            $counts.Keys | Sort-Object
        } else {
            # Count-desc, then Char
            $counts.GetEnumerator() |
                Sort-Object @{e = 'Value'; Descending = $true}, @{e = 'Key'} |
                ForEach-Object { $_.Key }
        }

    # Header
    Write-Host ("Character-Map (total: {0})" -f $total) -ForegroundColor Cyan
    $header = "{0,-12}  {1,5}  {2,7}  {3}" -f "Char","Count","Percent","Codepoints"
    Write-Host $header
    Write-Host ('-' * $header.Length)

    foreach ($k in $keys) {
        # Build UTF-32 codepoint list (handles surrogate pairs)
        $cpStrings = New-Object 'System.Collections.Generic.List[string]'
        $var = 0
        while ($var -lt $k.Length) {
            if ($var -lt $k.Length - 1 -and [char]::IsSurrogatePair($k[$var], $k[$var+1])) {
                $cp = [char]::ConvertToUtf32($k[$var], $k[$var+1])
                $var += 2
            } else {
                $cp = [int][char]$k[$var]
                $var += 1
            }
            $cpStrings.Add('U+' + $cp.ToString('X'))
        }

        # Optional: show whitespace visibly
        $display =
            if ($ShowWhitespace) {
                $k -replace ' ', '␠' -replace "`t", '␉' -replace "`r", '␍' -replace "`n", '␊'
            } else {
                $k
            }

        # Percentage with 2 decimals; locale-aware (e.g., 12,34 % in DE)
        $pct = if ($total -gt 0) { (100.0 * $counts[$k] / $total) } else { 0.0 }

        "{0,-12}  {1,5}  {2,6:N2} %  {3}" -f $display, $counts[$k], $pct, ($cpStrings -join ', ')
    }
}

function Get-TextMetricsPs5 {
    # copilot
    <#
    .SYNOPSIS
    Computes detailed Unicode and encoding-related metrics for a given string.

    .DESCRIPTION
    Analyzes a text string and returns multiple metrics related to its internal
    Unicode structure and encoding footprint. This includes UTF‑8 and UTF‑16 byte
    sizes, UTF‑16 code unit count, Unicode scalar values (code points), grapheme
    clusters (visual characters), and ASCII‑only diagnostics.

    The function correctly accounts for surrogate pairs when counting code points
    and uses .NET's StringInfo API to count user-perceived characters (graphemes).
    It is useful for debugging encoding issues, measuring text payload sizes, and
    distinguishing between ASCII and multibyte Unicode content—especially in
    Windows PowerShell 5 where Unicode handling can be subtle.

    .PARAMETER Text
    The input string to analyze. The text may contain arbitrary Unicode characters,
    including surrogate pairs, emoji, non‑ASCII symbols, or combining sequences.

    .OUTPUTS
    PSCustomObject
    An object with the following fields:

    - UTF8_Bytes        : Number of bytes required to encode the string in UTF‑8.
    - UTF16_Bytes       : Number of bytes required for UTF‑16 (little-endian).
    - CharUnits         : Count of UTF‑16 code units (`[string].Length`).
    - CodePoints        : Count of Unicode scalar values (surrogate‑aware).
    - Graphemes         : Count of user‑perceived characters (using StringInfo).
    - ASCII_CharCount   : Number of characters in the ASCII range U+0000–U+007F.
    - Contains_NonASCII : Boolean indicating whether the string contains characters
                        outside the ASCII range.

    .EXAMPLE
    PS> Get-TextMetricsPs5 -Text "Hi🙂"
    Returns byte sizes, code unit count, code points, and grapheme information for
    a mixed ASCII + emoji string.

    .EXAMPLE
    PS> Get-TextMetricsPs5 -Text $content
    Analyzes the full text content from a file or clipboard and reports Unicode
    structure details useful for debugging encoding issues.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Text
    )

    # Count UTF-8 and UTF-16 bytes
    $utf8Bytes  = [System.Text.Encoding]::UTF8.GetByteCount($Text)
    $utf16Bytes = [System.Text.Encoding]::Unicode.GetByteCount($Text)

    # Count UTF-16 code units (.NET char count)
    $charUnits = $Text.Length

    # Count Unicode code points (scalar values) by walking surrogate pairs
    function Get-CodePointCount {
        param([string]$S)
        $count = 0
        $var = 0
        while ($var -lt $S.Length) {
            $ch = $S[$var]
            $code = [int]$ch

            # High surrogate range: D800–DBFF
            if ($code -ge 0xD800 -and $code -le 0xDBFF) {
                if ($var + 1 -lt $S.Length) {
                    $next = [int]$S[$var + 1]
                    # Low surrogate range: DC00–DFFF
                    if ($next -ge 0xDC00 -and $next -le 0xDFFF) {
                        # Valid surrogate pair -> one code point
                        $count += 1
                        $var += 2
                        continue
                    }
                }
                # Unpaired high surrogate -> count as one code point
                $count += 1
                $var += 1
                continue
            }

            # Low surrogate without preceding high surrogate -> count as one code point
            if ($code -ge 0xDC00 -and $code -le 0xDFFF) {
                $count += 1
                $var += 1
                continue
            }

            # BMP char -> one code point
            $count += 1
            $var += 1
        }
        return $count
    }

    $codePoints = Get-CodePointCount -S $Text

    # Grapheme clusters (user-perceived characters)
    # StringInfo.ParseCombiningCharacters returns start indices of text elements
    $graphemes = [System.Globalization.StringInfo]::ParseCombiningCharacters($Text).Count

    # ASCII-only helper metrics
    $asciiChars = 0
    foreach ($c in $Text.ToCharArray()) {
        if ([int]$c -le 0x7F) { $asciiChars++ }
    }

    # Simple multibyte detection in UTF-8: any non-ASCII will push UTF-8 bytes above ASCII-char count
    $containsNonAscii = $utf8Bytes -gt $asciiChars

    [pscustomobject]@{
        UTF8_Bytes          = $utf8Bytes
        UTF16_Bytes         = $utf16Bytes
        CharUnits           = $charUnits
        CodePoints          = $codePoints
        Graphemes           = $graphemes
        ASCII_CharCount     = $asciiChars
        Contains_NonASCII   = $containsNonAscii
    }
}

function Read-Input {
    # Write-Host "read-input started"
    <# mostly copilot
        Purpose:
          Interactive input reader that decides between Substitution, Grep (text filter), or Deletion,
          and optionally enables regex (with or without flags). Returns a PSCustomObject
          with Flags/Search/Replace, keeping the existing contract.

        Notes:
          - All menus, variables, and comments are in English (as requested).
          - Operation modes are treated as mutually exclusive.
          - For Grep and Deletion, Replace will be $null.
          - For Substitution with regex, capture groups can be referenced via `$1, `$2, etc.
    #>

    # ---- If no operation has been selected, show a 3-way operation menu ----
    if (-not $Script:extractMatch -and -not $Script:substitute -and -not $Script:delete) {
        $opCaption = 'Missing CLI options, please specify your intention'
        $opMessage = 'Choose what you want to do:'
        $opChoices = @(
            [System.Management.Automation.Host.ChoiceDescription]::new('&Substitution', 'Perform a substitution')
            [System.Management.Automation.Host.ChoiceDescription]::new('&Grep (text filter)', 'Filter lines by a regex or plain text')
            [System.Management.Automation.Host.ChoiceDescription]::new('&Deletion', 'Delete matches (no replacement)')
        )
        $opDefault = 0
        $op = $Host.UI.PromptForChoice($opCaption, $opMessage, $opChoices, $opDefault)

        switch ($op) {
            0 { # Substitution
                $Script:substitute   = $true
                $Script:extractMatch = $false
                $Script:delete       = $false
            }
            1 { # Grep (text filter)
                $Script:extractMatch = $true
                $Script:substitute   = $false
                $Script:delete       = $false
            }
            2 { # Deletion
                $Script:delete       = $true
                $Script:substitute   = $false
                $Script:extractMatch = $false
            }
        }
    }
    # ---- Regex mode selection (only if \$Script:r is not already true) ----
    if (-not $Script:r) {
        # Write-Host "not script:r"
        $rxCaption = 'Regular expression'
        $rxMessage = 'Enable regex for the input?'
    
        $rxChoices = @(
            [System.Management.Automation.Host.ChoiceDescription]::new('&Literal Text', 'Use plain text (literal search)')
            [System.Management.Automation.Host.ChoiceDescription]::new('&Regex without flags', 'Enable regex without flags')
            [System.Management.Automation.Host.ChoiceDescription]::new('Regex &with flags', 'Enable regex and enter flags')
        )
        $rxDefault = 0
        $rx = $Host.UI.PromptForChoice($rxCaption, $rxMessage, $rxChoices, $rxDefault)

        switch ($rx) {
            0 {
                $Script:r = $false
                $flags = ""
            }
            1 {
                $Script:r = $true
                $flags = ""
            }
            2 {
                $Script:r = $true
                $flags = Read-Host "Enter regex flags (imsx ecujrb, 'i' ignore case, 'm' multiline, etc.; empty for none) "
            }
        }
    }
    elseif ($Script:r -and ( "" -eq $Script:flags )) {
        # if regex enabled but no flags provided enter flags now
        $flags = Read-Host "Enter regex flags (imsx ecujrb, 'i' ignore case, 'm' multiline, etc.; empty for none) "
    }

    # ---- Read search text ----
    $search = ""
    if ($Script:r) {
        $search = Read-Host "Please enter search text (.NET regex syntax allowed)"
    } else {
        $search = Read-Host "Please enter search text"
    }
    # ---- Read replacement when applicable ----
    # For Grep and Deletion, replacement is not applicable -> $null
    if (-not $Script:delete -and -not $Script:extractMatch) {
        if ($Script:r) {
            Write-Host "You can reference capture groups via `$1, `$2, etc."
        }
        $replace = Read-Host "Please enter replacement text"
    }

    # ---- Prepare return ----
    # $flags = $Script:flags
    return [PSCustomObject]@{
        Flags   = $flags
        Search  = $search
        Replace = $replace
    }
}

function write-File([string]$content) {
    <#
    .SYNOPSIS
    write-File(<STRING>)
    
    .DESCRIPTION
    accepts string as argument and writes it to a file
    
    .PARAMETER content
    Parameter description
    
    .EXAMPLE
    An example
    
    .NOTES
    General notes
    #>
  # Timestamp generation
    $nameStamp = Get-Date -Format "yyyyMMdd_HHmmss"

    if ($loop -gt 1 ) {
        $nameStamp = "$runNr-$nameStamp"
    }

    # Check, for content of $fileName 
    if ([string]::IsNullOrWhiteSpace($fileName)) {
        # empty -> use generic name
        $fileName = "Output_$nameStamp.txt"
    } else {
        # Name provided? ok then use it!
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
        $fileName = "${baseName}_$nameStamp.txt"
    }

    # Save file 
    $content | Out-File -FilePath $fileName -Encoding UTF8
    if ($PSBoundParameters.ContainsKey("plain") -eq $false){
        if ($loop -gt 1 ) {
            Write-Host "Run nr. $runNr`: " -NoNewline
        }
        Write-Output "Results saved in file: $fileName"
    }
}

function Show-Helptext {  # self descriptive: print help text
    Write-Host ""
    Write-Host "clipGre.ps1 - Search, extract and replace text from clipboard or files"
    Write-Host ""
    Write-Host "Basic example:"
    Write-Host "  clipGre.ps1 -search 'oldValue' [-replace 'newValue']"
    Write-Host ""
    Write-Host "INPUT OPTIONS"
    Write-Host "  -mf / -mappingFile         File with explicit search→replace mappings"
    Write-Host "  -st / -searchText          String or list of strings to search for"
    Write-Host "  -rt / -replaceText         Replacement string(s)"
    Write-Host "  -sf / -searchFilePath      File containing search strings (one per line)"
    Write-Host "  -rf / -replaceFilePath     File containing replacement strings (one per line)"
    Write-Host "  -sd / -searchFolderPath    Folder containing multiple files with search text"
    Write-Host "  -rd / -replaceFolderPath   Folder containing multiple files with replacement text"
    Write-Host ""

    Write-Host "OPERATION MODES"
    Write-Host "  -g  / -grep / -extractMatch   Extract matching text only"
    Write-Host "  -s  / -substitute             Perform search and replace"
    Write-Host "  -e  / -revert                 Swap search and replace values (reverse substitution)"
    Write-Host "  -d  / -delete                 Delete the matches"
    Write-Host ""

    Write-Host "MATCHING BEHAVIOUR"
    Write-Host "  -i / -ignoreCase            Ignore case while matching"
    Write-Host "  -r  / -RegEx                Enable Regular Expressions"
    Write-Host "  -m  / -flags                Pass regex engine flags (enables -r implicitly)"
    Write-Host ""
    Write-Host "CONTEXT OPTIONS"
    Write-Host "  -A / -after                  Number of lines after a match"
    Write-Host "  -B / -before                 Number of lines before a match"
    Write-Host "  -C / -combined               Apply same number of lines before and after"
    Write-Host "  -pg / plain                  Only matches (and provided separation string) for grep output"
    Write-Host ""

    Write-Host "INPUT / OUTPUT CONTROL"
    Write-Host "  -ia / -interactive           Ask user for search/replace strings interactively"
    Write-Host "  -f  / -fullFile              Process file as whole content (instead of line-by-line)"
    Write-Host "  -w  / -fileOutput            Write output to a file instead of clipboard"
    Write-Host "  -o  / -saveAs                Specify output filename (optional)"
    Write-Host ""

    Write-Host "FLOW CONTROL"
    Write-Host "  -t  / -timeout               Wait time (seconds) before script exits"
    Write-Host "  -p  / -persist               Require confirmation before closing the window"
    Write-Host "  -oo  / -endless               Repeat the operation endlessly"
    Write-Host "  -l  / -loop                  Repeat the operation n times"
    Write-Host ""

    Write-Host "MISC"
    Write-Host "  -bm / -benchmark             Measure execution and processing time"
    Write-Host "  -n  / -stats                 Display statistics about the processed text"
    Write-Host "  -h  / -help                  Show this help text"
    Write-Host ""
}

function set-RegexFlags() {
    # partly copilot (boilerplate)
    foreach ($char in $script:flags.ToCharArray()) {  # Convert flag string to regex options
        switch ($char) {
            'n' { $regexOptions = $regexOptions -bor [System.Text.RegularExpressions.RegexOptions]::None}
            'i' { $regexOptions = $regexOptions -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase }
            'm' { $regexOptions = $regexOptions -bor [System.Text.RegularExpressions.RegexOptions]::Multiline }
            's' { $regexOptions = $regexOptions -bor [System.Text.RegularExpressions.RegexOptions]::Singleline }
            'x' { $regexOptions = $regexOptions -bor [System.Text.RegularExpressions.RegexOptions]::IgnorePatternWhitespace }

            # exotic options:
            'e' { $regexOptions = $regexOptions -bor [System.Text.RegularExpressions.RegexOptions]::ExplicitCapture }
            'c' { $regexOptions = $regexOptions -bor [System.Text.RegularExpressions.RegexOptions]::Compiled }
            'u' { $regexOptions = $regexOptions -bor [System.Text.RegularExpressions.RegexOptions]::CultureInvariant }
            'j' { $regexOptions = $regexOptions -bor [System.Text.RegularExpressions.RegexOptions]::ECMAScript }
            'r' { $regexOptions = $regexOptions -bor [System.Text.RegularExpressions.RegexOptions]::RightToLeft }
            'b' { $regexOptions = $regexOptions -bor [System.Text.RegularExpressions.RegexOptions]::NonBacktracking }

            default {
                Write-Warning "Unknown modifier: '$char'"
            }
        }
    }
    if ($script:flags.Contains('j') -and ($script:flags.Contains('r') -or $script:flags.Contains('u') -or $script:flags.Contains('b') -or $script:flags.Contains('e') -or $script:flags.Contains('x'))) {
        Write-Warning "Warning:  'j' (ECMAScript) cannot be combined with 'x', 'e', 'b', 'r' or 'u'."
       
    }
    if ($script:flags.Contains('b') -and $script:flags.Contains('r')) {
        Write-Warning "Incompatible flags detected: 'b' (NonBacktracking) and 'r' (RightToLeft) should not be combined."
       
    }
    return [PSCustomObject]@{
        Options  = $regexOptions
    }
}


function get-SearchnReplaceExpressions() {
    # partly copilot (lazy parts)
    $searchLinesInside  = @()  # initialize arrays
    $replaceLinesInside = @()  # empty arrays

    # Add the provided search/replace text from CLI arguments to searcharray
    if ($searchText | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) {
        $searchLinesInside += $searchText  # add cli args to array
    }
    if ($replaceText) {  # Explicitly allowed to be empty (for deletion)
        $replaceLinesInside += $replaceText
    }

    # Get list of text files from each provided folder path
    $searchFolderPath = $searchFolderPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }  # Filter empty entries,
    foreach ($folder in $searchFolderPath) {
        if (Test-Path -LiteralPath $folder) {
            $searchFilePath += Get-ChildItem -LiteralPath $folder -Filter *.txt -File |
                            Sort-Object Name |
                            Select-Object -ExpandProperty FullName
        }
    }
    $replaceFolderPath = $replaceFolderPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } # Filter empty entries,
    foreach ($folder in $replaceFolderPath) {
        if (Test-Path -Path $folder) {
            $replaceFilePath += Get-ChildItem -LiteralPath $folder -Filter *.txt -File |
                            Sort-Object Name |
                            Select-Object -ExpandProperty FullName
        }
    }

    $searchFilePath = $searchFilePath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } # For case of wrong user input, filter empty entries
    $replaceFilePath = $replaceFilePath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } # For case of wrong user input,

    if ($wholeFile) {  # Read as whole files or linewise
        foreach ($file in $searchFilePath) {
            if (Test-Path -Path $file -PathType Leaf) {
                # Read file contents and append to search/replace arrays
                $searchContent = Get-Content -Path $file -Raw
                $searchLinesInside  += $searchContent  # Whole file as one entry
            }
        }
        foreach ($file in $replaceFilePath) {
            if (Test-Path -Path $file -PathType Leaf) {
                # Read file contents and append to search/replace arrays
                $replaceContent = Get-Content -Path $file -Raw
                if ($null -eq $replaceContent) {
                    $replaceContent = ''
                }
                $replaceLinesInside += $replaceContent  # Whole file as one entry
            }
        }
    } else {  # Linewise reading, lines as elements of arrays
        foreach ($file in $replaceFilePath) {
            if (Test-Path -Path $file -PathType Leaf) {
                $replaceLinesInside += @(Get-Content -Path $file)  # Urgent need of arrays: @( )
            }
        }
        foreach ($file in $searchFilePath) {
            if (Test-Path -Path $file -PathType Leaf) {
                $searchLinesInside += @(Get-Content -Path $file) 
            }
        }
    }
    # Read lazy file
    if ($mappingFile) {
        foreach ($path in $mappingFile) {
            if ([string]::IsNullOrWhiteSpace($path)) { continue }
            # If it's a directory
            if (Test-Path $path -PathType Container) {
                # Take all files in top-level directory (no subfolders)
                $files = Get-ChildItem -Path $path -File

                foreach ($file in $files) {
                    $lines = Get-Content $file.FullName
                    for ($i = 0; $i -lt $lines.Count; $i++) {
                        if ($i % 2 -eq 0) {
                            $searchLinesInside  += $lines[$i]
                        } else {
                            $replaceLinesInside += $lines[$i]
                        }
                    }
                }
            # If it's a file
            } elseif (Test-Path $path -PathType Leaf) {
                $lines = Get-Content $path
                for ($i = 0; $i -lt $lines.Count; $i++) {
                    if ($i % 2 -eq 0) {
                        $searchLinesInside  += $lines[$i]
                    } else {
                        $replaceLinesInside += $lines[$i]
                    }
                }
            } else {
                Write-Warning "Path not found: $path"
            }
        }
    }
    return [PSCustomObject]@{
        SearchFor  = $searchLinesInside
        ReplaceWith = $replaceLinesInside
    }
}

function show-Stats() {
                Write-Host ""
            "-" * 25
            $metrics = Get-TextMetricsPs5 -Text $clipboardUnchanged
            
            Write-Host "UTF-8 Bytes        : " -NoNewline -ForegroundColor Gray
            Write-Host $metrics.UTF8_Bytes        -ForegroundColor Yellow

            Write-Host "UTF-16 Bytes       : " -NoNewline -ForegroundColor Gray
            Write-Host $metrics.UTF16_Bytes       -ForegroundColor Cyan

            Write-Host "UTF-16 Code Units  : " -NoNewline -ForegroundColor Gray
            Write-Host $metrics.CharUnits         -ForegroundColor Green

            Write-Host "Unicode CodePoints : " -NoNewline -ForegroundColor Gray
            Write-Host $metrics.CodePoints        -ForegroundColor Magenta

            Write-Host "Grapheme Clusters  : " -NoNewline -ForegroundColor Gray
            Write-Host $metrics.Graphemes         -ForegroundColor Blue

            Write-Host "ASCII Characters   : " -NoNewline -ForegroundColor Gray
            Write-Host $metrics.ASCII_CharCount   -ForegroundColor DarkYellow

            Write-Host "Contains Non-ASCII : " -NoNewline -ForegroundColor Gray
            Write-Host $metrics.Contains_NonASCII -ForegroundColor Red
            "-" * 25
            Write-Host ""
            Get-CharacterMap -Text $clipboardUnchanged
            Write-Host ""
            # Additional regex-based statistics (ready for copy&paste)
            # Character count
            Write-Host "Character count (dot-matches-all, regex: `".`"): " -NoNewline 
            Write-Host ([System.Text.RegularExpressions.Regex]::Matches($clipboardUnchanged, ".", [System.Text.RegularExpressions.RegexOptions]::Singleline)).Count -ForegroundColor Magenta
            # digit count
            Write-Host "Digit count (regex: `"\d`"): " -NoNewline 
            Write-Host ([System.Text.RegularExpressions.Regex]::Matches($clipboardUnchanged, "\d", [System.Text.RegularExpressions.RegexOptions]::Singleline)).Count -ForegroundColor DarkMagenta
            # currency symbols count
            Write-Host "Currency symbols count (regex: `"\p{Sc}`"): " -NoNewline 
            Write-Host ([System.Text.RegularExpressions.Regex]::Matches($clipboardUnchanged, "\p{Sc}", [System.Text.RegularExpressions.RegexOptions]::Singleline)).Count -ForegroundColor DarkMagenta    
            # math symbols count
            Write-Host "Math symbols count (regex: `"\p{Sm}`"): " -NoNewline 
            Write-Host ([System.Text.RegularExpressions.Regex]::Matches($clipboardUnchanged, "\p{Sm}", [System.Text.RegularExpressions.RegexOptions]::Singleline)).Count -ForegroundColor DarkMagenta         
            # url count
            Write-Host "URL count (regex: `"t\bhttps?://[^\s)`"]+`"): " -NoNewline 
            Write-Host ([System.Text.RegularExpressions.Regex]::Matches($clipboardUnchanged, "\bhttps?://[^\s)`"]+", [System.Text.RegularExpressions.RegexOptions]::Singleline)).Count -ForegroundColor DarkMagenta         
            # Integer-like numbers count, optional sign
            # e-mail count
            Write-Host "E-mail count (regex: `"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b`"): " -NoNewline 
            Write-Host ([System.Text.RegularExpressions.Regex]::Matches($clipboardUnchanged, "\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b", [System.Text.RegularExpressions.RegexOptions]::Singleline)).Count -ForegroundColor DarkMagenta         
            # Integer-like numbers count, optional sign
            Write-Host "Integer-like numbers count (regex: `"[-+]?\d+`"): " -NoNewline 
            Write-Host ([System.Text.RegularExpressions.Regex]::Matches($clipboardUnchanged, "[-+]?\d+", [System.Text.RegularExpressions.RegexOptions]::Singleline)).Count -ForegroundColor Magenta
            # Integer-like numbers unicode count, optional sign
            Write-Host "Integer-like unicode count (regex: `"(?<![\p{L}\p{M}])[-+]?\d+(?![\p{L}\p{M}])`"): " -NoNewline 
            Write-Host ([System.Text.RegularExpressions.Regex]::Matches($clipboardUnchanged, "(?<![\p{L}\p{M}])[-+]?\d+(?![\p{L}\p{M}])", [System.Text.RegularExpressions.RegexOptions]::Singleline)).Count -ForegroundColor DarkMagenta
            # Decimal numbers dot/comma
            Write-Host "Decimal numbers unicode count (regex: `"(?<![\p{L}\p{M}])[-+]?\d+([.,]\d+)?(?![\p{L}\p{M}])`"): " -NoNewline 
            Write-Host ([System.Text.RegularExpressions.Regex]::Matches($clipboardUnchanged, "(?<![\p{L}\p{M}])[-+]?\d+([.,]\d+)?(?![\p{L}\p{M}])", [System.Text.RegularExpressions.RegexOptions]::Singleline)).Count -ForegroundColor Magenta
            # Unicodeword count
            Write-Host "Word count unicode (no options, regex: `"\b[\p{L}\p{M}\p{N}]+\b`"): " -NoNewline 
            Write-Host ([System.Text.RegularExpressions.Regex]::Matches($clipboardUnchanged, "\b[\p{L}\p{M}\p{N}]+\b", [System.Text.RegularExpressions.RegexOptions]::None)).Count -ForegroundColor Magenta
            #multiple spaces count
            Write-Host "Multiple spaces count (regex: `" {2,}`"): " -NoNewline 
            Write-Host ([System.Text.RegularExpressions.Regex]::Matches($clipboardUnchanged, " {2,}", [System.Text.RegularExpressions.RegexOptions]::None)).Count -ForegroundColor Magenta

            # Sentence count
            Write-Host "Sentence count (no options, regex: `"(?<=[\.!\?])\s+`"): " -NoNewline 
            Write-Host ([System.Text.RegularExpressions.Regex]::Matches($clipboardUnchanged, "(?<=[\.!\?])\s+", [System.Text.RegularExpressions.RegexOptions]::None)).Count -ForegroundColor DarkMagenta
            # Non-empty line count
            Write-Host "Non-empty line count (multiline, regex: `"^(?=.*\S).+$`"): " -NoNewline 
            Write-Host ([System.Text.RegularExpressions.Regex]::Matches($clipboardUnchanged, "^(?=.*\S).+$", [System.Text.RegularExpressions.RegexOptions]::Multiline)).Count -ForegroundColor Blue
            # Line count
            Write-Host "Linebreak count (no options, regex: `"\r?\n`"): " -NoNewline 
            Write-Host ([System.Text.RegularExpressions.Regex]::Matches($clipboardUnchanged, "\r?\n", [System.Text.RegularExpressions.RegexOptions]::None)).Count -ForegroundColor DarkBlue
            # Line count
            Write-Host "Line count (multiline, regex: `"^`"): " -NoNewline 
            Write-Host ([System.Text.RegularExpressions.Regex]::Matches($clipboardUnchanged, "^", [System.Text.RegularExpressions.RegexOptions]::Multiline)).Count -ForegroundColor DarkBlue
            #field count
            Write-Host "Fields, space separated, like words (no options, regex: `"\s*\S+\s*`"): " -NoNewline 
            Write-Host ([System.Text.RegularExpressions.Regex]::Matches($clipboardUnchanged, "\s*\S+\s*", [System.Text.RegularExpressions.RegexOptions]::None)).Count -ForegroundColor Magenta
            #comma count +1
            Write-Host "Fields, comma separated_ commas +1 (no options, regex: `",`"): " -NoNewline 
            Write-Host (([System.Text.RegularExpressions.Regex]::Matches($clipboardUnchanged, ",", [System.Text.RegularExpressions.RegexOptions]::None)).Count+1) -ForegroundColor Magenta
            # Word count
            Write-Host "Word count (no options, regex: `"\b\w+\b`"): " -NoNewline 
            Write-Host ([System.Text.RegularExpressions.Regex]::Matches($clipboardUnchanged, "\b\w+\b", [System.Text.RegularExpressions.RegexOptions]::None)).Count -ForegroundColor DarkMagenta

            $mc = $null # reset variable for later use, previous values are not needed anymore
            foreach ($pattern in $searchLines) {
                if (-not $r) { # Literal search, not regex: escape special characters
                    $pattern = [regex]::Escape($pattern)
                }
                $mc += [System.Text.RegularExpressions.Regex]::Matches($clipboardUnchanged, $pattern, $regexOptions)
            }
            Write-Host "You provided " -NoNewline
            Write-Host $searchLines.Count -NoNewline -ForegroundColor Yellow
            Write-Host " search pattern(s) as " -NoNewline
            if ($r) { Write-Host "regex. " -ForegroundColor Cyan -NoNewline }
                else { Write-Host "literal text. " -ForegroundColor Green -NoNewline }
            Write-Host "Your pattern(s) with your option(s) matched: " -NoNewline 
            Write-Host $mc.Count -ForegroundColor Red        
}

function invoke-Replacement() {
    param(
        [Parameter(Mandatory)]
        [string]$Text
    )
    for ($var = 0; $var -lt $Script:searchLines.Count; $var++) {  # for every entry in searchLines-array (contains search all patterns)
        $searchContent = $Script:searchLines[$var]
        $replaceContent = $Script:replaceLines[$var]

        if (-not $r) { # Literal search, not regex: escape special characters
            $searchContent = [regex]::Escape($searchContent)
        }
        try {
            $Text = [regex]::Replace($Text, $searchContent, [string]$replaceContent, $Script:regexOptions)
        }
        catch {
            Write-Warning "Skipping invalid substitution: $searchContent - $_"
            continue
        }
    }
    return [PSCustomObject]@{
        replacementResult  = $Text
    }
}


function invoke-Textfilter() {
    param(
        [Parameter(Mandatory)]
        [string]$Text,

        [Parameter(Mandatory)]
        [string[]]$searchLines

    )
    $lines = $Text -split "`n", -1
    $writeOut = New-Object System.Text.StringBuilder  # StringObject for output as textfile
    $matchCount = 0
    # $allMatches = @()
    $allMatches = [System.Collections.Generic.List[System.Text.RegularExpressions.Match]]::new()
    
    $sw = [System.Diagnostics.Stopwatch]::StartNew()  # Stopwatch for benchmarking grep time
    foreach ($pattern in $searchLines) {
        if (-not $r) { # Literal search, not regex: escape special characters
            $pattern = [regex]::Escape($pattern)
        }
        $mc = [System.Text.RegularExpressions.Regex]::Matches($Text, $pattern, $Script:regexOptions)
        foreach ($m in $mc) {
            $allMatches.Add($m)
        }
    }
    $sw.Stop()
    $grepElapsDesc = "Grepping took: $($sw.Elapsed.TotalMilliseconds) ms"

    $matchCount = $allMatches.Count  # Array count of all matches
    $allMatches = $allMatches | Sort-Object Index  # Sorting all matches by index for ordered processing
    
    if ($Script:PSBoundParameters.ContainsKey("plain") -eq $true) {
        foreach ($m in $allMatches) {
            $m.Groups[0].Value | Write-Host -ForegroundColor Red -NoNewline
            $Script:plain  | Write-Host -ForegroundColor Red -NoNewline
            if ($Script:fileOutput) {
                $null = $writeOut.Append($m.Groups[0].Value)  # Append to output string
                $null = $writeOut.Append($Script:plain)
            }
        }
    }
    else {
        foreach ($m in $allMatches) {
            $newB = $Script:B  # New name provides possibility to change value without loosing the information about lines to print my name has been good name
            $newA = $Script:A  # New name provides possibility to change value without loosing the information about lines to print
            $matchMetaData = Get-StringLineInfo -Text $Text -Position $m.Index -Length $m.Length

            Write-Host "Line " -NoNewline
            Write-Host "$($matchMetaData.StartLine)" -NoNewline -ForegroundColor Yellow
            Write-Host ", matched: `"" -NoNewline
            $actValue = $m.Groups[0].Value
            $actValue = $actValue.Replace("`r","").Replace("`n","")  # to avoid disturbed output remove crlf
            Write-Host "$actValue" -ForegroundColor Red -NoNewline
            Write-Host "`" at index " -NoNewline
            Write-Host "$($m.Index)" -ForegroundColor Cyan -NoNewline
            Write-Host " with length " -NoNewline
            Write-Host "$($m.Length)" -ForegroundColor Blue -NoNewline
            Write-Host ":"

            $addText = ""
            if ($Script:loop -gt 1 ) {
                $addText = "Run $runNr. "
            }
            if ($Script:benchmark) {
                $addText = "$addText$grepElapsDesc"
            }
            
            $null = $writeOut.AppendLine("$($addText)Line $($matchMetaData.StartLine), matched: `"$($m.Groups[0].Value)`" at index $($m.Index) with length $($m.Length):`n")  # Append to output string
            while(($matchMetaData.StartLine - $newB) -lt 1 ) {  # decrement B if out of bounds, no negative line numbers are possible
                $newB--
            }

            while(($matchMetaData.EndLine + $newA) -gt $matchMetaData.TotalLines ) {  # decrement A if out of bounds, because cannot show nonexisting line numbers
                $newA--
            }

            if($newB -gt 0) {
                $outputLines = $lines[($matchMetaData.StartLine - $newB - 1)..($matchMetaData.StartLine -1-1 )]  # Slice array to yield lines before match
                $outputLines | ForEach-Object { $null = $writeOut.AppendLine($_); Write-Host $_ }  # Append and print
            }
            $lines[($matchMetaData.StartLine-1)..($matchMetaData.EndLine-1)] | ForEach-Object { $null = $writeOut.AppendLine($_); Write-Host $_ }  # Append and print match lines
            if($newA -gt 0) {
                $outputLines = $lines[($matchMetaData.EndLine)..($matchMetaData.EndLine - 1 + $newA )]  # Slice array to yield lines after match
                $outputLines | ForEach-Object { $null = $writeOut.AppendLine($_); Write-Host $_ }  # Append and print
            }
            "-" * 50
            Write-Host ""  # empty line / CRLF
            $null = $writeOut.AppendLine("")  # empty line / CRLF # $null supresses output
        }
        if ($matchCount -eq 0) {
            Write-Host "No matches at all" -ForegroundColor Yellow
        }
        else {
            Write-Host "Count of all matches is " -NoNewline
            Write-Host " $matchCount " -ForegroundColor Green -BackgroundColor DarkRed
            Write-Host ""
            if ($Script:fileOutput) {
                write-File($writeOut.ToString())
            }
        }
        if ($Script:benchmark) {
            Write-Host $grepElapsDesc
            Write-Host ""
        }
    }
    Write-Host ""
    if (($writeOut.ToString().Length -gt 0) -and $Script:fileOutput -and ($Script:PSBoundParameters.ContainsKey("plain") -eq $true)) {
        write-File($writeOut.ToString())
    }
}

function isTextFile {
    # Copilot
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if ($scanBinary) {
        return $true
    }
    # Only consider existing files
    if (-not (Test-Path $Path -PathType Leaf)) {
        return $false
    }

    try {
        # Read only first chunk for speed (GNU grep scans first buffer)
        $fs = [System.IO.File]::OpenRead($Path)
        $buffer = New-Object byte[] 65536   # 64 KB like GNU grep
        $bytesRead = $fs.Read($buffer, 0, $buffer.Length)
        $fs.Close()
    }
    catch {
        return $false
    }

    # Scan for NUL byte (0x00)
    for ($i = 0; $i -lt $bytesRead; $i++) {
        if ($buffer[$i] -eq 0) {
            return $false  # File is binary (GNU grep logic)
        }
    }

    # No null bytes found → treat as text
    return $true
}


function Invoke-PathProcessor {
    # co-operation-ilot partly
    param (
        [Parameter(Mandatory)]
        [string[]]$Paths,
        [string[]]$searchLines,
        [switch]$callFilter
    )
    $result=""
    foreach ($p in $Paths) {
        if (-not (Test-Path $p)) {
            Write-Host "Invalid path: $p" -ForegroundColor Red
            continue
        }

        # If file
        if (Test-Path $p -PathType Leaf) {
            Write-Host "`n=== FILE: $p ===" -ForegroundColor Cyan
            
            try {
                $text = Get-Content -Path $p -Raw -ErrorAction Stop
                if($null -eq $text -or $text -eq '') {
                     Write-Host "Empty file. No matches." -ForegroundColor Yellow 
                     continue
                }
                if($callFilter) {
                    invoke-Textfilter -Text $text -searchLines $Script:searchLines
                }
                else{
                    $meta = invoke-Replacement -Text $text
                    # $result += ($meta.replacementResult -join "$Script:plain")
                    $result += $meta.replacementResult + $Script:plain
                }
            }
            catch {
                Write-Host "Skipping (not readable as text): $p" -ForegroundColor Yellow
            }

            continue
        }

        # If folder
        if (Test-Path $p -PathType Container) {

            # Only if switch -recurse is true recursion should occur
            $files = Get-ChildItem -Path $p -Recurse:$Script:recurse -File -ErrorAction SilentlyContinue
            # $files = Get-ChildItem -Path $p -File -Recurse:(!$noRecurse) -ErrorAction SilentlyContinue

            foreach ($file in $files) {

                if(isTextFile $file){
                    # Try reading file BEFORE printing filename
                    try {
                        $text = Get-Content -Path $file.FullName -Raw -ErrorAction Stop
                    }
                    catch {
                        # Not readable as text -> skip silently
                        continue
                    }

                    # Only printed if text-readable
                    Write-Host "`n=== FILE: $($file.FullName) ===" -ForegroundColor Green
                    if($text -eq '' -or $null -eq $text) { Write-Host "Empty file. No matches." -ForegroundColor Yellow } 
                    else { 
                        if($callFilter) {
                            invoke-Textfilter -Text $text -searchLines $Script:searchLines
                        }
                        else{
                            $meta = invoke-Replacement -Text $text
                            # $result += ($meta.replacementResult -join "$Script:plain")
                            $result += $meta.replacementResult + $Script:plain
                        }
                    }
                }
                else {
                    Write-Host "`n=== BINARY FILE: $($file.FullName) ===" -ForegroundColor Yellow
                }
            }
        }
    }
    $Script:clipboardText = ($result -join "$Script:plain")
}


#PROGRAM STARTS HERE (with evaluation of cli-options)

$global:ProgramTimer = [System.Diagnostics.Stopwatch]::StartNew()
if ($endless -and $fileOutput) {
        Write-Warning "Endless loop and file output shouldn't be combined, be sure you know what you're doing!"
        [void][System.Console]::ReadLine()
}
if ($revert -and ($r -or $delete)) {
    Write-Warning "Only literal replacements (no regexes or deletions) can be meaningfully reverted, be sure you know what you're doing!"
    [void][System.Console]::ReadLine()
}
# Show help text if necessary, then exit
if ( $Help.IsPresent ) {
    show-Helptext
    confirm-exit
    return 
}
if (
    -not $interactive -and
    -not $stats -and
    (-not $searchFolderPath -or $searchFolderPath.Count -eq 0) -and    # No folder         and
    (-not $searchFilePath -or $searchFilePath.Count -eq 0) -and      # No file           and
    (-not $mappingFile -or $mappingFile.Count -eq 0) -and      # No mapping file   and
    (-not $searchText -or $searchText.Count -eq 0)  # No CLI args
) {
    $interactive = $true
}


# $C is $A and $B combined, to reduce variable amount we sum them up here  # used for context w grepping
$A += $C
$B += $C
$runNr = 0
if ($A -gt 0 -or $B -gt 0) { $extractMatch = $true }
# if ($revert -or $delete) { $substitute = $true } # Revert implies substitute, because it is a special case of substitution
if ( 
    (($searchText | Where-Object { $_ -ne $null -and $_ -ne '' }) -and -not ($replaceText | Where-Object { $_ -ne $null -and $_ -ne '' }) -and -not ($substitute -or $revert -or $delete))
    )
    {
        $extractMatch = $true
    }
if ( 
    (($replaceText | Where-Object { $_ -ne $null -and $_ -ne '' }) -and ($searchText | Where-Object { $_ -ne $null -and $_ -ne '' })) -or
    $revert -or
    $delete
    ) { 
        $substitute = $true 
    } # 
if ($mappingFile -and $mappingFile.Count -gt 0) { $substitute = $true } # LazyFile implies substitute
if ($loop -lt 1) { $loop = 1 } #avoid empty endless loop in case of wrong user input
if ($ci) { $regexOptions = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase }
    else { $regexOptions = [System.Text.RegularExpressions.RegexOptions]::None }
if ($flags.Length -gt 0) { $r = $true }  # Provided flags indicate intended usage of regex
if (($PSBoundParameters.ContainsKey("fromFile") -eq $false)){ $clipboardInput = $true }
if (($PSBoundParameters.ContainsKey("fileName") -eq $true)){ $fileOutput = $true }
if (-not $interactive) {
    $regularOptions = set-RegexFlags
    $regexOptions = $regexOptions -bor $regularOptions.Options
}
do { # (Endless) loop start
    for ($forRun = 1; $forRun -lt $loop + 1; $forRun++) {
        $runNr++
        $searchLines  = @()  # initialize arrays
        $replaceLines = @()  # empty arrays
        if ($interactive) {
            $userRead = Read-Input
            $Script:flags = $userRead.Flags
            $regularOptions = set-RegexFlags

            $searchLines += $userRead.Search
            $replaceLines += $userRead.Replace
            $regexOptions = $regexOptions -bor $regularOptions.Options
            Write-Host "______________________" -ForegroundColor DarkBlue
            Write-Host ""
        }
        if ($timeout.Contains("-")) {  # Negative values will yield waiting time at program start
            wait-Timeout
        }
        
        if($clipboardInput) {
            # Read text from clipboard
            $clipboardText = Get-Clipboard -Raw
            $clipboardUnchanged = $clipboardText  # for later comparison to check whether changes were made

            if ([string]::IsNullOrWhiteSpace($clipboardText)) {   
                Write-Host "No clipboard available. Nothing to do!" -ForegroundColor Magenta
                if (-not $endless -or $loop -gt 1) {
                    return 
                }
            }
        }
        
        $expressions = get-SearchnReplaceExpressions
        $searchLines += $expressions.SearchFor
        $replaceLines += $expressions.ReplaceWith

        # Filling up entries for replacement, if too less are provided corresponding search terms will be deleted (replaced by NULL)
        while ($replaceLines.Count -lt $searchLines.Count) {  # Filling replace terms to amount of search terms (possible because replace terms are assumed empty for missing lines)
            $replaceLines += '' # because empty lines are not recognized as lines, array will be filled with empty entries here for every empty line
        }
        if ($delete) {
            $replaceLines = @()  # For deletion, replacement is not applicable, set to empty array
            foreach ($searchLine in $searchLines) {
                $replaceLines += ''
            }
        }
        if ($revert) { 
            $searchLines, $replaceLines = $replaceLines, $searchLines  # Swap search and replace lines
        }
        if ($loop -gt 1 ) {
            Write-Host "-----------------------" -ForegroundColor DarkCyan
            if($runNr -gt 1) {
                Write-Host "-----------------------" -ForegroundColor DarkCyan
            }
            Write-Host "Begin run $runNr" -BackgroundColor DarkGray -ForegroundColor DarkCyan
        }

        # Main processing: Grep / Extract matches with context
        if ( $extractMatch ) {  # test for grep flag
            if($clipboardInput) {
                invoke-Textfilter -Text $clipboardText -searchLines $searchLines
            }
            else{
                Invoke-PathProcessor -Paths $fromFile -searchLines $searchLines -callFilter 
            }
        }

        if ( $substitute ) {  # If not grepping / extracting, do search and replace
            # Check for usability of provided search/replace lines
            if ($searchLines.Count -lt $replaceLines.Count) {  # Search terms being < replace terms is impossible
                Write-Error "Error: Amount of search strings cannot be less than replace strings, check entries!"
                Write-Warning "In other words: For every replacement a position needs to be specified!"
                Read-Host -Prompt "Press enter to end program"
                return 
            }

            $sw = [System.Diagnostics.Stopwatch]::StartNew()  # Stopwatch for benchmarking substitution time
            # Main processing loop: iterate search/replace lines
            if(-not $clipboardInput) {
                 Invoke-PathProcessor -Paths $fromFile -searchLines $searchLines 
            }
            else {
                $replacementResult = invoke-Replacement -Text $clipboardText
                $clipboardText = $replacementResult.replacementResult
            }

            $sw.Stop()
            $subsElapsDesc = "Substitution took: {0:F3} ms" -f $sw.Elapsed.TotalMilliSeconds
            
            if ( [String]::CompareOrdinal($clipboardUnchanged, $clipboardText) -ne 0 ){  # Check whether Clipboardtext has changed - byte by byte comparision seems to help here - it works!
                if ($fileOutput) { # This runs if output as file is desired, therefore needs to be called at the end
                    write-File($clipboardText)
                }
                else {  # Else = no file output? -> then set clipboard content
                    if ([string]::IsNullOrEmpty($clipboardText)) {
                        $null | Set-Clipboard  # explict deletion because Set-Clipboard does not accept $null-arrays/strings
                        Write-Host 'Clipboard is empty now.' -ForegroundColor Blue
                    }
                    else {
                        Set-Clipboard -Value $clipboardText  # Modified text back to the clipboard!
                    }
                    Write-Host 'Clipboard successfully modified.' -ForegroundColor Green
                }
            }
            else {
                Write-Host 'Clipboard text has not changed.' -ForegroundColor Yellow
            }
            if ($benchmark) {
                Write-Host $subsElapsDesc
                Write-Host ""
            }
        }
        if ($stats) { show-Stats }
        if ($benchmark) {
            "Whole script took: {0:F5} s" -f $global:ProgramTimer.Elapsed.TotalSeconds
        }
        if ($loop -gt 1 ) {
            Write-Host "End run $runNr" -BackgroundColor DarkGray -ForegroundColor DarkCyan
        }
        confirm-exit
        if (-not $timeout.Contains("-")) {  # Negative values will yield waiting time at program start
            wait-Timeout
        }
    }
} until (-not $endless)

