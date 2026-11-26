param([string]$PythonPath='python.exe', [string]$NodePath='node.exe')
$ErrorActionPreference='Stop'
Push-Location $PSScriptRoot
try {
    & (Join-Path $PSScriptRoot 'Build.ps1') | Write-Host
    & $NodePath scripts/run-lua-test.js tests/test_stats.lua addon/Exporter/CharacterStats.lua
    if($LASTEXITCODE -ne 0){throw 'Character stats tests failed'}
    & $NodePath scripts/run-lua-test.js tests/test_equipment.lua addon/Exporter/Equipment.lua
    if($LASTEXITCODE -ne 0){throw 'Equipment tests failed'}
    & $NodePath scripts/run-lua-test.js tests/test_talents.lua addon/Exporter/Talents.lua
    if($LASTEXITCODE -ne 0){throw 'Talent tests failed'}
    & $NodePath scripts/run-lua-test.js tests/test_spellbook.lua addon/Exporter/Spellbook.lua
    if($LASTEXITCODE -ne 0){throw 'Spellbook tests failed'}
    & $NodePath scripts/run-lua-test.js tests/test_questlog.lua addon/Exporter/QuestLog.lua
    if($LASTEXITCODE -ne 0){throw 'Quest log tests failed'}
    & $NodePath scripts/run-lua-test.js tests/test_items.lua addon/Exporter/Items.lua
    if($LASTEXITCODE -ne 0){throw 'Items tests failed'}
    & $NodePath scripts/run-lua-test.js tests/test_professions_active.lua addon/Exporter/Professions.lua
    if($LASTEXITCODE -ne 0){throw 'Professions tests failed'}
    & $NodePath scripts/run-lua-test.js tests/test_requests.lua addon/Exporter/DataRequests.lua
    if($LASTEXITCODE -ne 0){throw 'Shared data request tests failed'}
    & $NodePath scripts/run-lua-test.js tests/test_compact.lua addon/Exporter/Exporter.lua
    if($LASTEXITCODE -ne 0){throw 'Compact export schema tests failed'}
    & $NodePath scripts/run-lua-test.js tests/test_exporter.lua addon/Exporter/Exporter.lua addon/Exporter/Options.lua
    if($LASTEXITCODE -ne 0){throw 'Exporter integration tests failed'}
    & $PythonPath -m unittest discover -s tests -v
    if($LASTEXITCODE -ne 0){throw 'Python tests failed'}
    & (Join-Path $PSScriptRoot 'tests\test_install.ps1')
    Write-Host 'PASS: addon Lua suites, wire-format tests, installer backup and rollback checks.'
}finally{Pop-Location}
