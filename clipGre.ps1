param (
    [Alias("folder1", "searchFolder", "sdir", "sd")]
    [string[]]$searchFolderPath = "",   
    [Alias("folder2", "replaceFolder", "rdir", "rd")]          
    [string[]]$replaceFolderPath = "",
    [Alias("file1", "searchFile", "sfile", "sf")]
    [string[]]$searchFilePath = "",    
    [Alias("file2", "replaceFile", "rfile", "rf")]          
    [string[]]$replaceFilePath = "",
    [Alias("text1", "search", "find", "findText", "searchFor", "st", "ft")]
    [string[]]$searchText,   
    [Alias("text2", "replace", "displace", "substitute", "replaceBy", "rt", "subt")]          
    [string[]]$replaceText,
    [Alias("onTheFly", "readInput", "ri", "interactiveMode", "im", "ia", "inputAsk")] 
    [switch]$interactive,
    [Alias("wait", "delay", "seconds", "time", "t" , "z")] 
    [string]$timeout = "0",
    [Alias("regExOptions", "regExFlags", "modifier")] 
    [string]$flags = "",
    [Alias("showHelp", "h", "hint", "usage")]          
    [switch]$Help = $false,
    [Alias("caseInsensitive", "caseMattersNot", "ignoreCase", "ic", "noCase")]          
    [switch]$ci = $false,
    [Alias("toFile", "f", "save", "write", "w", "fileOut", "toOutput")]          
    [switch]$fileOutput = $false,
    [Alias("outputName", "saveFileName", "outName", "saveAs", "o", "out", "output")]
    [string]$fileName = "",  
    [Alias("regularExpressions", "regEx", "advanced", "regExP")]          
    [switch]$r,  
    [Alias("after")]          
    [int16]$A = 0,
    [Alias("before")]          
    [int16]$B = 0,
    [Alias("context", "combined")]          
    [int16]$C = 0,
    [Alias("verbose", "wholeTextFile", "singleFile", "v")]          
    [switch]$wholeFile = $false,  
    [Alias("termOpen", "stay", "windowPersist", "confirm", "p")]
    [switch]$persist = $false,  
    [Alias("grep", "ext", "e", "x", "extract", "g")]    
    [switch]$extractMatch,
    [Alias("forever", "repeat", "nonstop", "8", "loop", "relentless")]    
    [switch]$endless
)

# Write-Host "pre-all: searchLines:"
# Write-Host $searchLines
# Write-Host "replaceLines:"
# Write-Host $replaceLines
# Write-Host "end"

function Show-CharDebug {
    param(
        [Parameter(Mandatory)]
        [Object]$InputData
    )

    # Falls Input ein Array ist, alle Elemente in einen String zusammenführen
    if ($InputData -is [System.Array]) {
        $InputData = -join $InputData
    }

    for ($i = 0; $i -lt $InputData.Length; $i++) {
        $char = $InputData[$i]

        switch ($char) {
            "`r" { Write-Host "`r (CR)" -ForegroundColor Cyan  -NoNewline}
            "`n" { Write-Host "`n (LF)" -ForegroundColor Cyan  -NoNewline}
            "`t" { Write-Host "`t (TAB)" -ForegroundColor Yellow  -NoNewline}
            default { Write-Host $char -NoNewline }
        }
    }
}
#Write-Host "Pipeline input present:" ($input.Count)
# Write-Host "pre-all: begin show-CharDebug"
# Show-CharDebug $searchText
# Write-Host ""
# Show-CharDebug $replaceText
# Write-Host ""
# Write-Host "end show-CharDebug"
# Write-Host "DEBUG searchFilePath = '[$searchFilePath]'"
# Write-Host "IsNullOrWhiteSpace = $([string]::IsNullOrWhiteSpace($searchFilePath))"
function wait-Timeout([int]$additionalTime = 0) {
    # accepts additional timeout, for internals requiring waiting time (e.g. help text)
    $newDelay = [math]::Abs([int]([math]::Round(([double]($timeout -replace ',','.') * 1000)))) + $additionalTime #convert , to . then from string to double multiply 1k then round and convert to int and then take abs
    if ($newDelay -ne 0){
        Start-Sleep -Milliseconds ($newDelay)
    }
}

function check-Confirmation() {
    if ($persist){
        Write-Host "Press Enter to exit..."
        [void][System.Console]::ReadLine()
    }
}

function Read-Input {
    $search  = Read-Host "Please enter search text"
    if(-not $extractMatch){
        $replace = Read-Host "Please enter replacement text"
    }
    return [PSCustomObject]@{
        Search  = $search
        Replace = $replace
    }
}

