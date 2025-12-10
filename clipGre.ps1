param (
    [Alias("folder1", "searchFolder")]
    [string]$searchFolderPath = "",   
    [Alias("folder2", "replaceFolder")]          
    [string]$replaceFolderPath = "",
    [Alias("file1", "searchFile")]
    [string]$searchFilePath = "",    
    [Alias("file2", "replaceFile")]          
    [string]$replaceFilePath = "",
    [Alias("text1", "search", "find", "findText", "searchFor")]
    [string[]]$searchText,   
    [Alias("text2", "replace", "displace", "substitute", "replaceBy")]          
    [string[]]$replaceText,
    [Alias("onTheFly", "readInput", "ri", "interactiveMode", "im", "ia", "inputAsk")] 
    [switch]$interactive,
    [Alias("wait", "delay", "seconds", "time", "t" , "z")] 
    [string]$timeout = "0",
    [Alias("showHelp", "h", "hint", "usage")]          
    [switch]$Help = $false,
    [Alias("caseInsensitive", "caseMattersNot", "ignoreCase", "ic", "noCase")]          
    [switch]$ci = $false,
    [Alias("toFile", "f", "save", "write", "w", "fileOut", "toOutput")]          
    [switch]$fileOutput = $false,
    [Alias("outputName", "saveFileName", "outName", "saveAs", "o", "out", "output")]
    [string]$fileName = "",  
    [Alias("standard", "s", "normal", "n", "default", "d")]          
    [switch]$standardSettings,  
    [Alias("regularExpressions", "regEx", "advanced", "regExP")]          
    [switch]$r,  
    [Alias("termOpen", "stay", "windowPersist", "confirm", "p", "c")]          
    [switch]$persist = $false,  
    [Alias("grep", "ext", "e", "x", "extract", "g")]    
    [switch]$extractMatch,
    [Alias("forever", "repeat", "nonstop", "8", "loop", "relentless")]    
    [switch]$endless,
    [Alias("repeatDelay", "repeatTimeout", "loopTimeout", "loopWait", "loopSleep", "ld")]    
    [string]$loopDelay
)


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
        Write-Error "Neither the required files nor the required folders exist. Please check the paths."
        exit
    }
}

