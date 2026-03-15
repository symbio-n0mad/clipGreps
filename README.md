# clipGreps: Clipboard Grep and Substitutions
## clipGre.ps1

A lightweight PowerShell script for **filter** or **search & replace operations** directly on your **clipboard content**.

---

## Basic Features
These are the core, productive features:

- Supports **inline strings** (`-search foo`, `-replace bar`) or **text files** (see below) as search/replace ammo  
  - Reads your clipboard, modifies it and puts changes back into the clipboard
- Includes a **grep-like search** mode (`-search <pattern>`) for quick text filtering 🔍  
  - Displays: literal match, full line (+ optional context) containing the match, the line number and overall match count
- Optional **RegEx** mode (`-r`) and **case-insensitive mode** (`-i`)  



---
### Basic Examples  
Below are simple examples demonstrating the essential functionality of the script:

```powershell
# Basic inline search & replace
# Replaces every occurrence of "foo" with "bar" in the clipboard content.
clipGre.ps1 -search "foo" -replace "bar"
# Accepts arrays as search/replace strings, e.g. redacting names
clipGre.ps1 -search "Jens@Hofmann.biz","Albert Schrödinger","123.999" -replace "[Redacted E-Mail]","[Redacted Name]","[Redacted Number]"

# Grep-like filtering (no replacement)
# Keeps only lines that match "pattern" from the clipboard
clipGre.ps1 -searchText "pattern"

# RegEx + case-insensitive replacement
# Finds "foo...bar" regardless of case, and replaces the entire match with "baz".
clipGre.ps1 -r -i -searchText "foo.*bar" -replaceText "baz"

```

##  GUI Tip: Run via Keyboard Shortcut (Windows)

For quick access - without having to use the command line, it's highly recommended to run the script via a **custom keyboard shortcut** in Windows.  
You can achieve this easily using a **desktop shortcut** that launches PowerShell with the correct arguments.

###  Setup Steps

1. **Create a Shortcut**
   - Right-click on your desktop → **New → Shortcut**  
   - For the location, enter something like:
     ```powershell
     powershell.exe -ExecutionPolicy Bypass -File "C:\Path\To\clipGre.ps1" -ci -searchText "foo.bar" -replaceText "baz"
     ```
     >  `-ExecutionPolicy Bypass` ensures the script runs without restrictions, even if PowerShell’s default policy is limited.

2. **Assign a Keyboard Shortcut**
   - Right-click the newly created shortcut → **Properties**
   - In the **Shortcut** tab, click inside the *Shortcut key* field and press your desired key combo (e.g. `Ctrl + Alt + R`)
   - Click **Apply** or **OK**

3. **Use It**
   - Now you can simply press your shortcut to run `clipGre.ps1` instantly — perfect for quick routine clipboard transformations or grep-style searches on the fly.
---


## All Features Explained (incl. Advanced / Implicit Behaviour)

Below is a complete overview of all functional capabilities. Several options interact with each other and may implicitly activate related features. Unless noted otherwise, all options are **optional**, and the script attempts to **infer intent automatically**.

---

### Search & Replace Inputs

- **Inline search strings** (`-searchText`)  
  - Provided as a single string or an array  
    - Example: `-st "foo","bar","baz"`
  
- **Inline replacement strings** (`-replaceText`)  
  - Single string or array  
    - Example: `-rt "one","two","three"`

- **Search file** (`-searchFile <FILE>`)  
  - Single string or array  
  - May be provided multiple times  
  - Each line is treated as one search pattern  
  - Empty lines are **deprecated**

- **Replace file** (`-replaceFile <FILE>`)  
  - Single string or array  
  - May be provided multiple times  
  - Each line corresponds to a replacement pattern  
  - **Empty patterns = deletions**

- **Search folder** (`-searchFolder <FOLDER>`)  
  - Single string or array  
  - Accepts one or multiple directories  
  - Uses only `*.txt` files  
  - Files are sorted alphabetically  
  - File count must match `-replaceFolder`  
  - Empty files are **deprecated**