function writeFile([string]$content) {
  # Timestamp generation
    $timeStamp = Get-Date -Format "yyyyMMdd_HHmmss"

    # Check, for content of $fileName
    if ([string]::IsNullOrWhiteSpace($fileName)) {
        # empty -> use generic name
        $fileName = "Output_$timeStamp.txt"
    } else {
        # Name provided? ok then use it!
        $extension = [System.IO.Path]::GetExtension($fileName)
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
        $fileName = "${baseName}_$timeStamp$extension"
    }

    # Save file
    $content | Out-File -FilePath $fileName -Encoding UTF8
    Write-Output "Results saved in file: $fileName"
}


function set-Standard() {  # Set standard preferences (file/folder names) if applicable (dependant of existence)
    # Standard paths
    $searchFile = ".\SEARCH.txt"
    $replaceFile = ".\REPLACE.txt"
    $searchFolder = ".\SEARCH\"
    $replaceFolder = ".\REPLACE\"
    $script:ci = $true  # Standard settings include case-insensitivity
    $script:timeout = "1.5"  # Standard settings include a short timeout

    # Check existence
    $filesExist = (Test-Path $searchFile -PathType Leaf) -and (Test-Path $replaceFile -PathType Leaf)
    $foldersExist = (Test-Path $searchFolder -PathType Container) -and (Test-Path $replaceFolder -PathType Container)

    # Conditional assignment
    if ($filesExist) {
        $script:searchFilePath = $searchFile
        $script:replaceFilePath = $replaceFile
        Write-Host "File for search patterns is $searchFilePath"
        Write-Host "File for replacement patterns is $replaceFilePath"
    }
    if ($foldersExist) {
        $script:searchFolderPath = $searchFolder
        $script:replaceFolderPath = $replaceFolder
        Write-Host "Folder for search patterns is $searchFolderPath"
        Write-Host "Folder for replacement patterns is $replaceFolderPath"
    }
    if (!($filesExist) -and -Not($foldersExist)) {
        Write-Host "No standard files or folders found, proceeding without them."
    }
}

function show-Helptext() {  # self descriptive: print help text
    Write-Host ""
    Write-Host "This PowerShell script is intended to apply basic search (and replace) actions to the content of the clipboard. Search/Replace strings may not only be provided as named CLI arguments, but also in the form of lists as predefined files/folders with suitable content."
    Write-Host ""
    Write-Host "Basic example: clipGre.ps1 -searchText 'old1' -replaceText 'newString'"
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
    Write-Host "  -r / -RegEx               Permit use of Regular Expressions"
    Write-Host "  -ci / -ignoreCase         Ignore case while searching"
    Write-Host "  -ia / -interactive        Queries for (single) search and replace strings interactively"
    Write-Host ""
    Write-Host "  -w / -fileOutput          Write to file, not clipboard"
    Write-Host "  -o / -saveAs              Provide output filename as string (optional)"
    Write-Host ""
    Write-Host "  -p / -persist             Waiting for confirmation at the end holds open the terminal"
    Write-Host "  -t / -timeout             Waiting time in seconds before ending the program"
    Write-Host "  -8 / -endless             Repeat the process endlessly"
    Write-Host "  -ld / -loopDelay          Delay between endless-loops in seconds (only with -endless)"
    Write-Host ""
}

function check-Folder {  # Function to check for existence of folder and for files bearing content
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [switch]$Strict
    )
    # Check whether path is a folder
    if (-not (Test-Path $Path -PathType Container)) {
        return $false
    }

    # To accept relative or absolute paths
    $fullPath = Convert-Path $Path
    # Call top layer of files
    try {
        $files = Get-ChildItem -Path $fullPath -File -Filter *.txt
    }
    catch {
        return $false
    }
    
    # Check for files
    if ($files.Count -eq 0) {
        return $false
    }
    if ($Strict) {
        # Check for file content (size > 0)
        foreach ($file in $files) {
            if ($file.Length -eq 0) {
                return $false
            }
        }
    }
    return $true
}

# $C is $A and $B combined, to reduce variable amount we sum them up here
$A += $C
$B += $C

#PROGRAM STARTS HERE



# Show help text if necessary, then exit
if (
    $Help.IsPresent -or  # Help flag provided or
    (
        ($searchFolderPath.Trim().Length -eq 0) -and    # No folder         and
        ($searchFilePath.Trim().Length -eq 0) -and      # No file           and
        (-not $searchText -or $searchText.Count -eq 0) -and  # No CLI args
        (-not $interactive)  # No interactive mode 
    )
) {
    show-Helptext
    check-Confirmation
    wait-Timeout(750)
    exit
}

$searchFiles = @()  # initialize arrays
$replaceFiles = @()  # empty arrays

$searchLines  = @()  # initialize arrays
$replaceLines = @()  # empty arrays

$regexOptions = [System.Text.RegularExpressions.RegexOptions]::None

