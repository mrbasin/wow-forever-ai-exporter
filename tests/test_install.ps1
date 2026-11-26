$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
. (Join-Path $project 'Install.Common.ps1')
$tempRoot=Join-Path ([IO.Path]::GetTempPath()) ('exporter-test-'+[guid]::NewGuid().ToString('N'))
$game=Join-Path $tempRoot 'Game with spaces é'
$target=Join-Path $game 'Interface\AddOns\Exporter'
function Assert([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
try {
    $release=& (Join-Path $project 'Build.ps1')
    Set-Content -LiteralPath (Join-Path $release 'stale-private.txt') -Value 'must not be packaged'
    $release=& (Join-Path $project 'Build.ps1')
    $expected=@('DataRequests.lua','CharacterStats.lua','Equipment.lua','Talents.lua','Spellbook.lua','QuestLog.lua','Items.lua','Professions.lua','Exporter.lua','Exporter.toc','Exporter_Camelot.toc','Decode-Export.ps1','ExportWire.cs','LICENSE','LocalPaths.lua','Options.lua','THIRD_PARTY.md')
    $actual=@(Get-ChildItem -LiteralPath $release -File | Select-Object -ExpandProperty Name)
    Assert (@(Compare-Object $expected $actual).Count -eq 0) 'Release contains missing or unexpected files'
    $releaseHashes=@{}
    foreach($name in $expected){$releaseHashes[$name]=(Get-FileHash -LiteralPath (Join-Path $release $name)).Hash}
    Assert ((Get-FileHash -LiteralPath (Join-Path $release 'LICENSE')).Hash -eq (Get-FileHash -LiteralPath (Join-Path $project 'LICENSE')).Hash) 'Release license differs from source'
    $decoderFiles = @('Decode-Export.ps1', 'ExportWire.cs')
    foreach ($name in $decoderFiles) {
        Assert ($releaseHashes[$name] -eq (Get-FileHash -LiteralPath (Join-Path $project "addon\Exporter\$name")).Hash) "Release decoder differs from source: $name"
    }
    New-Item -ItemType Directory -Path $target,(Join-Path $game 'WTF\Account\FICTIONAL\Realm\Hero') -Force | Out-Null
    $cache=Join-Path $game 'WTF\Account\FICTIONAL\Realm\Hero\cooldownmanager.txt'
    Set-Content -LiteralPath $cache -Value 'fixture cache untouched'
    Set-Content -LiteralPath (Join-Path $target 'Exporter.lua') -Value 'old addon'
    Set-Content -LiteralPath (Join-Path $target 'unrelated.txt') -Value 'preserved'
    $backup=Join-Path $tempRoot 'backups'
    $result=& (Join-Path $project 'Build.ps1') -Install -WoWRoot $game -BackupRoot $backup
    Assert ((Get-Content -LiteralPath (Join-Path $result.BackupDirectory 'Exporter.lua') -Raw).Trim() -eq 'old addon') 'Missing original backup'
    Assert ((Get-Content -LiteralPath $cache -Raw).Trim() -eq 'fixture cache untouched') 'Installer changed game data'
    Assert (Test-Path -LiteralPath (Join-Path $target 'unrelated.txt')) 'Unrelated addon file changed'
    $localPaths=Get-Content -LiteralPath (Join-Path $target 'LocalPaths.lua') -Raw -Encoding utf8
    Assert ($localPaths.Contains('FICTIONAL')) 'Missing installed cache path hint'
    Assert ($localPaths.Contains('wowRoot="'+$game.Replace('\','\\')+'"')) 'Missing installed game root hint'
    Assert (-not (Get-Content -LiteralPath (Join-Path $project 'addon\Exporter\LocalPaths.lua') -Raw).Contains('FICTIONAL')) 'Private path leaked to source'
    Assert ((Get-FileHash -LiteralPath (Join-Path $target 'LICENSE')).Hash -eq $releaseHashes['LICENSE']) 'Installed license missing or changed'
    Assert ((Get-FileHash -LiteralPath (Join-Path $target 'THIRD_PARTY.md')).Hash -eq $releaseHashes['THIRD_PARTY.md']) 'Installed attribution missing or changed'
    foreach ($name in $decoderFiles) {
        Assert ((Get-FileHash -LiteralPath (Join-Path $target $name)).Hash -eq $releaseHashes[$name]) "Installed decoder missing or changed: $name"
    }
    foreach($name in $expected){Assert ((Get-FileHash -LiteralPath (Join-Path $release $name)).Hash -eq $releaseHashes[$name]) "Installation altered public release file: $name"}
    $old=(Get-FileHash -LiteralPath (Join-Path $target 'Exporter.lua')).Hash
    $script:copies=0
    function Copy-ExporterPackageFile {
        param($Source,$Destination)
        $script:copies++
        Copy-Item -LiteralPath $Source -Destination $Destination -Force
        if($script:copies -eq 2){throw 'Simulated partial installation failure'}
    }
    $failed=$false
    try {Install-ExporterAddon -PackageDir (Join-Path $project 'dist\Exporter') -WoWRoot $game -BackupRoot $backup | Out-Null}catch{$failed=$true}
    Assert $failed 'Rollback test failed to trigger'
    Assert ((Get-FileHash -LiteralPath (Join-Path $target 'Exporter.lua')).Hash -eq $old) 'Rollback failed'
    $rejected=$false
    try {& (Join-Path $project 'Build.ps1') -Install -WoWRoot $tempRoot | Out-Null}catch{$rejected=$true}
    Assert $rejected 'Invalid root accepted'
    Write-Host 'PASS: clean release, isolated install, Unicode paths, local path generation, backups, rollback, unrelated files and invalid-root rejection'
}finally{
    $resolved=[IO.Path]::GetFullPath($tempRoot)
    $allowed=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if(-not $resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $resolved) -notlike 'exporter-test-*'){throw 'Unsafe cleanup target'}
    if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
