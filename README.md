# clipGreps: Clipboard Textfilter and Substitutions
## clipGre.ps1

A lightweight PowerShell script for **filter** or **search & replace operations** directly on your **clipboard content**.  
Resembles GNU *sed* and *grep*; textfilter as well as search and replace operations can also be applied to **files**.

Compatible with PowerShell 5.1+

---

## Basic Features
These are the core, productive features:

- Supports **inline strings** (`-search foo`, `-replace bar`) or **text files** (see below) as search/replace ammo  
  - Reads your clipboard, modifies it and puts changes back into the clipboard
- Includes a **grep-like search** mode (`-search <pattern>`) for quick text filtering 🔍  
  - Displays: literal match, full line (+ optional context) containing the match, the line number and overall match count
- Optional **RegEx** mode (`-r`) and **case-insensitive mode** (`-i`)  
- Can also be applied to **files or folders** (`-files "C:\path\to"`), optionally 
  - recursively (`-recurse`)
  - on binary files (`-IncludeBinary`)



---
### Basic Examples  
Below are simple examples demonstrating the essential functionality of the script:

```powershell
# Basic text filter, literal text (standard target: clipbaord)
clipGre.ps1 'eggsample'

# Basic search & replace (standard target: clipbaord)
clipGre.ps1 'eggsample' 'example'

# Apply textfilter to folder and sub-folder content, recursively, case-insensitive
clipGre.ps1 'glasses' -Path 'c:\path\to\folder' -Recurse -i

# Regex search for text and print context lines before (2) and after (1) the match
clipGre.ps1 -r -B 2 -A 1 'c.t\.' 

```

##  GUI Tip: Run via Keyboard Shortcut (Windows)

For quick access - without having to use the command line, it's highly recommended to run the script via a **custom keyboard shortcut** in Windows.  
You can achieve this easily using a **desktop shortcut** that launches PowerShell with the correct arguments.

###  Setup Steps

1. **Create a Shortcut**
   - Right-click on your desktop → **New → Shortcut**  
   - For the location, enter something like:
     ```powershell
     powershell.exe -ExecutionPolicy Bypass -File "C:\Path\To\clipGre.ps1" -i -r -search 'foo.bar' -replace 'baz'
     ```
     >  `-ExecutionPolicy Bypass` ensures the script runs without restrictions, even if PowerShell’s default policy is limited.

2. **Assign a Keyboard Shortcut**
   - Right-click the newly created shortcut → **Properties**
   - In the **Shortcut** tab, click inside the *Shortcut key* field and press your desired key combo (e.g. `Ctrl + Alt + R`)
   - Click **Apply** or **OK**

3. **Use It**
   - Now you can simply press your shortcut to run `clipGre.ps1` instantly — perfect for quick routine clipboard transformations or grep-style searches on the fly.
   
**Pro Tip:**
For this workflow, it’s handy to use the `-interactive` option. If you additionally specify all other desired options directly in the shortcut, the interactive mode will only prompt you for the search string and/or the replacement string. This keeps the usage fast and flexible while avoiding repetitive typing.

## CLI Tip: Run from Anywhere via PATH (Windows)

To call the script from **any directory**, add its location to your user `PATH` using PowerShell only.

### Setup Steps

1. **Move the Script**
   - Place `clipGre.ps1` in a stable directory, e.g.:
     ```
     C:\Tools\clipGreps\
     ```

2. **Add Directory to PATH (PowerShell One-Liner)**
   ```
   $p='C:\Tools\clipGreps';[Environment]::SetEnvironmentVariable('Path',[Environment]::GetEnvironmentVariable('Path','User')+';'+$p,'User')
   ```

3. **Make the new PATH available immediately or restart the terminal**
   ```
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'User') + ';' + [Environment]::GetEnvironmentVariable('Path', 'Machine')
   ```
4. **Use It**
   ```
   clipGre.ps1 -search 'foo' -replace 'bar'
   ```


---


## All Features Explained (incl. Advanced / Implicit Behaviour)

Below is a complete overview of all functional capabilities. Several options interact with each other and may implicitly activate related features. All options are **optional**, and the script attempts to **infer intent automatically**, but does not necessarily hinder you from attempting impossible operations ;-)

Run `clipGre.ps1 -h` for a compact overview in the terminal.

---

### Search & Replace Inputs

- **Inline search strings** (`-Search <STRING[]>`)
  - First positional argument, the option name may be omitted
  - Single string or array, e.g. `-Search "foo","bar","baz"`

- **Inline replacement strings** (`-Replace <STRING[]>`)
  - Second positional argument, the option name may be omitted
  - Single string or array, e.g. `-Replace "one","two","three"`
  - An empty string (`''`) deletes the matches

