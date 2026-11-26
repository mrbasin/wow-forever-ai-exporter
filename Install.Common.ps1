function Copy-ExporterPackageFile {
    param([string]$Source, [string]$Destination)
    Copy-Item -LiteralPath $Source -Destination $Destination -Force -ErrorAction Stop
}

function Install-ExporterAddon {
    param([Parameter(Mandatory)][string]$PackageDir,
          [Parameter(Mandatory)][string]$WoWRoot,
          [Parameter(Mandatory)][string]$BackupRoot)
    $targetDir = [IO.Path]::GetFullPath((Join-Path $WoWRoot 'Interface\AddOns\Exporter'))
    $names = @('Exporter.lua','DataRequests.lua','CharacterStats.lua','Equipment.lua','Talents.lua','Spellbook.lua','QuestLog.lua','Items.lua','Professions.lua','Options.lua','LocalPaths.lua','Exporter.toc','Exporter_Camelot.toc','Decode-Export.ps1','ExportWire.cs','LICENSE','THIRD_PARTY.md')
    $ancestor = $targetDir
    while ($ancestor) {
        if (Test-Path -LiteralPath $ancestor) {
            $item = Get-Item -LiteralPath $ancestor -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Refusing installation through a reparse point: $ancestor" }
        }
        $ancestor = Split-Path -Parent $ancestor
    }
    foreach ($name in $names) {
        if (-not (Test-Path -LiteralPath (Join-Path $PackageDir $name) -PathType Leaf)) { throw "Missing package file: $name" }
        $dest = Join-Path $targetDir $name
        if (Test-Path -LiteralPath $dest) {
            $item = Get-Item -LiteralPath $dest -Force
            if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "Unsafe addon target: $dest" }
        }
    }
    $backupDir = Join-Path ([IO.Path]::GetFullPath($BackupRoot)) ((Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    $manifest = foreach ($name in $names) {
        $dest = Join-Path $targetDir $name
        $existed = Test-Path -LiteralPath $dest -PathType Leaf
        if ($existed) { Copy-Item -LiteralPath $dest -Destination (Join-Path $backupDir $name) -ErrorAction Stop }
        [ordered]@{name=$name;existed=$existed;originalHash=$(if ($existed) { (Get-FileHash -LiteralPath $dest).Hash } else { $null })}
    }
    [ordered]@{addonDirectory=$targetDir;files=@($manifest)} | ConvertTo-Json -Depth 4 |
        Set-Content -LiteralPath (Join-Path $backupDir 'manifest.json') -Encoding utf8
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    $attempted = [Collections.Generic.List[string]]::new()
    try {
        foreach ($name in $names) {
            $attempted.Add($name)
            Copy-ExporterPackageFile -Source (Join-Path $PackageDir $name) -Destination (Join-Path $targetDir $name)
            if ((Get-FileHash -LiteralPath (Join-Path $PackageDir $name)).Hash -ne
                (Get-FileHash -LiteralPath (Join-Path $targetDir $name)).Hash) { throw "Installed hash mismatch: $name" }
        }
    } catch {
        $installError = $_
        $rollbackErrors = @()
        foreach ($name in $attempted) {
            try {
                $entry = $manifest | Where-Object { $_.name -eq $name }
                $dest = Join-Path $targetDir $name
                if ($entry.existed) { Copy-Item -LiteralPath (Join-Path $backupDir $name) -Destination $dest -Force -ErrorAction Stop }
                elseif (Test-Path -LiteralPath $dest -PathType Leaf) { Remove-Item -LiteralPath $dest -Force -ErrorAction Stop }
            } catch { $rollbackErrors += $_.Exception.Message }
        }
        if ($rollbackErrors.Count) { throw "Installation failed: $installError. Rollback also needs attention: $($rollbackErrors -join '; '). Backup: $backupDir" }
        throw "Installation failed and copied files were rolled back: $installError. Backup: $backupDir"
    }
    return [pscustomobject]@{AddonDirectory=$targetDir;BackupDirectory=$backupDir;Files=$names}
}
