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
    [switch]$substitute
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



function Read-Input {
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
    if (-not $extractMatch){
        if ($r) {
            Write-Host "Groups may be referenced by `$1, `$2 etc."
        }
        $replace = Read-Host "Please enter replacement text"
    }
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
        (-not $interactive)  # No interactive mode 
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
        $clipboardUnchanged = $clipboardText
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
        $searchLines = $expressions.SearchFor
        $replaceLines = $expressions.ReplaceWith
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
            Write-Warning "Working with empty search terms seems impossible!"
            if (-not $endless) {
                return 
            }
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
        if ($extractMatch) {  # test for grep flag
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

        if ($substitute -or $delete) {  # If not grepping / extracting, do search and replace
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
