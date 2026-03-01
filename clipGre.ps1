param (
    [Alias("search", "find", "findText", "st", "ft")]
    [string[]]$searchText = @(),   
    [Alias("replace", "displace", "rt")]          
    [string[]]$replaceText = @(),
    [Alias("searchFile", "sfile", "sf")]
    [string[]]$searchFilePath = @(),    
    [Alias("replaceFile", "rfile", "rf")]          
    [string[]]$replaceFilePath = @(),
    [Alias("searchFolder", "sdir", "sd")]
    [string[]]$searchFolderPath = @(),   
    [Alias("replaceFolder", "rdir", "rd")]          
    [string[]]$replaceFolderPath = @(),
    [Alias("onTheFly", "readInput", "ri", "ia")] 
    [switch]$interactive,
    [Alias("wait", "delay", "t", "sleep")] 
    [string]$timeout = "0",
    [Alias("reOptions", "regExFlags", "modifier", "ro")] 
    [string]$flags = "",
    [Alias("showHelp", "h", "hint", "usage")]          
    [switch]$Help = $false,
    [Alias("caseInsensitive", "ignoreCase", "ic", "noCase")]          
    [switch]$ci = $false,
    [Alias("toFile", "f", "save", "write")]          
    [switch]$fileOutput = $false,
    [Alias("saveAs", "o", "out")]
    [string]$fileName = "",  
    [Alias("regEx", "advanced", "regExP")]          
    [switch]$r,  
    [Alias("after")]          
    [int16]$A = 0,
    [Alias("before")]          
    [int16]$B = 0,
    [Alias("context", "combined")]          
    [int16]$C = 0,
    [Alias("verbose", "wholeTextFile", "singleFile", "w")]          
    [switch]$wholeFile = $false,  
    [Alias("termOpen", "stay", "windowPersist", "confirm", "p")]
    [switch]$persist = $false,  
    [Alias("grep", "ext", "e", "x", "extract", "g")]    
    [switch]$extractMatch,
    [Alias("d", "del", "remove")]    
    [switch]$delete,
    [Alias("forever", "relentless", "8")]    
    [switch]$endless,
    [Alias("repeat", "again", "l")]    
    [int]$loop = 1,
    [Alias("measTim", "measureTime", "mt", "bm")]    
    [switch]$benchmark = $false,
    [Alias("sub", "substitution", "s")]    
    [switch]$substitute,
    #[Alias("countMatches", "c", "matchAmount", "countRegEx")]    
    [switch]$numba
)

function wait-Timeout([int]$additionalTime = 0) {
    # accepts additional timeout, for internals requiring waiting time (e.g. help text)
    $newDelay = [math]::Abs([int]([math]::Round(([double]($timeout -replace ',','.') * 1000)))) + $additionalTime #convert , to . then from string to double multiply 1k then round and convert to int and then take abs
    if ($newDelay -ne 0){
        Start-Sleep -Milliseconds ($newDelay)
    }
}

function show-Confirmation() {
    if ($persist){
        if ($loop -gt 1 ) {
           Write-Host "Run nr. $runNr`: " -NoNewline
        }
        Write-Host "Press Enter to end run..."
        [void][System.Console]::ReadLine()
    }
}

