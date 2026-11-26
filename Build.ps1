param([switch]$Install, [string]$WoWRoot, [string]$CacheFilePath,
      [string]$BackupRoot = (Join-Path $PSScriptRoot 'backups'))
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Install.Common.ps1')
$names=@('Exporter.lua','DataRequests.lua','CharacterStats.lua','Equipment.lua','Talents.lua','Spellbook.lua','QuestLog.lua','Items.lua','Professions.lua','Options.lua','LocalPaths.lua','Exporter.toc','Exporter_Camelot.toc','Decode-Export.ps1','ExportWire.cs')
$source=Join-Path $PSScriptRoot 'addon\Exporter'
$package=Join-Path $PSScriptRoot 'dist\Exporter'
$installStage=$null
function ConvertTo-LuaString([string]$Value) {
    '"' + $Value.Replace('\','\\').Replace('"','\"').Replace("`r",'\r').Replace("`n",'\n') + '"'
}
if($Install){
    if(-not $WoWRoot){throw 'Specify -WoWRoot containing Interface and WTF.'}
    $WoWRoot=[IO.Path]::GetFullPath($WoWRoot)
    foreach($folder in @('Interface','WTF')){if(-not (Test-Path -LiteralPath (Join-Path $WoWRoot $folder) -PathType Container)){throw "Invalid WoW root: missing $folder"}}
    # Installation hints must never enter the public release directory.
    $installStage=Join-Path ([IO.Path]::GetTempPath()) ('exporter-install-'+[guid]::NewGuid().ToString('N'))
    $package=Join-Path $installStage 'Exporter'
}else{
    # Rebuild only this project's generated package; reject redirected paths.
    $distRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'dist'))
    $package=[IO.Path]::GetFullPath($package)
    if($package -ne (Join-Path $distRoot 'Exporter')){throw 'Unsafe package output path'}
    foreach($path in @($distRoot,$package)){
        if(Test-Path -LiteralPath $path){
            $item=Get-Item -LiteralPath $path -Force
            if(-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw "Unsafe package directory: $path"}
        }
    }
    if(Test-Path -LiteralPath $package){Remove-Item -LiteralPath $package -Recurse -Force}
}
try {
New-Item -ItemType Directory -Path $package -Force | Out-Null
foreach($name in $names){Copy-Item -LiteralPath (Join-Path $source $name) -Destination (Join-Path $package $name) -Force}
foreach($name in @('LICENSE','THIRD_PARTY.md')){Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $package $name) -Force}
if($Install){
    $accountRoot=Join-Path $WoWRoot 'WTF\Account'
    $paths=@()
    if($CacheFilePath){
        $resolved=[IO.Path]::GetFullPath($CacheFilePath)
        if(-not $resolved.StartsWith($accountRoot.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase) -or
            [IO.Path]::GetFileName($resolved) -ne 'cooldownmanager.txt' -or -not (Test-Path -LiteralPath $resolved -PathType Leaf)){
            throw 'CacheFilePath must be an existing cooldownmanager.txt under this WoW account tree.'
        }
        $paths=@($resolved)
    }elseif(Test-Path -LiteralPath $accountRoot){
        $paths=@(Get-ChildItem -LiteralPath $accountRoot -Filter cooldownmanager.txt -File -Recurse | Sort-Object FullName | Select-Object -ExpandProperty FullName)
    }
    # Machine-specific paths exist only in temporary staging and the installed addon.
    $escaped=@($paths | ForEach-Object { ConvertTo-LuaString $_ })
    $localPaths='-- Generated locally; do not publish.'+"`n"+'ExporterLocalPaths = {wowRoot='+(ConvertTo-LuaString $WoWRoot)+',cacheFiles={'+($escaped -join ',')+'}}'+"`n"
    [IO.File]::WriteAllText((Join-Path $package 'LocalPaths.lua'),$localPaths,[Text.UTF8Encoding]::new($false))
    Install-ExporterAddon -PackageDir $package -WoWRoot $WoWRoot -BackupRoot $BackupRoot
}else{Write-Output $package}
}finally{
    if($installStage){
        $resolved=[IO.Path]::GetFullPath($installStage)
        $allowed=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
        if(-not $resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $resolved) -notlike 'exporter-install-*'){throw 'Unsafe install staging cleanup target'}
        if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
    }
}
