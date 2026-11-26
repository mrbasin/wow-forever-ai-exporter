#requires -Version 5.1
<#
.SYNOPSIS
Reads a WoW Forever AI Exporter cooldownmanager.txt and prints its snapshot as JSON.
.PARAMETER Output
Write UTF-8 JSON to this file and print its full path.
.PARAMETER Pretty
Indent the JSON for human review.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position=0)] [Alias('CacheFile')] [string]$Path,
    [string]$Output,
    [switch]$Pretty
)

$ErrorActionPreference = 'Stop'
try {
    $cachePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    if ($Output) {
        $outputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Output)
        if ([string]::Equals($cachePath, $outputPath, [StringComparison]::OrdinalIgnoreCase) -or
            [IO.Path]::GetFileName($outputPath) -ieq 'cooldownmanager.txt') {
            throw 'Output cannot overwrite the game cache.'
        }
    }

    if (-not ('WowForeverAIExporter.ExportWire' -as [type])) {
        Add-Type -LiteralPath (Join-Path $PSScriptRoot 'ExportWire.cs')
    }
    $json = [WowForeverAIExporter.ExportWire]::Read($cachePath)
    if ($PSVersionTable.PSEdition -eq 'Desktop') {
        $snapshot = [Windows.Data.Json.JsonObject, Windows.Data.Json, ContentType=WindowsRuntime]::Parse($json)
        $source = $snapshot.GetNamedString('sourceAddon')
        $version = $snapshot.GetNamedNumber('schemaVersion')
        $guid = $snapshot.GetNamedObject('character').GetNamedString('guid')
    } else {
        $snapshot = [System.Text.Json.JsonDocument]::Parse($json)
        try {
            $source = $snapshot.RootElement.GetProperty('sourceAddon').GetString()
            $version = $snapshot.RootElement.GetProperty('schemaVersion').GetDouble()
            $guid = $snapshot.RootElement.GetProperty('character').GetProperty('guid').GetString()
        } finally { $snapshot.Dispose() }
    }
    if ($source -cne 'Exporter' -or (1..5) -notcontains $version -or -not $guid) {
        throw 'Not a supported Exporter snapshot.'
    }

    $formatted = [WowForeverAIExporter.ExportWire]::FormatJson($json, $Pretty.IsPresent)
    $utf8 = [Text.UTF8Encoding]::new($false)
    if ($Output) {
        [WowForeverAIExporter.ExportWire]::WriteOutput($cachePath, $outputPath, $formatted)
        $result = $outputPath
    } else {
        $result = $formatted
    }
    $originalEncoding = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = $utf8
        Write-Output $result
    } finally { [Console]::OutputEncoding = $originalEncoding }
} catch {
    [Console]::Error.WriteLine($_.Exception.GetBaseException().Message)
    exit 1
}
