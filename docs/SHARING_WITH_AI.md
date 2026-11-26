# Share your character with an AI

The addon comes with a decoder that reads WoW's `cooldownmanager.txt` and
outputs your snapshot as JSON. It uses Windows PowerShell 5.1 and works offline.

## Use the prompt in WoW

1. Log into the character you want to share, open `/exporter`, check **Enable
   exporting**, and click **Export now**.
2. Wait for **"Snapshot sent to WoW; disk delivery may be delayed."** Stay
   logged in while decoding. Logging out, reloading the UI, or disabling
   exporting can remove the snapshot from the game file.
3. Click **Select AI prompt**, press **Ctrl+C**, and paste into ChatGPT or
   Claude. A desktop AI with access to files and PowerShell on this PC can
   run the command and read the result. If the prompt needs your game
   folder, give it the folder containing **Interface** and **WTF**, usually
   called **_forever_**.
4. Ask about your character. For example, “When was this captured, including
   the time zone? Based on my equipped wand, talents and current quests,
   what should I do next for solo leveling?”

The prompt identifies your character by GUID and asks for the latest matching
capture. WoW may take time to write a new capture. Check the capture time
before using the answer.

## Save a JSON file to attach

If your chat cannot run commands on your PC, you can run the command yourself.
Use the command in the copied prompt with its `-Output` option, or follow the
steps below.

1. Find your character's file in the **Character export source** box in
   `/exporter`. If it shows placeholders, open your game's **WTF** folder in
   File Explorer and look under **Account**, your account, realm, and character.
   The file is named **cooldownmanager.txt**. Shift-right-click it and select
   **Copy as path**.
2. In File Explorer, open **Interface**, **AddOns**, then **Exporter** inside
   the same game folder. You should see **Decode-Export.ps1** and its helper
   **ExportWire.cs** beside **Exporter.toc**. Type `powershell` into File Explorer's address bar and
   press **Enter** to open Windows PowerShell in that folder.
3. Run the first line below. When prompted, paste the full path to your
   character's cache and press **Enter**. Then run the second line to save
   the snapshot to a file in your Windows temporary folder.

```powershell
$cache = (Read-Host 'Paste the path to cooldownmanager.txt').Trim('"')
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Decode-Export.ps1 -Path $cache -Output "$env:TEMP\wow-character.json"
```

4. After the decoder prints the full output path, paste that path into your
   chat's file picker to attach **wow-character.json**. To view the JSON in
   the console instead, omit `-Output` and its filename.

The file can contain your character's name, ID, location, gear, and quest
history. Share it only where you want that information used. To share updated
progress, request another capture, run the decoder again, and attach the newly
saved file. Using the same output path replaces the previous copy after a
successful decode.

## If something goes wrong

| What you see | What to try |
| --- | --- |
| PowerShell cannot find `Decode-Export.ps1` or `ExportWire.cs`. | Open the installed **Interface\AddOns\Exporter** folder. If either file is missing, update the whole Exporter folder from the current package. |
| The decoder cannot find the cache. | Check the character and file path. If the file has yet to appear, keep the character logged in with exporting enabled and allow WoW time to save it. |
| No Exporter snapshot, or an older capture than expected. | Check the character path, click **Export now**, stay logged in, wait for WoW to write the file, then run the decoder again. |
| A checksum or invalid-data error. | WoW may have been writing the file. Wait and try again. If the error persists, keep the exact message when asking for help. |
| The AI cannot interpret the JSON structure. | Attach the [export format reference](../EXPORT_FORMAT.md) with the JSON. |

For more on what's included, see the [collection details](COLLECTION_DETAILS.md).