foreach ($char in $flags.ToCharArray()) {
    switch ($char) {
        'i' { $regexOptions = $regexOptions -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase }
        'm' { $regexOptions = $regexOptions -bor [System.Text.RegularExpressions.RegexOptions]::Multiline }
        's' { $regexOptions = $regexOptions -bor [System.Text.RegularExpressions.RegexOptions]::Singleline }
        'x' { $regexOptions = $regexOptions -bor [System.Text.RegularExpressions.RegexOptions]::IgnorePatternWhitespace }

        # Fantasie-Modifier
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

do { # (Endless) loop start

if ($timeout.Contains("-")) {  # Negative values will yield waiting time at program start
    wait-Timeout
}

if ($interactive) {
    $userRead = Read-Input
    $searchLines += $userRead.Search
    $replaceLines += $userRead.Replace
}    
# Read text from clipboard
$clipboardText = Get-Clipboard -Raw
$clipboardUnchanged = $clipboardText

if ([string]::IsNullOrWhiteSpace($clipboardText)) {
    Write-Output "No clipboard available. Nothing to do!"
    if (-not $endless) {
        exit
    }
}
# Add the provided search/replace text from CLI arguments to searcharray
if ($searchText | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) {
    $searchLines += $searchText  # add cli args to array
}
if ($replaceText | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) {
    $replaceLines += $replaceText
}

# Get list of text files from each provided folder path
$searchFolderPath = $searchFolderPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }  # Filter empty entries,
foreach ($folder in $searchFolderPath) {
    if (Test-Path -Path $folder) {
        $searchFiles += Get-ChildItem -Path $folder -Filter *.txt -File | Sort-Object Name
        # Add text files to the list
    }
}
$replaceFolderPath = $replaceFolderPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } # Filter empty entries,
foreach ($folder in $replaceFolderPath) {
    if (Test-Path -Path $folder) {
        $replaceFiles += Get-ChildItem -Path $folder -Filter *.txt -File | Sort-Object Name
        # Add text files to the list
    }
}

$searchFilePath = $searchFilePath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } # For case of wrong user input,
$replaceFilePath = $replaceFilePath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } # For case of wrong user input,

$searchFilePath += $searchFiles.FullName  # Append found files from folders to file path arrays
$replaceFilePath += $replaceFiles.FullName  # Append found files from folders to file

if ($wholeFile) {  # Read as whole files or linewise
    foreach ($file in $searchFilePath) {
        if (Test-Path -Path $file -PathType Leaf) {
            # Read file contents and append to search/replace arrays
            $searchContent = Get-Content -Path $file -Raw
            $searchLines  += $searchContent  # Whole file as one entry
        }
    }
    foreach ($file in $replaceFilePath) {
        if (Test-Path -Path $file -PathType Leaf) {
            # Read file contents and append to search/replace arrays
            $replaceContent = Get-Content -Path $file -Raw
            if ($null -eq $replaceContent) {
                $replaceContent = ''
            }
            $replaceLines += $replaceContent  # Whole file as one entry
        }
    }
} else {  # Linewise reading
    foreach ($file in $replaceFilePath) {
        if (Test-Path -Path $file -PathType Leaf) {
            $replaceLines += @(Get-Content -Path $file)  # Urgent need of arrays: @( )
        }
    }
    foreach ($file in $searchFilePath) {
        if (Test-Path -Path $file -PathType Leaf) {
            $searchLines += @(Get-Content -Path $file) 
        }
    }
# Read file contents (lines) explicitly as arrays, but only if they exist
}


