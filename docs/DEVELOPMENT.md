# Development and testing

This optional guide is for people changing the addon, building a package, or
checking its output. You do not need to run these tests to use the addon.
For installation and everyday use, start with the [main guide](../README.md).

Run the commands below from the project folder in PowerShell 7.

## Build and install

`Build.ps1` packages the thirteen game runtime files, the Windows PowerShell 5.1
decoder (`Decode-Export.ps1` and `ExportWire.cs`), `LICENSE` and
`THIRD_PARTY.md` in a clean `dist/Exporter` folder. Windows PowerShell loads
the C# reader with the built-in `Add-Type` command. Development and installation scripts use PowerShell 7.
The test suite uses Node and Python.

```powershell
.\Build.ps1
.\Build.ps1 -Install -WoWRoot 'C:\Games\World of Warcraft\_forever_'
```

The game root must contain `Interface` and `WTF`. Installation stages the
Exporter runtime files, decoder and two license notices, backs up overwritten files with a
manifest, and rolls back copy failures. It changes no Startup settings or other
addons. Optional `-CacheFilePath`
selects one existing cache file under that game's account directory for the path
display; otherwise all discovered locations are shown. With no discovered file,
the addon shows the [character-file template](COLLECTION_DETAILS.md#where-the-data-goes).
Reinstall to refresh hints for new characters.
Installation uses temporary staging so local path hints never enter the release
folder. A normal build replaces the generated `dist/Exporter` folder completely.

Reload after updating an existing installation. For a new addon folder, fully
restart WoW if it does not appear in the AddOns list. Enable **AI Exporter** in
the AddOns menu. Exporter uses layout field 127 and refuses to replace a marker
owned by another addon. If the slot is occupied, disable the conflicting addon
and reload before enabling Exporter.

Do not run development tests against the installed addon. Prepare and test the
repository copy, then explicitly install the update and reload at a safe time.

## Set up and run the tests

Use PowerShell 7, Node.js 24, and Python 3.14. GitHub Actions runs the same test
command on Windows for pushes and pull requests.

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
npm ci --ignore-scripts
.\Test.ps1 -PythonPath .\.venv\Scripts\python.exe
```

The single test command builds the package, runs the addon’s Lua suites using pinned
Fengari, verifies the wire format, and checks installation/rollback in temporary
folders. Lua assertion failures fail the command. The ignored `dist`, `.cache`,
and `backups` directories must never be committed; they may contain local paths
or private QA data. No files from another project are needed for normal setup.

To exercise the same decoder a player's desktop AI uses, run this command from
the project folder with a real cache path. Omit `-Output` to print JSON or add
`-Pretty` for indentation.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\addon\Exporter\Decode-Export.ps1 -Path 'C:\Games\WoW\WTF\Account\EXAMPLE\Realm\Hero\cooldownmanager.txt' -Output .cache\Exporter.json
```

For a second implementation to compare during development, use the Python
reference decoder after installing the test dependencies.

```powershell
.\.venv\Scripts\python.exe tools\inspect_export.py 'C:\Games\WoW\WTF\Account\EXAMPLE\Realm\Hero\cooldownmanager.txt' --output .cache\Exporter.json
```

This reference decoder is a test utility, not part of the addon or a running
integration. It preserves capture timestamps and never writes to the source file.
Output is compact JSON by default for AI use; add `--pretty` for indented human
review. Decoding preserves schema-5 column tables and does not add legacy
availability labels back to compact data.

Version **1.0.0** targets WoW Forever (TOC 16001) and writes snapshot schema **5**
using the **EXP1** transport marker.
MIT licensed; see [THIRD_PARTY.md](../THIRD_PARTY.md) for reused source and dev packages.

## Compatibility and excluded data

Action-bar payloads, recipes, weapon/riding skills, expansion-specific profession
child trees, reputation standings, bank/mail and current health/mana remain excluded.
The reader accepts snapshot schemas 1 through 5. Check the schema before reading
category fields. A missing section means the information is unavailable.
See the [export format](../EXPORT_FORMAT.md) for field definitions.

## Contributing and QA

Use synthetic data in tests. Keep character data, account paths and screenshots
out of commits. Include a test for transport, timing, or category changes. Verify
in-game settings, periodic and ad-hoc delivery, category exclusion, file timestamps,
and coexistence/slot refusal before a release. Record offline and live results
separately. No gameplay input, point spending or talent resets are needed for QA.
