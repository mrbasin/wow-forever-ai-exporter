param(
    [Parameter(Mandatory)][ValidatePattern('^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$')][string]$Tag,
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{40}$')][string]$Commit,
    [Parameter(Mandatory)][string]$ArtifactDirectory
)
$ErrorActionPreference = 'Stop'
if ($env:GITHUB_REPOSITORY -cne 'mrbasin/wow-forever-ai-exporter' -or -not $env:GH_TOKEN) {
    throw 'Run this publisher in the official GitHub Actions workflow.'
}
$repo = $env:GITHUB_REPOSITORY
$api = "https://api.github.com/repos/$repo"
$version = $Tag.Substring(1)
$assetName = "Exporter-$version.zip"
$zipPath = Join-Path $ArtifactDirectory $assetName
$digest = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
$checksum = (Get-Content -LiteralPath "$zipPath.sha256" -Raw).Trim()
if ($checksum -cne "$digest  $assetName") { throw 'Artifact checksum mismatch.' }
$headers = @{ Authorization="Bearer $env:GH_TOKEN"; Accept='application/vnd.github+json';
    'X-GitHub-Api-Version'='2022-11-28'; 'User-Agent'='Exporter-release-workflow' }
# Resolve annotated tags too; never create or move a tag while publishing.
$remote = Invoke-RestMethod -Uri "$api/commits/$Tag" -Headers $headers
if ($remote.sha -cne $Commit) { throw 'Tag moved after the build; publication stopped.' }
$release = $null
try { $release = Invoke-RestMethod -Uri "$api/releases/tags/$Tag" -Headers $headers }
catch { if ([int]$_.Exception.Response.StatusCode -ne 404) { throw } }
if (-not $release) {
    $notes = @"
Download ``$assetName``, extract it, and copy the ``Exporter`` folder into ``_forever_\Interface\AddOns``. Start WoW and type ``/exporter`` to open settings. The Windows PowerShell decoder is included.

**Experimental.** Disconnects have occurred during exports. If this happens, disable AI Exporter in the AddOns menu before logging back in.

SHA-256: ``$digest``
"@
    $body = @{tag_name=$Tag; target_commitish=$Commit; name="WoW Forever AI Exporter $version"; body=$notes; draft=$true} | ConvertTo-Json
    $release = Invoke-RestMethod -Method Post -Uri "$api/releases" -Headers $headers -ContentType 'application/json' -Body $body
}
$asset = $release.assets | Where-Object name -CEQ $assetName | Select-Object -First 1
if ($asset) {
    if ($asset.digest -cne "sha256:$digest" -or $asset.state -cne 'uploaded') { throw 'An existing asset differs; it will not be overwritten.' }
} else {
    if (-not $release.draft) { throw 'Published release is missing its ZIP; refusing to alter it.' }
    $uploadUrl = "https://uploads.github.com/repos/$repo/releases/$($release.id)/assets?name=$assetName"
    $asset = Invoke-RestMethod -Method Post -Uri $uploadUrl -Headers $headers -ContentType 'application/zip' -InFile $zipPath
    if ($asset.digest -cne "sha256:$digest" -or $asset.state -cne 'uploaded') { throw 'Uploaded asset checksum mismatch.' }
}
if ($release.draft) {
    $release = Invoke-RestMethod -Method Patch -Uri "$api/releases/$($release.id)" -Headers $headers -ContentType 'application/json' -Body '{"draft":false}'
}
if ($release.draft) { throw 'Release is still a draft.' }
$download = Join-Path $ArtifactDirectory 'public-download.zip'
# No authentication headers are sent for the final public download.
Invoke-WebRequest -Uri "https://github.com/$repo/releases/download/$Tag/$assetName" -OutFile $download -MaximumRetryCount 3 -RetryIntervalSec 5
if ((Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash.ToLowerInvariant() -cne $digest) { throw 'Public download checksum mismatch.' }
"Published and verified $($release.html_url)" | Tee-Object -FilePath $env:GITHUB_STEP_SUMMARY -Append
