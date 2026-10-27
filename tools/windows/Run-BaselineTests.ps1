# Reaper's Reaper Windows baseline test runner (non-destructive)
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\windows\Run-BaselineTests.ps1
param(
    [string]$GodotExe = "C:\ReapersReaper\Tools\Godot43-Windows.exe",
    [string]$OutputRoot = "C:\ReapersReaper\TestResults"
)
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$project = Join-Path $repo "godot-project"
if (!(Test-Path -PathType Leaf $GodotExe)) { throw "Godot executable not found: $GodotExe" }
if (!(Test-Path -PathType Leaf (Join-Path $project "project.godot"))) { throw "Godot project missing at $project" }
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$out = Join-Path $OutputRoot $stamp
New-Item -ItemType Directory -Force -Path $out | Out-Null
$sha = (& git -C $repo rev-parse HEAD | Out-String).Trim()
"Git commit: $sha" | Set-Content (Join-Path $out "manifest.txt")
"Godot: $GodotExe" | Add-Content (Join-Path $out "manifest.txt")
& $GodotExe --version 2>&1 | Out-File (Join-Path $out "godot-version.txt")
$tests = Get-ChildItem (Join-Path $project "scripts") -Filter "*_test.gd" -File | Sort-Object Name
$results = @()
foreach ($test in $tests) {
    Write-Host "Running $($test.Name)"
    $log = Join-Path $out ($test.BaseName + ".log")
    $relative = "res://scripts/$($test.Name)"
    $lines = & $GodotExe --headless --path $project --script $relative 2>&1 | Out-String
    $lines | Set-Content $log
    $code = $LASTEXITCODE
    $fatal = $lines -match "(?m)^SCRIPT ERROR:|(?m)^ERROR:|(?i)ALL FAIL|(?i)\bFAIL(?:ED)?\b"
    $passed = ($code -eq 0) -and (-not $fatal)
    $results += [pscustomobject]@{ Test=$test.Name; ExitCode=$code; Result=$(if($passed){"PASS"}else{"REVIEW"}); Log=$log }
}
$results | Export-Csv (Join-Path $out "results.csv") -NoTypeInformation
$results | Format-Table -AutoSize
Write-Host "Reports: $out"
Write-Host "NOTE: PASS means the test process exited cleanly without common failure markers, not visual/device acceptance."
if ($results | Where-Object { $_.Result -ne "PASS" }) { exit 1 }
