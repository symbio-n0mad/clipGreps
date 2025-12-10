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
clipGre.ps1 -search "Albert Einstein","Erwin Schrödinger","Whitney Houston" -replace "[Redacted Name]","[Redacted Name]","[Redacted Name]"

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



## Exotic / Advanced Features
All additional functional flags are categorized as extended capabilities:

- Interactive **prompt** for single **search/replace** strings (`-interactive`)

- Explicit **search file** (`-searchFile <FILENAME>`)  
  - Applied **line by line** (compatible with `-ci` and `-r`)
  - Empty lines **deprecated**

- Explicit **replace file** (`-replaceFile <FILENAME>`)  
  - Applied **line by line**  
  - **Empty lines = deletions**

- Explicit **search folder** (`-searchFolder <FOLDERNAME>`)  
  - Only *.txt files are used
  - Files are sorted alphabetical prior to usage
  - Applied **file by file** (compatible with `-ci` and `-r`)
  - Empty files **deprecated**
  - _Incompatible_ with `-grep`

- Explicit **replace folder** (`-replaceFolder <FOLDERNAME>`)  
  - Only *.txt files are used
  - Files are sorted alphabetical prior to usage
  - Applied **file by file**  
  - **Empty files = deletions**

- Can **output to file** instead of clipboard (`-write`)  
  - If no filename is given, a **timestamp** is used  
  - Optional explicit filename via `-saveAs <FILENAME>`
    - Timestamp gets added anyway

- **Time delay** before script ends (`-timeout <SECONDS>`, decimals allowed)  
  - Negative values introduce a **delay _before_ execution** (useful for fullscreen applications)

- **Exit requires confirmation** (Terminal stays open until pressing enter `-confirm`)
    - For arbitrary additional peeking time, terminal might be closed after results are evaluated 

- Activate **standard settings** (`-standard`)  
  - Standard file paths: `.\SEARCH.txt` and `.\REPLACE.txt` (used if existent)
  - Standard folder paths: `.\SEARCH\*.txt` and `.\REPLACE\*.txt` (used if existent, _incompatible_ with `-grep` mode)
  - Corresponding existence is validated and reported

- **Repeated** application of chosen action in an **endless loop** `-endless`
    - Optional timeout for every loop `-loopDelay`
    - Useful for fullscreen applications

- Display **all** available **flags** with `-h` or `-usage`

---

## Why PowerShell?

Why PowerShell? Simple: because it’s *already there*.  
Unlike many languages that would require extra installs or permissions, PowerShell comes preinstalled on (almost) every Windows system — including tightly locked-down enterprise environments.

In those settings, security policies often say:  
*"No, you can’t run that tool… no, you can’t install that… no, you can’t use that language…"*

And PowerShell just stands there, smiling politely like:  
**"Hehe, but *I* am allowed — here’s your solution."**

So while it may not be the flashiest choice, PowerShell is the one tool that actually survives the real-world security gauntlet. And that makes it the perfect fit for this project.