- **Regex flags** (`-RegexFlags <FLAGS>` / `-flags <FLAGS>`)
  - Third positional argument, the option name may be omitted
  - Implies `-Regex`, see the table below

- **Search file** (`-SearchFile <FILE[]>`) / **Replace file** (`-ReplaceFile <FILE[]>`)
  - **Each line** is **one pattern** / **one replacement**
  - Empty lines in a replace file are *deletions*

- **Search folder** (`-SearchFolder <FOLDER[]>`) / **Replace folder** (`-ReplaceFolder <FOLDER[]>`)
  - All `*.txt` files directly inside the folder, *sorted alphabetically*

- **Pairing**: inline strings, files and folders of the search side form one list, the replace side another one; both lists are paired **by position**. Missing replacements count as empty (= deletion); more replacements than search patterns is an error.

- **Pattern per file** (`-PatternPerFile`)
  - *Every pattern file is one single pattern* (its final line break is removed)
  - Useful for multi-line regex patterns or multiline literal strings
    - Best combined with `-flags "x"` for use as regex (see `assets/matchEngGerDate.txt`)

- **Pair file** (`-PairFile <FILE[]>`)
  - Contains *pairs* of search → replace lines, a folder means all its `*.txt` files
  - Automatically enables **substitution**
  - Pairs are kept together, independent of other pattern sources
  - A warning is shown if the number of lines is odd
    ```
    1. searchValue1
    2. replaceValue1
    3. searchValue2
    4. replaceValue2
    etc.
    ```

- **Empty search patterns** match at every position (between all characters) - that is regex behaviour, a warning is shown.

- All pattern files are read as UTF-8 (a BOM, also UTF-16, is recognised).

---

### Implicit Behaviour

| Condition | Implicit Action |
|-----------|------------------|
| First / second / third unnamed CLI argument | **`-Search`** / **`-Replace`** / **`-RegexFlags`** |
| No search pattern (and no text analysis option) | Activates **interactive mode** (`-Interactive`) |
| Search pattern(s) without replacement | **Grep mode** |
| Any replacement given (incl. `-PairFile`) | **Substitution** |
| `-Delete` or `-Swap` used | **Substitution** |
| `-A`, `-B`, `-C`, `-OnlyMatching`, `-CountOnly`, `-FilesWithMatches`, `-InvertMatch` | **Grep mode** |
| `-Separator` used | **`-OnlyMatching`** for grep output |
| `-RegexFlags` used | **Regex mode** (`-Regex`) |
| `-OutFile` used | **Write to file** (`-Save`) |

Grep and substitution can be combined: grep shows the matches in the original text, then the text is substituted.

---

### Mode Selection: Grep / Substitute / Delete / Swap

- **Grep** (`-Grep`)
  - Prints each matching line **once**, with line number, matches highlighted (red, bold where the console supports it)
  - Context lines with `-A`, `-B`, `-C` (marked with `-`, groups separated by `--`, like GNU grep)
  - Shows the match count; index and length of every match with `-Verbose`

- **Substitution** (`-Substitute`)
  - Performs *search & replace*; the pairs are applied one after another
  - In literal mode `$` in the replacement is taken literally; in regex mode `$1`, `${name}` etc. refer to groups

- **Delete** (`-Delete`)
  - Removes the matches, replacements are ignored

- **Swap** (`-Swap` / `-reverse`)
  - Swaps search and replacement, e.g. to undo a literal substitution

---

### Regex Features

- **Enable RegEx mode** (`-Regex` / `-r`)
  - Interprets all search strings as regular expressions (.NET style)

- **Modifier flags** (`-RegexFlags "imsx..."` / `-flags`)
  - Enables regex implicitly, for available flags see the table below

- **Case-insensitive mode** (`-IgnoreCase` / `-i`)
  - Works for both literal and regex patterns

---

### Apply to Files Instead of Clipboard Content

- **Input path** (`-Path <PATH[]>` / `-files` / `-inputPath`)
  - Files, folders or wildcards (e.g. `*.log`); default target is the clipboard
  - Folders: all contained files are read
  - Files that look binary are skipped
  - Grep prints to the console, the substitution result of all files is joined (see `-Separator`) and put into the clipboard (or a file)

- **Recursive search** (`-Recurse`) in subfolders

- **Include binary** (`-IncludeBinary`) files
  - Does not check files for NUL bytes

- **In-place substitution** (`-InPlace`)
  - Writes the result back into each changed input file, keeping its encoding
  - A backup `<file>.bak` is created before

---

### Output Handling

- **Only matches** (`-OnlyMatching`), e.g. to build your own list of matches
  - Output is reduced to the matches, each followed by the separator

