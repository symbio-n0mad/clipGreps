# clipGreps: Clipboard Grep and Substitutions
## clipGre.ps1

A lightweight PowerShell script for **filter** or **search & replace operations** directly on your **clipboard content**.

---

## Basic Features
These are the core, productive features:

- Supports **inline strings** (`-search foo`, `-replace bar`) or **text files** (see below) as search/replace ammo  
  - Reads your clipboard, modifies it and puts changes back into the clipboard
- Includes a **grep-like search** mode (`-grep`) for quick text filtering 🔍  
  - Displays: literal match, full line containing the match, the line number and overall match count
- Optional **RegEx** mode (`-r`) and **case-insensitive mode** (`-ci`)  



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
# Keeps only lines that match "pattern" from the clipboard, holds terminal open until confirmation
clipGre.ps1 -grep -searchText "pattern" -confirm

# RegEx + case-insensitive replacement
# Finds "foo...bar" regardless of case, and replaces the entire match with "baz".
clipGre.ps1 -r -ci -searchText "foo.*bar" -replaceText "baz"

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



## All Features Explained (incl. Exotic / Advanced)
All additional functional flags are categorized as extended capabilities:

- **Inline strings** may be provided as array
  - E. g. `-search "foo","bar","baz"` `-replace "rea","lwo","rds"`

- **RegEx** mode (`-r`) available
  - All input search patterns are interpreted as RegEx (.NET flavor)

- **Case-insensitive mode** (`-ci`) for search patterns
  - Despite being often standardized, here an explicit call is necessary

- Interactive **prompt** for single **search/replace** strings (`-interactive`)
    - Provide search/replace strings at program start, on the fly.

- Explicit **search file** (`-searchFile <FILENAME>`)  
  - Applied **line by line** in ordered fashion (compatible with `-ci` and `-r`)
  - Empty lines **deprecated**

- Explicit **replace file** (`-replaceFile <FILENAME>`)  
  - Applied **line by line** or **file by file**
  - **Empty lines = deletions**

- Explicit **search folder** (`-searchFolder <FOLDERNAME>`)  
  - Only *.txt files are used, whole files at once
  - Files are sorted alphabetical prior to usage
  - File count must match with replace folder file count
  - Applied **file by file** or **line by line**
  - Empty files **deprecated**

- Explicit **replace folder** (`-replaceFolder <FOLDERNAME>`)  
  - Only *.txt files are used, whole files at once
  - Files are sorted alphabetical prior to usage
  - File count has to match search folder file count
  - Applied **file by file** or **line by line**
  - **Empty files = deletions**

- Can **output to file** instead of clipboard (`-write`)  
  - If no filename is given, a **timestamp** is used  
  - Optional explicit filename (`-saveAs <FILENAME>`)
    - Timestamp gets added anyway
    
- **Repeated** application of chosen action in an **endless loop** (`-endless`)
    - Timeout for every loop (`-loopDelay <SECONDS>`, optional but _recommended_)
    - Intended for fullscreen applications
    - Forcefully termination of script obligatory

- **Time delay** before script ends (`-timeout <SECONDS>`, decimals allowed)  
  - Prolong your peeking time as desired
  - Negative values introduce a **delay _before_ execution** 
    - Intended for fullscreen applications

- **Exit requires confirmation** (`-confirm`)
    - Terminal stays open until pressing enter 
    - For arbitrary/variable peeking time, terminal might be closed after output is evaluated 

- Display **all** available **flags** (`-h` / `-usage`)

---

## Why PowerShell?

Why PowerShell? Simple: because it’s *already there*.  
Unlike many languages that would require extra installs or permissions, PowerShell comes preinstalled on (almost) every Windows system — including tightly locked-down enterprise environments.

In those settings, security policies often say:  
*"No, you can’t run that tool… no, you can’t install that… no, you can’t use that language…"*

And PowerShell just stands there, smiling politely like:  
**"Hehe, but *I* am allowed — here’s your solution."**

So while it may not be the flashiest choice, PowerShell is the one tool that actually survives the real-world security gauntlet. And that makes it the perfect fit for this project.