- **Replace folder** (`-replaceFolder <FOLDER>`)  
  - Single string or array  
  - Identical behaviour as search folder  
  - **Empty patterns = deletions**

---

### Mapping Files (Lazy / Mapping Mode)

- **Mapping file** (`-mappingFile`, aliases: `-lazyFile`, `-lazyPairs`)  
  - Single string or array  
  - Contains *pairs* of search → replace entries  
  - Automatically enables **substitution mode** (`-substitute`)  
  - Ideal for lists of mappings where maintaining separate search/replace files is inconvenient  
  - Ensures consistent pairing without having to manage file order manually  
  - Lines typically follow the format:  
    ```
    1. searchValue 
    2. replaceValue
    3. searchValue 
    4. replaceValue
    etc.
    ```

---

### Implicit Behaviour

Several features are triggered automatically when certain flags or inputs are used:

| Condition | Implicit Action |
|----------|------------------|
| No search/replace arguments given | Activates **interactive mode** (`-interactive`) |
| `-A`, `-B` or `-C` provided | Enables **grep mode** (`-grep`) |
| `-flags` / `-modifier` used | Enables **regex mode** (`-r`) |
| `-mappingFile` used | Enables **substitution** |
| `-revert` used | Enables **substitution** |

---

### Mode Selection: Extract / Replace / Delete

These options are **optional** because the script attempts to infer which mode you intended based on the provided inputs. However, you may explicitly combine them if needed, where applicable.

- **Grep / Extract match** (`-grep / -g`)  
  - Prints only matching lines (or extracted text)  
  - Context options available (`-A`, `-B`, `-C`)

- **Substitution** (`-substitute` / `-s`)  
  - Performs search & replace  
  - Activated automatically through mapping files or `-revert`
  - Overridden by `-delete`

- **Revert substitution** (`-revert` / `-e`)  
  - Swaps search and replace values

- **Delete** (`-delete` / `-d`)  
  - Removes lines matching the search pattern  
  - Useful for cleaning lists or rapidly filtering content

---

### Regex Features

- **Enable RegEx mode** (`-regEx` / `-r`)  
  - Interprets all search strings as .NET regular expressions

- **Modifier flags** (`-flags "imsx..."` / `-m`)  
  - Enables regex implicitly and passes flags directly to the .NET engine  
  - Example: `-m "imx"`
  - For available options see table below

- **Case-insensitive mode** (`-ignoreCase` / `-i`)  
  - Works for both literal and regex patterns

---

### Input Processing

- **Line-by-line mode** (default)  
  - Each line is treated as an independent expression

- **Whole-file mode** (`-wholeFile` / `-f`)  
  - Input is considered one single expression  
  - Useful for multi-line regex patterns or structural transformations

---

### Interactive Mode

- **Interactive prompt** (`-interactive` / `-ia`)  
  - Allows entering search/replace strings manually at runtime  
  - Automatically activated when no search/replace arguments are provided

---

### Output Handling

- **Write to file** (`-w` / `-write`)  
  - Redirects output to a file instead of copying to clipboard

- **Explicit filename** (`-saveAs <FILE>` / `-o <FILE>`)  
  - Custom filename  
  - A timestamp is always appended

- **Default filename**  
  - When no name is provided, a timestamp is used automatically
  - Even with provided filename, a timestamp is added

---

### Repetition & Looping

- **Endless loop mode** (`-endless` / `-8`)  
  - Repeats the selected operation indefinitely  
  - Intended for fullscreen or continuously updated applications
  - Requires manual termination

- **Loop count** (`-loop <N>` / `-l <N>`)  
  - Execute the operation N times
  - Overridden by `-endless`

- **Timeout between loops** (`-timeout <SECONDS>` / `-t <SECONDS>` )  
  - Delays execution before exiting  
  - Negative values delay execution *before* running the action  
  - Recommended when combining with `-endless` or `-loop <N>`

---

### Additional Behaviour