- **Separator** (`-Separator <STRING>`)
  - Separator for `-OnlyMatching` (default: line break), empty string allowed
  - Also joins the substitution results of several files
  - `\t`, `\n`, `\r` and `\\` are converted - this also works in single quotes and desktop shortcuts

- **Count only** (`-CountOnly`) - only the number of matches (per file)

- **Files with matches** (`-FilesWithMatches`) - only the names of files containing matches

- **Invert match** (`-InvertMatch`) - lines *without* matches

- **Write to file** (`-Save`)
  - Writes the substitution result (or the grep output) to `Output_<timestamp>.txt` instead of the clipboard

- **Explicit filename** (`-OutFile <FILE>`)
  - Folder and extension are kept, a timestamp is always appended to the name
  - With grep and substitution together, the grep output goes to `<name>_grep_<timestamp>`
  - With `-Repeat` / `-Endless` the run number is added

---

### Repetition & Looping

- **Looping** re-reads search (and replace) values
  - Pattern files and input files are freshly read in every run
  - CLI arguments are not re-read, but `-Interactive` input is asked again

- **Endless loop mode** (`-Endless` / `-oo`)
  - Repeats the selected operation indefinitely, stop with Ctrl+C
  - Intended for fullscreen or continuously updated applications

- **Repeat count** (`-Repeat <N>`)
  - Execute the operation N times

- **Delay** (`-Delay <SECONDS>`)
  - Waits after each run, `0.5` and `0,5` are both accepted
  - Negative values or `-DelayFirst` wait *before* each run instead

---

### Text Analysis

- **Statistics** (`-Stats`)
  - Character map, text metrics and regex based counts (characters, digits, URLs, e-mails, sentences, lines, words, fields) of the input text, plus the match count of your patterns
  - Every count shows its regex, ready for copy & paste

- **Extended statistics** (`-ExtendedStats`)
  - Additionally counts integers, decimal numbers, Unicode words, currency and math symbols, multiple spaces and line breaks

- **Character map** (`-CharMap`) only
  - Frequency of every character (grapheme) with Unicode code points
  - `-SortBy Count` (default) or `-SortBy Char`
  - `-ShowWhitespace` shows space, tab, CR and LF as visible symbols

- **Text metrics** (`-TextMetrics`) only
  - UTF-8/UTF-16 bytes, code units, code points, grapheme clusters, ASCII check

---

### Additional Features

- **Interactive prompt** (`-Interactive` / `-ia`)
  - Asks for search/replace strings (and, if not given, mode and regex usage) at runtime
  - Automatically activated when no search pattern is provided

- **Pause at end** (`-PauseAtEnd` / `-pause`)
  - Waits for a key press after each run, useful for desktop shortcuts

- **Benchmarking** (`-Benchmark`)
  - Prints timing information for grep, substitution and the whole script

- **Help / Usage overview** (`-Help` / `-h`)

---

## Regex Modifier Table (`-RegexFlags` / `-flags` option)

The following tables lists all supported .NET regex modifiers evaluated in the script:

| Modifier | RegexOptions Enum Value        | Description |
|---------|---------------------------------|-------------|
|         | `None`                          | No additional options enabled. Default behavior. |
| **i**   | `IgnoreCase`                    | Case-insensitive matching. |
| **m**   | `Multiline`                     | `^` and `$` match line start and line end instead of only the beginning/end of the entire input. |
| **s**   | `Singleline`                    | The dot (`.`) also matches newline characters (`\n`). |
| **x**   | `IgnorePatternWhitespace`       | Whitespace in the pattern is ignored; activates free format comment mode |

### Advanced / Exotic Options

| Modifier | RegexOptions Enum Value        | Description |
|---------|---------------------------------|-------------|
| **n**   | `ExplicitCapture`               | Only named groups (e.g. `(?<name>...)`) are captured. |
| **c**   | `Compiled`                      | Compiles the regex for improved performance when reused repeatedly. |
| **u**   | `CultureInvariant`              | Culture‑invariant matching, ignoring locale-specific rules. |
| **j**   | `ECMAScript`                    | Enables ECMAScript‑compatible regular expression behavior. |
| **r**   | `RightToLeft`                   | Performs the match from right to left. |
| **b**   | `NonBacktracking`               | Uses a non‑backtracking regex engine mode (faster, but with feature limitations). **Requires PowerShell 7** - Windows PowerShell 5.1 shows an error. |

## Safety & Security

Check your threat model, as you are supposed to be the one providing the input!

This tool processes **only the current user’s input** (clipboard and/or local files you explicitly provide). Under this assumption, the risk of **Regular Expression Denial of Service (ReDoS)** or other super‑linear (exponential) matches is generally out of scope.