# Process the grepping functionality: extracting matches
if ($extractMatch) { 
    $opt =  if ($ci) {
                [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
            } else {
                [System.Text.RegularExpressions.RegexOptions]::None
            }
    # Match extraction: extract matches
    #### Printing line nr of match, match itself, CRLF, full line, CRLF ###
    # Define search string as empty variable
    $textOut = New-Object System.Text.StringBuilder
    $matchCount = 0
    $pattern = ""
    # Text splitting to lines
    $lines = $clipboardText -split "`r?`n"
    for ($j = 0; $j -lt $searchLines.Count; $j++) {
        $pattern = $searchLines[$j]
        $escpattern = [regex]::Escape($pattern)
        # Iterate lines
        #$escpattern = [regex]::Escape($pattern)
        # Iterate lines
        for ($i = 0; $i -lt $lines.Length; $i++) {
            $lineNumber = $i + 1
            $line = $lines[$i]
            if ($r) {
                # Regex-search (case-sensitive)
                foreach ($m in [regex]::Matches($line, $pattern, $opt)) {
                    Write-Host "${lineNumber}: " -NoNewline -ForegroundColor Yellow
                    Write-Host "$($m.Value)"  -ForegroundColor Red  # Match 
                    Write-Host "${lineNumber}:" -NoNewline -ForegroundColor Yellow
                    Write-Host "$line"        # Full line
                    Write-Host ""                            # empty line/CRLF
                    $null = $textOut.AppendLine("${lineNumber}: $($m.Value)") #  do not output to console but to $null
                    $null = $textOut.AppendLine("${lineNumber}: $line") #  do not output to console but to $null
                    $null = $textOut.AppendLine("")  # empty line/CRLF 
                    $matchCount++
                }
            } else {
                # Literal search (case-sensitive)
                foreach ($m in [regex]::Matches($line, $escpattern, $opt)) {
                    Write-Host "${lineNumber}: " -NoNewline -ForegroundColor Yellow
                    Write-Host "$($m.Value)"  -ForegroundColor Red  # Match 
                    Write-Host "${lineNumber}:" -NoNewline -ForegroundColor Yellow
                    Write-Host "$line"        # Full line
                    Write-Host ""                            # empty line/CRLF
                    $null = $textOut.AppendLine("${lineNumber}: $($m.Value)")  # do not output to console but to $null
                    $null = $textOut.AppendLine("${lineNumber}: $line") #  do not output to console but to $null
                    $null = $textOut.AppendLine("")  # empty line/CRLF 
                    $matchCount++
                }
            }
        }
    }
    if ($matchCount -eq 0) {
        Write-Output "No matches at all"
    }
    else {
        Write-Host "Count of all matches is " -NoNewline
        Write-Host " $matchCount " -ForegroundColor Green -BackgroundColor DarkRed
        if ($fileOutput) {
            writeFile($textOut.ToString())
        }
    }
} else {
    # "Performing search and replace..."
    # "Performing search and replace..."
    # "Performing search and replace..."



# Check for usability of provided search/replace lines
if ($searchLines.Count -lt $replaceLines.Count) {  # Search terms being < replace terms is impossible
    Write-Error "Error: Line count of provided files not usable, check entries!"
    Read-Host -Prompt "Press enter to end program"
    exit
}

 # Filling up entries for replacement, if too less are provided they are assumed to be vanished (replaced by NULL)
if (-not [string]::IsNullOrWhiteSpace($searchFilePath) -and
    -not [string]::IsNullOrWhiteSpace($replaceFilePath)  # Both need to exist
    ) {
    while ($replaceLines.Count -lt $searchLines.Count) {  # Filling replace terms to amount of search terms (possible because replace terms are assumed empty for missing lines)
        $replaceLines += '' # because empty lines are not recognized as lines, array will be filled with empty entries here for every empty line
    }
}
else {
    #$searchLines = @($searchText)
}

# Main processing loop: iterate search/replace lines
if ($null -ne $replaceLines -and $replaceLines.Count -gt 0 -and $null -ne $searchLines -and $searchLines.Count -gt 0) {  # Only runs if search/replaceLines-Array is existing and has content
    for ($i = 0; $i -lt $searchLines.Count; $i++) {
        $searchContent = $searchLines[$i]
        $replaceContent = $replaceLines[$i]
        # rest'd be obsolete
        if ($ci) { 
            if ($r) {
                    $searchContent = '(?i)' + $searchContent
            }
            else {
                $searchContent = '(?i)' + [regex]::Escape($searchContent)
            }
        }
        else{
            if ($r) {
                $searchContent =  $searchContent
            }
            else {
                $searchContent = [regex]::Escape($searchContent)
            }
        }
        try {
            #$regex = [regex]::new($searchContent)
            #$clipboardText = $regex.Replace($clipboardText, $replaceContent)
            $clipboardText = [regex]::Replace($clipboardText, $searchContent, $replaceContent, $regexOptions)
        }
        catch {
            Write-Warning "Skipping invalid regex: $pattern - $_"
            continue
        }
        
    }
}


if ( [String]::CompareOrdinal($clipboardUnchanged, $clipboardText) -ne 0 ){ #byte by byte comparision seems to help here - it works!
    if ($fileOutput) { # This runs if output as file is desired, therefore needs to be called at the end
        writeFile($clipboardText)
    }
    else {  # Else = no file output? -> then set clipboard content
        if ([string]::IsNullOrEmpty($clipboardText)) {
            $null | Set-Clipboard  # explict deletion because Set-Clipboard does not accept $null-arrays/strings
        }
        else {
            Set-Clipboard -Value $clipboardText
        }
        Write-Host 'Clipboard successfully modified.'
    }
}
else {
    Write-Host 'Clipboard text has not changed.'
}
}
$searchLines  = @()  # empty arrays for case of endless loop
$replaceLines = @()  # empty arrays

check-Confirmation
if (-not $timeout.Contains("-")) {  # Negative values will yield waiting time at program start
    wait-Timeout
}
# wait-Timeout(([int]([math]::Round(([double]($loopDelay -replace ',','.') * 1000)))))  # convert to ms
} until (-not $endless)