function Get-StringLineInfo {
    param(
        [Parameter(Mandatory)]
        [string]$Text,

        [Parameter(Mandatory)]
        [int]$Position,

        [Parameter(Mandatory)]
        [int]$Length
    )

    $lineBreaks = New-Object System.Collections.Generic.List[int]

    for ($i = 0; $i -lt $Text.Length; $i++) {
        if ($Text[$i] -eq "`n") {
            $lineBreaks.Add($i)
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
        $i = 0
        while ($i -lt $k.Length) {
            if ($i -lt $k.Length - 1 -and [char]::IsSurrogatePair($k[$i], $k[$i+1])) {
                $cp = [char]::ConvertToUtf32($k[$i], $k[$i+1])
                $i += 2
            } else {
                $cp = [int][char]$k[$i]
                $i += 1
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
        $i = 0
        while ($i -lt $S.Length) {
            $ch = $S[$i]
            $code = [int]$ch

            # High surrogate range: D800–DBFF
            if ($code -ge 0xD800 -and $code -le 0xDBFF) {
                if ($i + 1 -lt $S.Length) {
                    $next = [int]$S[$i + 1]
                    # Low surrogate range: DC00–DFFF
                    if ($next -ge 0xDC00 -and $next -le 0xDFFF) {
                        # Valid surrogate pair -> one code point
                        $count += 1
                        $i += 2
                        continue
                    }
                }
                # Unpaired high surrogate -> count as one code point
                $count += 1
                $i += 1
                continue
            }

            # Low surrogate without preceding high surrogate -> count as one code point
            if ($code -ge 0xDC00 -and $code -le 0xDFFF) {
                $count += 1
                $i += 1
                continue
            }

            # BMP char -> one code point
            $count += 1
            $i += 1
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
    # # Present a clean A/B choice: "Deletion/Substitution" vs "Grep/Text search"
    $caption = 'Empty replacement string detected'
    $message = 'Do you want a deletion/substitution or a grep (text search)?'
    $choices = @(
        [System.Management.Automation.Host.ChoiceDescription]::new('&Deletion', 'Perform deletion/substitution')
        [System.Management.Automation.Host.ChoiceDescription]::new('&Grep', 'Run a grep-like text search')
    )
    $default = 1  # 0 = Substitution, 1 = Grep


    $flags = ""
    $replace = ""
    $search = ""
    if ($r) {
        if ($Script:flags -eq "") {
            $flags = Read-Host "Please enter regex flags (e.g. 'i' for ignore case, 'm' for multiline, leave empty for none) "
        } else {
            $flags = $Script:flags
        }
        $search  = Read-Host "Please enter search text (.NET flavor regex syntax allowed) "
    } else {
        $search  = Read-Host "Please enter search text"
    }
    #if (-not $extractMatch -and -not $delete) {  # Replacement only makes sense if not extracting or deleting
        if ($r) {
            Write-Host "Groups may be referenced by `$1, `$2 etc."
        }
        $replace = Read-Host "Please enter replacement text"
    if ($replace -eq "") {

        $selection = $Host.UI.PromptForChoice($caption, $message, $choices, $default)
        switch ($selection) {
            0 { $Script:delete = $true }  # 'User selected: Substitution'
            1 { $replace = $null }  # 'User selected: Grep'
        }
    }
    #}
    return [PSCustomObject]@{
        Flags  = $flags
        Search  = $search
        Replace = $replace
    }
}

function write-File([string]$content) {
  # Timestamp generation
    $nameStamp = Get-Date -Format "yyyyMMdd_HHmmss"

    if ($loop -gt 1 ) {
        $nameStamp = "$runNr-$nameStamp"
    }

    # Check, for content of $fileName = 
    if ([string]::IsNullOrWhiteSpace($fileName)) {
        # empty -> use generic name
        $fileName = "Output_$nameStamp.txt"
    } else {
        # Name provided? ok then use it!
        # $extension = [System.IO.Path]::GetExtension($fileName) 
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
        $fileName = "${baseName}_$nameStamp.txt"
    }

    # Save file = 
    $content | Out-File -FilePath $fileName -Encoding UTF8
    if ($loop -gt 1 ) {
        Write-Host "Run nr. $runNr`: " -NoNewline
    }
    Write-Output "Results saved in file: $fileName"
}

function show-Helptext() {  # self descriptive:  print help text
    Write-Host ""
    Write-Host "This PowerShell script is intended to apply basic search (and replace) actions to the content of the clipboard.  Search/Replace strings may not only be provided as named CLI arguments, [...]"
    Write-Host ""
    Write-Host "Basic example:  clipGre.ps1 -searchText 'old1' -replaceText 'newString'"
    Write-Host ""
    Write-Host "Usage:"
    Write-Host "  -sd / -searchFolderPath   Path to folder with search files as string"
    Write-Host "  -sf / -searchFilePath     Path to file with lines to search for as string"
    Write-Host "  -st / -searchText         String (or comma separated string list) to search for"
    Write-Host "and corresponding"
    Write-Host "  -rd / -replaceFolderPath  Path to folder with replace files as string"
    Write-Host "  -rf / -replaceFilePath    Path to file with replacement lines as string"
    Write-Host "  -rt / -replaceText        Replacement string (or comma separated string list)"
    Write-Host ""
    Write-Host "  -x / -grep                Search and extract patterns"
    Write-Host "  -x / -substitute                Search and replace patterns"
    Write-Host "  -A / -after               Lines of context after the match"
    Write-Host "  -B / -before              Lines of context before the match"
    Write-Host "  -C / -combined            Lines of context combined (before and after)"
    Write-Host "  -r / -RegEx               Permit use of Regular Expressions"
    Write-Host "  -ro / -flags              Pass flags to regex engine (implicitly activates regex [-r])"
    Write-Host "  -ci / -ignoreCase         Ignore case while searching"
    Write-Host "  -ia / -interactive        Queries for (single) search and replace strings interactively"
    Write-Host ""
    Write-Host "  -v / -wholeFile           Read files as whole content instead of line-by-line"
    Write-Host "  -w / -fileOutput          Write to file, not clipboard"
    Write-Host "  -o / -saveAs              Provide output filename as string (optional)"
    Write-Host ""
    Write-Host "  -p / -persist             Waiting for confirmation at the end holds open the terminal"
    Write-Host "  -t / -timeout             Waiting time in seconds before ending the program"
    Write-Host "  -8 / -endless             Repeat the process endlessly"
    Write-Host ""
}

function set-RegexFlags() {
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
 
    return [PSCustomObject]@{
        SearchFor  = $searchLinesInside
        ReplaceWith = $replaceLinesInside
    }
}




#PROGRAM STARTS HERE
$global:ProgramTimer = [System.Diagnostics.Stopwatch]::StartNew()
if ($endless -and $fileOutput) {
        Write-Warning "Endless loop and file output shouldn't be combined, be sure you know what you're doing!"
        [void][System.Console]::ReadLine()
}
# Show help text if necessary, then exit
if (
    $Help.IsPresent -or  # Help flag provided or
    (
        (-not $searchFolderPath -or $searchFolderPath.Count -eq 0) -and    # No folder         and
        (-not $searchFilePath -or $searchFilePath.Count -eq 0) -and      # No file           and
        (-not $searchText -or $searchText.Count -eq 0) -and  # No CLI args
        (-not $interactive) -and  # No interactive mode 
        (-not $numba)  #
    )
) {
    show-Helptext
    show-Confirmation
    wait-Timeout(750)
    return 
}


# $C is $A and $B combined, to reduce variable amount we sum them up here  # used for context w grepping
$A += $C
$B += $C
$runNr = 0
if($loop -lt 1){$loop = 1} #avoid empty endless loop in case of wrong user input
# $searchFiles = @()  # initialize arrays
# $replaceFiles = @()  # empty arrays



if($ci) {
    $regexOptions = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
} else {
    $regexOptions = [System.Text.RegularExpressions.RegexOptions]::None
}

if (-not $interactive) {
    $regularOptions = set-RegexFlags
    $regexOptions = $regexOptions -bor $regularOptions.Options
}

if ($flags.Length -gt 0) {  # Provided flags indicate intended usage of regex
    $r = $true
}


do { # (Endless) loop start
    for ($forRun = 1; $forRun -lt $loop + 1; $forRun++) {
        $runNr++
        $searchLines  = @()  # initialize arrays
        $replaceLines = @()  # empty arrays

        if ($interactive) {
            $userRead = Read-Input
            $regularOptions = set-RegexFlags

            $searchLines += $userRead.Search
            $replaceLines += $userRead.Replace
            $flags = $userRead.Flags
            $regexOptions = $regexOptions -bor $regularOptions.Options
        }
        if ($timeout.Contains("-")) {  # Negative values will yield waiting time at program start
            wait-Timeout
        }
        # Read text from clipboard
        $clipboardText = Get-Clipboard -Raw
        $clipboardUnchanged = $clipboardText  # for later comparison to check whether changes were made
        # Write-Host "Current regex flags: " -NoNewline
        # Write-Host $flags
        # Write-Host $regexOptions
        if ([string]::IsNullOrWhiteSpace($clipboardText)) {   
            # if ($loop -gt 1 ) {
            # Write-Host "Run nr. $runNr`: " -NoNewline
            # }
            Write-Host "No clipboard available. Nothing to do!" -ForegroundColor Magenta
            if (-not $endless) {
                return 
            }
        }
        $expressions = get-SearchnReplaceExpressions
        $searchLines += $expressions.SearchFor
        $replaceLines += $expressions.ReplaceWith
        # Write-Host "Number of search lines: $($searchLines.Count)"
        # Write-Host "Number of replace lines: $($replaceLines.Count)"
        # Filling up entries for replacement, if too less are provided corresponding search terms will be deleted (replaced by NULL)
        while ($replaceLines.Count -lt $searchLines.Count) {  # Filling replace terms to amount of search terms (possible because replace terms are assumed empty for missing lines)
            $replaceLines += '' # because empty lines are not recognized as lines, array will be filled with empty entries here for every empty line
        }
        if ($delete) {
            foreach ($searchLine in $searchLines) {
                $replaceLines = ''
            }
        }
        if(-not ($searchLines -and ($searchLines | Where-Object { -not [string]::IsNullOrWhiteSpace($_.ToString()) }))){
            Write-Warning "Working with empty search terms seems difficult!"
            Write-Host "Beware of the output!" -ForegroundColor Red
            # if (-not $endless) {
            #     return 
            # }
        }
        if ($loop -gt 1 ) {
            Write-Host "-----------" -ForegroundColor DarkCyan
            Write-Host "Begin run $runNr" -BackgroundColor DarkGray -ForegroundColor DarkCyan
        }


        # Write-Host "Search patterns to process: " -NoNewline
        # Write-Host $searchLines
        # Write-Host $searchFolderPath
        # Write-Host $searchFilePath
        # Write-Host $searchLines

        # Main processing: Grep / Extract matches with context
        if ($extractMatch -or (-not $delete -and -not ($replaceLines | Where-Object { $_ -ne $null -and $_ -ne '' }) -and ($searchLines | Where-Object { $_ -ne $null -and $_ -ne '' }))) {  # test for grep flag
            $lines = $clipboardText -split "`n", -1
            $writeOut = New-Object System.Text.StringBuilder  # StringObject for output as textfile

            $matchCount = 0
            # $allMatches = @()
            $allMatches = [System.Collections.Generic.List[System.Text.RegularExpressions.Match]]::new()

            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            foreach ($pattern in $searchLines) {
                $mc = [System.Text.RegularExpressions.Regex]::Matches($clipboardText, $pattern, $regexOptions)
                foreach ($m in $mc) {
                    $allMatches.Add($m)
                }
            }

            # foreach ($pattern in $searchLines) {
            #     $allMatches += [System.Text.RegularExpressions.Regex]::Matches($clipboardText, $pattern, $regexOptions)  # Adding all matches to one array
            # }
            $sw.Stop()
            $grepElapsDesc = "Grepping took: $($sw.Elapsed.TotalMilliseconds) ms"

            $matchCount = $allMatches.Count  # Array count of all matches
            $allMatches = $allMatches | Sort-Object Index  # Sorting all matches by index for ordered processing
            foreach ($m in $allMatches) {
                $newB = $B  # New name provides possibility to change value without loosing the information about lines to print
                $newA = $A  # New name provides possibility to change value without loosing the information about lines to print
                $matchMetaData = Get-StringLineInfo -Text $clipboardText -Position $m.Index -Length $m.Length
                # if ($loop -gt 1 ) {
                #     Write-Host "Run nr. $runNr`: " -NoNewline
                # }
                Write-Host "Line " -NoNewline
                Write-Host "$($matchMetaData.StartLine)" -NoNewline -ForegroundColor Yellow
                Write-Host ", matched: `"" -NoNewline
                $actValue = $m.Groups[0].Value
                $actValue = $actValue.Replace("`r","").Replace("`n","")
                Write-Host "$actValue" -ForegroundColor Red -NoNewline
                Write-Host "`" at index " -NoNewline
                Write-Host "$($m.Index)" -ForegroundColor Cyan -NoNewline
                Write-Host " with length " -NoNewline
                Write-Host "$($m.Length)" -ForegroundColor Blue -NoNewline
                Write-Host ":"

                $addText = ""
                if ($loop -gt 1 ) {
                    $addText = "Run $runNr. "
                }
                if ($benchmark) {
                    $addText = "$addText$grepElapsDesc"
                }
                
                # Write-Host "`" at index $($m.Index) with length $($m.Length):"      
                $null = $writeOut.AppendLine("$($addText)Line $($matchMetaData.StartLine), matched: `"$($m.Groups[0].Value)`" at index $($m.Index) with length $($m.Length):`n")  # Append to output string
                # Write-Host "newB"
                # Write-Host $newB
                # Write-Host "matchMetaData.StartLine"
                # Write-Host $matchMetaData.StartLine
                while(($matchMetaData.StartLine - $newB) -lt 1 ) {  # decrement B if out of bounds, no negative line numbers are possible
                    $newB--
                }
                # Write-Host $newB
                while(($matchMetaData.EndLine + $newA) -gt $matchMetaData.TotalLines ) {  # decrement A if out of bounds, because cannot show nonexisting line numbers
                    $newA--
                }
                #"-" * 50
                if($newB -gt 0) {
                    # Write-Host ($matchMetaData.StartLine - $newB)
                    # Write-Host ($matchMetaData.StartLine -1-1)
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
                $null = $writeOut.AppendLine("")  # empty line / CRLF
            }
            if ($matchCount -eq 0) {
                # if ($loop -gt 1 ) {
                #     Write-Host "Run nr. $runNr`: " -NoNewline
                # }
                Write-Host "No matches at all" -ForegroundColor Yellow
            }
            else {
                # if ($loop -gt 1 ) {
                #     Write-Host "Run nr. $runNr`: " -NoNewline
                # }
                Write-Host "Count of all matches is " -NoNewline
                Write-Host " $matchCount " -ForegroundColor Green -BackgroundColor DarkRed
                Write-Host ""
                if ($fileOutput) {
                    write-File($writeOut.ToString())
                }
            }
            if ($benchmark) {
                Write-Host $grepElapsDesc
                Write-Host ""
            }
        }

        if ($substitute -or $delete -or (($replaceLines | Where-Object { $_ -ne $null -and $_ -ne '' }) -and ($searchLines | Where-Object { $_ -ne $null -and $_ -ne '' }))) {  # If not grepping / extracting, do search and replace
            # Write-Host "entered replacement section"
            # "Performing search and replace..."
            # Check for usability of provided search/replace lines
            if ($searchLines.Count -lt $replaceLines.Count) {  # Search terms being < replace terms is impossible
                Write-Error "Error: Amount of search strings cannot be less than replace strings, check entries!"
                Write-Warning "In other words: For every replacement a position needs to be specified!"
                Read-Host -Prompt "Press enter to end program"
                return 
            }

            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            # Main processing loop: iterate search/replace lines
            for ($i = 0; $i -lt $searchLines.Count; $i++) {  # for every entry in searchLines-array (contains search all patterns)
                $searchContent = $searchLines[$i]
                $replaceContent = $replaceLines[$i]

                if (-not $r) { # Literal search, not regex: escape special characters
                    $searchContent = [regex]::Escape($searchContent)
                }
                try {
                    $clipboardText = [regex]::Replace($clipboardText, $searchContent, [string]$replaceContent, $regexOptions)
                }
                catch {
                    Write-Warning "Skipping invalid substitution: $searchContent - $_"
                    continue
                }
            }
            $sw.Stop()
            # $subsElapsDesc = "Substitution took: $($sw.Elapsed)"
            $subsElapsDesc = "Substitution took: {0:F3} ms" -f $sw.Elapsed.TotalMilliSeconds
            
            


            if ( [String]::CompareOrdinal($clipboardUnchanged, $clipboardText) -ne 0 ){  # Check whether Clipboardtext has changed - byte by byte comparision seems to help here - it works!
                if ($fileOutput) { # This runs if output as file is desired, therefore needs to be called at the end
                    write-File($clipboardText)
                }
                else {  # Else = no file output? -> then set clipboard content
                    if ([string]::IsNullOrEmpty($clipboardText)) {
                        $null | Set-Clipboard  # explict deletion because Set-Clipboard does not accept $null-arrays/strings
                        # if ($loop -gt 1 ) {
                        #     Write-Host "Run $runNr`: " -NoNewline
                        # }
                        Write-Host 'Clipboard is empty now.' -ForegroundColor Blue
                    }
                    else {
                        Set-Clipboard -Value $clipboardText  # Modified text back to the clipboard!
                    }
                    # if ($loop -gt 1 ) {
                    #     Write-Host "Run $runNr`: " -NoNewline
                    # }
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
        if ($numba) {
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
            
            $mc = [System.Text.RegularExpressions.Regex]::Matches($clipboardUnchanged, ".", [System.Text.RegularExpressions.RegexOptions]::Singleline)
            Write-Host "Character count (dot-matches-all, regex: `".`"): " -NoNewline 
            Write-Host $mc.Count -ForegroundColor Magenta

            
            $mc = [System.Text.RegularExpressions.Regex]::Matches($clipboardUnchanged, "\b\w+\b", [System.Text.RegularExpressions.RegexOptions]::None)
            Write-Host "Word count (no options, regex: `"\b\w+\b`"): " -NoNewline 
            Write-Host $mc.Count -ForegroundColor DarkMagenta

            #field count
            $mc = [System.Text.RegularExpressions.Regex]::Matches($clipboardUnchanged, "\s*\S+\s*", [System.Text.RegularExpressions.RegexOptions]::None)
            Write-Host "Space separated fields, like words (no options, regex: `"\s*\S+\s*`"): " -NoNewline 
            Write-Host $mc.Count -ForegroundColor Magenta

            $mc = [System.Text.RegularExpressions.Regex]::Matches($clipboardUnchanged, "^", [System.Text.RegularExpressions.RegexOptions]::Multiline)
            Write-Host "Line count (multiline, regex: `"^`"): " -NoNewline 
            Write-Host $mc.Count -ForegroundColor DarkBlue

            $mc = $null # reset variable for later use, previous values are not needed anymore
            foreach ($pattern in $searchLines) {
                $mc += [System.Text.RegularExpressions.Regex]::Matches($clipboardUnchanged, $pattern, $regexOptions)
            }
            Write-Host "You provided " -NoNewline
            Write-Host $searchLines.Count -NoNewline -ForegroundColor Yellow
            Write-Host " search pattern(s). " 
            Write-Host "Your pattern(s) with your option(s) matched: " -NoNewline 
            Write-Host $mc.Count -ForegroundColor Red            
        }

        # $searchLines  = @()  # reset arrays for case of endless loop
        # $replaceLines = @()  # empty arrays
        if ($benchmark) {
            "Whole script took: {0:F5} s" -f $global:ProgramTimer.Elapsed.TotalSeconds
        }
        if ($loop -gt 1 ) {
            Write-Host "End run $runNr" -BackgroundColor DarkGray -ForegroundColor DarkCyan
        }
        show-Confirmation
        if (-not $timeout.Contains("-")) {  # Negative values will yield waiting time at program start
            wait-Timeout
        }
    }
} until (-not $endless)


#powershell hat mir schonmal einen text ausgegeben der nicht mehr im programmcode stand, das war ein abschnittstrenner, lauter - striche
#diese wurden nachdem ich mich umentschieden habe und es aus dem code entfernt habe noch immer ausgeführt an
#der stelle im code wo sie vorher standen. ich wurde verrückt weil ich nicht wusste warum
#neustart von powershell und schwupps wieder alles gut
#heute dann hat nichts mehr gematched - es gab nur noch "fullmatches" (also ^match$) oder gar keine. wieder rätselhaft
#powershell neu gestartet dann wars problem behoben!!! 
#really strange behaviour!