If you still want to be extra cautious, you can **enforce linear‑time matching** by enabling the **NonBacktracking** engine mode via your regex modifiers. This guarantees **no catastrophic backtracking** and therefore avoids auto-ReDoS scenarios.

### What this means

- **ReDoS / catastrophic backtracking**: Certain regex patterns can cause exponential runtimes on specific inputs when backtracking is allowed.
- **NonBacktracking mode**: Disables backtracking in the regex engine, resulting in **predictable, linear runtime**. This eliminates ReDoS risks but **restricts some advanced regex features** (e.g., patterns relying on backtracking constructs). If a pattern depends on such features, it may need to be simplified or rewritten.
- For **trusted, local, one‑user scenarios** (default usage), standard regex behavior is fine - you are *safe* and *secure*!


### How to enable it

- Use the `NonBacktracking` option in your modifier string
  - CLI: `-flags b`
  - Only available in PowerShell 7 (.NET 7+); Windows PowerShell 5.1 reports an error


## Tests

`tests/Test-ClipGre.ps1` runs the script with many option combinations and checks output, clipboard and written files. It needs no extra modules (no Pester) and uses a simulated clipboard, so your real clipboard is not touched:

```powershell
powershell -ExecutionPolicy Bypass -File tests\Test-ClipGre.ps1
```

The exit code is the number of failed checks. Interactive prompts are not covered.

## Why PowerShell?

Why PowerShell? Simple: because it’s *already there*.  
Unlike many languages that would require extra installs or permissions, PowerShell comes preinstalled on (almost) every Windows system — including tightly locked-down enterprise environments.

In those settings, security policies often say:  
*"No, you can’t run that tool… no, you can’t install that… no, you can’t use that language…"*

And PowerShell just stands there, smiling politely like:  
**"Hehe, but *I* am allowed — here’s your solution."**

So while it may not be the flashiest choice, PowerShell is the one tool that actually survives the real-world security gauntlet. And that makes it the perfect fit for this project.

---
### Extended Examples  

Below are extended examples demonstrating further functionality of the script:

```powershell
# Benchmark a regex search operation in a loop applied to a file
clipGre.ps1 -r '(\d+?|\D+)' -Benchmark -Repeat 10 -Path 'data.db'

# regex search & replace with flags (clipbaord)
clipGre.ps1 -r '-.-' ', ' 'ms'

# literal search & replace with flags (clipbaord)
clipGre.ps1 '|'  '{!}' 

# very explicit search and search & replace with persisting terminal for reading output
clipGre.ps1 -r -search '-.-' -replace ', ' -flags 'ms' -Substitute -Grep -PauseAtEnd

# regex search & replace with groups (clipbaord)
clipGre.ps1 -r '- . (\d+) . -' ' $1 ' 'msx'

# regex search & replace with lists of regexes from files, pattern mapping search to replace line by line
clipGre.ps1 -r -searchFile "regex-list.txt" -replaceFile "replacements.txt" "msi"

# regex search & replace with lists of regexes from files, every file one pattern (-PatternPerFile) 
# free formatable regex flag x added
clipGre.ps1 -r -searchFile "regex-list.txt" -replaceFile "replacements.txt" "xi" -PatternPerFile

# Accepts arrays as search/replace strings, e.g. redacting names, e-mails or other patterns
# Option names (-search and -replace) may be omitted if order is kept
clipGre.ps1 -search 'Jens@Hofmann.biz','Albert Schrödinger','123.999' -replace '[Redacted E-Mail]','[Redacted Name]','[Redacted Number]'

# When used with RegEx flags can be specified
# Finds 'foo...bar', uses flags 'si' and prints context lines before and after match
clipGre.ps1 -r -flags si -B 2 -A 1 'foo.{2,4}bar' 

# replace 'SOLUTION<TAB>1' by '<TAB>SOLUTION<WHITEPACE(s)>3' (PHREEQC)
clipGre.ps1 -r '(SOLUTION\s+)1' "`t`${1}3"

# change a Surf- modelfile to SurfO-0.5 (1-pK) (PHREEQC)
clipGre.ps1 −r 'Surf([a−zA−Z]{1,2})','Surf−' 'SurfO$1+0.5','SurfO−0.5’'

# replace newline(s) by a tab - one new line: '[\r][\n]'
clipGre.ps1 -r '[\n\r]+' "`t"

# get overview over a python file (classes, methods, returns)
clipGre.ps1 -r '\s*def\s+(\w+\.)*\w+\(.*?\):|\s*class\s+(\w+\.)*\w+(\(.*?\))?:|\s*return.*$' -Path "solver.py" -Separator '' -flags m

# search your project folder for python docstrings
clipGre.ps1 -r '("""|'''''' ).*?\1' -Path "." -Recurse

```
