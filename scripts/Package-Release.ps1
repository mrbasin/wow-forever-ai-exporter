param(
    [Parameter(Mandatory)][string]$SourceRoot,
    [Parameter(Mandatory)][ValidatePattern('^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$')][string]$Tag,
    [Parameter(Mandatory)][string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
$SourceRoot = (Resolve-Path -LiteralPath $SourceRoot).Path
$version = $Tag.Substring(1)
$packageJson = Get-Content -LiteralPath (Join-Path $SourceRoot 'package.json') -Raw | ConvertFrom-Json
$lock = Get-Content -LiteralPath (Join-Path $SourceRoot 'package-lock.json') -Raw | ConvertFrom-Json -AsHashtable
if ($packageJson.version -cne $version -or $lock.version -cne $version -or $lock.packages[''].version -cne $version) {
    throw 'Tag and package versions must match.'
}
foreach ($toc in 'Exporter.toc','Exporter_Camelot.toc') {
    $text = Get-Content -LiteralPath (Join-Path $SourceRoot "addon/Exporter/$toc") -Raw
    if ($text -notmatch ('(?m)^## Version: ' + [regex]::Escape($version) + '\r?$')) { throw "Version mismatch in $toc" }
}
$lua = Get-Content -LiteralPath (Join-Path $SourceRoot 'addon/Exporter/Exporter.lua') -Raw
if ($lua -notmatch ('Exporter = \{version="' + [regex]::Escape($version) + '"')) { throw 'Runtime version mismatch.' }

# Build without -Install: installed copies may contain private local path hints.
& (Join-Path $SourceRoot 'Build.ps1') | Out-Null
$package = Join-Path $SourceRoot 'dist/Exporter'
$names = @('CharacterStats.lua','DataRequests.lua','Decode-Export.ps1','Equipment.lua','ExportWire.cs',
    'Exporter.lua','Exporter.toc','Exporter_Camelot.toc','Items.lua','LICENSE','LocalPaths.lua','Options.lua',
    'Professions.lua','QuestLog.lua','Spellbook.lua','Talents.lua','THIRD_PARTY.md')
$entries = @(Get-ChildItem -LiteralPath $package -Force)
if (@(Compare-Object $names @($entries.Name)).Count -ne 0 -or
    @($entries | Where-Object { $_.PSIsContainer -or ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) }).Count) {
    throw 'Package contains missing, unexpected, or redirected files.'
}
$hints = Get-Content -LiteralPath (Join-Path $package 'LocalPaths.lua') -Raw
if (($hints -replace '(?m)^--[^\r\n]*', '').Trim() -cne 'ExporterLocalPaths = {}') { throw 'Private installation hints are not allowed.' }

$utf8 = [Text.UTF8Encoding]::new($false, $true)
$payloads = @{}
foreach ($name in $names) {
    # Stable line endings and timestamps make packages independent of checkout settings.
    $text = [IO.File]::ReadAllText((Join-Path $package $name), $utf8).Replace("`r`n", "`n")
    if ($text -match '(?i)[a-z]:[\\/]+Users[\\/]|/Users/|/home/|-----BEGIN .*PRIVATE KEY|github_pat_|ghp_[A-Za-z0-9]') {
        throw "Private path or credential pattern in $name"
    }
    $payloads[$name] = $utf8.GetBytes($text)
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$OutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path
$zipPath = Join-Path $OutputDirectory "Exporter-$version.zip"
if (Test-Path -LiteralPath $zipPath) { throw 'Output ZIP already exists; use an empty output directory.' }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::Open($zipPath, [IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($name in ($names | Sort-Object -CaseSensitive)) {
        $entry = $zip.CreateEntry("Exporter/$name", [IO.Compression.CompressionLevel]::Optimal)
        $entry.LastWriteTime = [DateTimeOffset]::new(2000,1,1,0,0,0,[TimeSpan]::Zero)
        $stream = $entry.Open()
        try { $stream.Write($payloads[$name], 0, $payloads[$name].Length) } finally { $stream.Dispose() }
    }
} finally { $zip.Dispose() }
$zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
try {
    if ($zip.Entries.Count -ne $names.Count) { throw 'ZIP entry count mismatch.' }
    foreach ($entry in $zip.Entries) {
        $name = $entry.FullName.Substring('Exporter/'.Length)
        if ($entry.FullName -cne "Exporter/$name" -or -not $payloads.ContainsKey($name)) { throw 'Unexpected ZIP path.' }
        $stream = $entry.Open()
        $buffer = [IO.MemoryStream]::new()
        try {
            $stream.CopyTo($buffer)
            if ([Convert]::ToBase64String($buffer.ToArray()) -cne [Convert]::ToBase64String($payloads[$name])) { throw "ZIP content mismatch: $name" }
        } finally { $stream.Dispose(); $buffer.Dispose() }
    }
} finally { $zip.Dispose() }
$digest = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText("$zipPath.sha256", "$digest  $([IO.Path]::GetFileName($zipPath))`n", $utf8)
Write-Output "Verified Exporter-$version.zip ($($names.Count) files), SHA-256 $digest"