function show-Helptext() {  # self descriptive: print help text
    Write-Host ""
    Write-Host "This PowerShell script is intended to apply basic search (and replace) actions to the content of the clipboard. Search/Replace strings may not only be provided as named CLI arguments, but also in the form of lists as predefined files/folders with suitable content."
    Write-Host ""
    Write-Host "Basic example: clipGre.ps1 -searchText 'old1' -replaceText 'newString'"
    Write-Host ""
    Write-Host "Usage:"
    Write-Host "  -searchFolderPath         Path to folder with search files as string"
    Write-Host "  -searchFilePath           Path to file with lines to search for as string"
    Write-Host "  -searchText / -find       String (or comma separated string list) to search for"
    Write-Host "and corresponding"
    Write-Host "  -replaceFolderPath        Path to folder with replace files as string"
    Write-Host "  -replaceFilePath          Path to file with replacement lines as string"
    Write-Host "  -replaceText / -replace   Replacement string (or comma separated string list)"
    Write-Host "or"
    Write-Host "  -s / -standardSettings    Loads the standard folder or file names SEARCH/REPLACE or SEARCH/REPLACE.txt"
    Write-Host "further options"
    Write-Host "  -r / -RegEx               Permit use of Regular Expressions"
    Write-Host "  -x / -grep                Search and extract patterns"
    Write-Host "  -i / -ignoreCase          Ignore case while searching"
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


#PROGRAM STARTS HERE

if ($timeout.Contains("-")) {  # Negative values will yield waiting time at program start
    wait-Timeout
    $timeout = "0"
}

# Apply standard settings if user wishes to do so
if ($standardSettings) {
    set-Standard
}

# Show help text if desired, then exit
if (
    $Help.IsPresent -or  # Help flag provided or
    (
        ($searchFolderPath.Trim().Length -eq 0) -and    # No folder         or
        ($searchFilePath.Trim().Length -eq 0) -and      # No file           or
        (-not $searchText -or $searchText.Count -eq 0) -and
        (-not $interactive) 
        #($searchText.Trim().Length -eq 0)               # No search text    provided
    )
) {
    show-Helptext
    check-Confirmation
    wait-Timeout(750)
    # Read-Host -Prompt "Press Enter to end program!"
    exit
}

$searchLines  = @()  # empty arrays
$replaceLines = @()  # initialize arrays

if ($interactive) {
    $userRead = Read-Input
    $searchLines += $userRead.Search
    $replaceLines += $userRead.Replace
}

do { # (Endless) loop start
    
# Read text from clipboard
$clipboardText = Get-Clipboard -Raw
$clipboardUnchanged = $clipboardText

if ([string]::IsNullOrWhiteSpace($clipboardText)) {
    Write-Output "No clipboard available. Nothing to do!"
    exit
}

# Read file contents explicitly as arrays, but only if they exist
if (-not [string]::IsNullOrWhiteSpace($searchFilePath)) {
    $searchLines = @(Get-Content -Path $searchFilePath)
}
if ($searchText -or $searchText.Count -gt 0) {
    $searchLines += $searchText  # So that $searchLines will be an array
}
# if (-not [string]::IsNullOrWhiteSpace($searchText)) { #saved for later
#     $searchLines += ,$searchText  # So that $searchLines will be an array
# }


# if (-not [string]::IsNullOrWhiteSpace($extractMatch)) {
#     $searchLines += ,$extractMatch  # So that $searchLines will be an array
# }
if (-not [string]::IsNullOrWhiteSpace($replaceFilePath)) {
    $replaceLines = @(Get-Content -Path $replaceFilePath)  # Urgent need of arrays: @( )
}
if ($replaceText -or $replaceText.Count -gt 0) {
    $replaceLines += $replaceText
}
# if (-not [string]::IsNullOrWhiteSpace($replaceText)) { #saved for later
#     $replaceLines += ,$replaceText
# }

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
            if ($ci) {
                if ($r) {
                    # Regex-search (case-insensitive)
                    foreach ($m in [regex]::Matches($line, $pattern, $opt)) {
                        Write-Host "${lineNumber}: " -NoNewline -ForegroundColor Yellow
                        Write-Host "$($m.Value)"  -ForegroundColor Red  # Match 
                        Write-Host "${lineNumber}:" -NoNewline -ForegroundColor Yellow
                        Write-Host "$line"        # Full line
                        Write-Host ""                            # empty line/CRLF
                        $null = $textOut.AppendLine("${lineNumber}: $($m.Value)")  # do not output to console but to $null
                        $null = $textOut.AppendLine("${lineNumber}: $line")  # do not output to console but to $null
                        $null = $textOut.AppendLine("")  # empty line/CRLF 
                        $matchCount++
                    }
                } else {
                    # Literal search (case-insensitive)
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
            else {
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
    check-Confirmation
    wait-Timeout
    exit
}
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


#searchAndReplace part by part
if ($null -ne $replaceLines -and $replaceLines.Count -gt 0 -and $null -ne $searchLines -and $searchLines.Count -gt 0) {  # Only runs if search/replaceLines-Array is existing and has content
    if ($r) {
        for ($i = 0; $i -lt $searchLines.Count; $i++) {
            $searchString = $searchLines[$i]
            $replaceString = $replaceLines[$i]
            if ($replaceString -eq '') {
                # Delete $searchString from $clipboardText
                if ($ci) {
                    $clipboardText = $clipboardText -replace $searchString, ''
                }
                else {
                    $clipboardText = $clipboardText -creplace $searchString, ''
                }
            } else {
                if ($ci) {
                    # Replace $searchString by $replaceString
                    $clipboardText = $clipboardText -replace $searchString, $replaceString
                }
                else {
                    $clipboardText = $clipboardText -creplace $searchString, $replaceString
                }
            }
}
    }
    else {
        for ($i = 0; $i -lt $searchLines.Count; $i++) {
            $searchString = $searchLines[$i]
            $replaceString = $replaceLines[$i]
            if ($replaceString -eq '') {
                if ($ci) {
                    $clipboardText = $clipboardText -replace [regex]::Escape($searchString), ''
                    #$clipboardText = $clipboardText.Replace($searchString, '')
                }
                else {
                    # #$clipboardText = $clipboardText.Replace($searchString, '', [System.StringComparison]::Ordinal) # Not working, meethod is not overloaded
                    $clipboardText = $clipboardText.Replace($searchString, '')
                }
            } else {
                if ($ci) {
                    $clipboardText = $clipboardText -replace [regex]::Escape($searchString), $replaceString
                    #$clipboardText = $clipboardText.Replace($searchString, $replaceString)
                }
                else {
                #  #$clipboardText = $clipboardText.Replace($searchString, $replaceString, [System.StringComparison]::Ordinal) # Not working, meethod is not overloaded
                $clipboardText = $clipboardText.Replace($searchString, $replaceString)
                }
            }
        }
    }
}

#Search and replace folderwise
if (-not [string]::IsNullOrWhiteSpace($searchFolderPath)) {
    if (-not (check-folder -Path $searchFolderPath -Strict)) {
        Write-Host "Folder check failed, path non-existent or files empty"
    }
    else {
        #"Folder check successfull"
    }
    if (-not (check-folder -Path $replaceFolderPath)) {
        Write-Host "Folder check failed, path non-existent"
    }
    else {
        #"Folder check successfull"
    }
}

$searchFiles = Get-ChildItem -Path $searchFolderPath -Filter *.txt | Sort-Object Name
$replaceFiles = Get-ChildItem -Path $replaceFolderPath -Filter *.txt | Sort-Object Name


# Check if the number of files in both folders matches
if ($searchFiles.Count -ne $replaceFiles.Count) {
    Write-Host "The number of .txt-files in the SEARCH and REPLACE folders does not match."
    Write-Host "Exiting..."
    exit
}
for ($i = 0; $i -lt $searchFiles.Count; $i++) {
    # Read file contents
    $searchContent = Get-Content -Path $searchFiles[$i].FullName -Raw
    $replaceContent = Get-Content -Path $replaceFiles[$i].FullName -Raw
    if ($null -eq $replaceContent) {
        $replaceContent = ''
    }
    if ($ci) { 
        if ($r) {
                $searchContent = $searchContent
        }
        else {
            $searchContent = '(?i)' + [regex]::Escape($searchContent)
        }
    }
    else{
        if ($r) {
            $searchContent = $searchContent
        }
        else {
            $searchContent = [regex]::Escape($searchContent)
        }
    }
    # Ersetze den Inhalt in der clipboardText (case-sensitive)
    #$clipboardText = [regex]::Replace($clipboardText, [regex]::Escape($searchContent), $replaceContent)
    try {
        $clipboardText = [regex]::Replace($clipboardText, $searchContent, $replaceContent)
    }
    catch {
        Write-Warning "Skipping invalid regex: $pattern - $_"
        continue
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

$searchLines  = @()  # empty arrays for case of endless loop
$replaceLines = @()  # empty arrays

wait-Timeout(([int]([math]::Round(([double]($loopDelay -replace ',','.') * 1000)))))  # convert to ms
} until (-not $endless)


check-Confirmation
wait-Timeout