- **Require confirmation before exit** (`-persist` / `-p`)  
  - Keeps the terminal open until the user presses Enter  
  - Useful for manual inspection of output

- **Benchmarking** (`-benchmark` / `-bm`)  
  - Prints timing information for pattern application and script execution

- **Statistics** (`-stats` / `-n`)  
  - Displays counts of matches, counts occurence of various text-properties guided by regex

- **Help / Usage overview** (`-help` / `-h`)  
  - Displays all flags and usage instructions

---

## Regex Modifier Table (`-m` / `-modifier` Flag)

The following table lists all supported regex modifiers evaluated in the script:

| Modifier | RegexOptions Enum Value        | Description |
|---------|---------------------------------|-------------|
| **n**   | `None`                          | No additional options enabled. Default behavior. |
| **i**   | `IgnoreCase`                    | Case-insensitive matching. |
| **m**   | `Multiline`                     | `^` and `$` match line start and line end instead of only the beginning/end of the entire input. |
| **s**   | `Singleline`                    | The dot (`.`) also matches newline characters (`\n`). |
| **x**   | `IgnorePatternWhitespace`       | Whitespace in the pattern is ignored; comments are allowed. |

### Advanced / Exotic Options

| Modifier | RegexOptions Enum Value        | Description |
|---------|---------------------------------|-------------|
| **e**   | `ExplicitCapture`               | Only named groups (e.g. `(?<name>...)`) are captured. |
| **c**   | `Compiled`                      | Compiles the regex for improved performance when reused repeatedly. |
| **u**   | `CultureInvariant`              | Culture‑invariant matching, ignoring locale-specific rules. |
| **j**   | `ECMAScript`                    | Enables ECMAScript‑compatible regular expression behavior. |
| **r**   | `RightToLeft`                   | Performs the match from right to left. |
| **b**   | `NonBacktracking`               | Uses a non‑backtracking regex engine mode (faster, but with feature limitations). |

## Safety & Security

> TL;DR: By default, this tool assumes trusted, user‑local input. If you want to be absolutely safe against ReDoS, enable **NonBacktracking** (`-m b`) to guarantee linear performance.

This tool processes **only the current user’s input** (clipboard and/or local files you explicitly provide). Under this assumption, the risk of **Regular Expression Denial of Service (ReDoS)** or other super‑linear (exponential) matches is generally out of scope.

If you still want to be extra cautious, you can **enforce linear‑time matching** by enabling the **NonBacktracking** engine mode via your regex modifiers. This guarantees **no catastrophic backtracking** and therefore avoids ReDoS scenarios.

### What this means

- **ReDoS / catastrophic backtracking**: Certain regex patterns can cause exponential runtimes on specific inputs when backtracking is allowed.
- **NonBacktracking mode**: Disables backtracking in the regex engine, resulting in **predictable, linear runtime**. This eliminates ReDoS risks but **restricts some advanced regex features** (e.g., patterns relying on backtracking constructs). If a pattern depends on such features, it may need to be simplified or rewritten.
- For **trusted, local, one‑user scenarios** (default usage), standard regex behavior is fine.
- For **maximum safety** or when using complex patterns, add `b` to your modifiers to enforce **NonBacktracking**.


### How to enable it

- Use the `NonBacktracking` option in your modifier string (the script flag is `b`).
- Example with your script’s modifier flag:
  - CLI: `-m b`
  - Combined with other flags (e.g., case‑insensitive + multiline + non‑backtracking): `-m imb`


## Why PowerShell?

Why PowerShell? Simple: because it’s *already there*.  
Unlike many languages that would require extra installs or permissions, PowerShell comes preinstalled on (almost) every Windows system — including tightly locked-down enterprise environments.

In those settings, security policies often say:  
*"No, you can’t run that tool… no, you can’t install that… no, you can’t use that language…"*

And PowerShell just stands there, smiling politely like:  
**"Hehe, but *I* am allowed — here’s your solution."**

So while it may not be the flashiest choice, PowerShell is the one tool that actually survives the real-world security gauntlet. And that makes it the perfect fit for this project.

