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
"Runner source: tools/windows/Run-BaselineTests.ps1" | Add-Content (Join-Path $out "manifest.txt")

function Invoke-GodotCapture {
    param([string[]]$GodotArgs, [string]$LogBase)
    $stdout = "$LogBase.stdout.txt"
    $stderr = "$LogBase.stderr.txt"
    # Start-Process prevents Windows PowerShell 5.1 from converting native
    # stderr lines prefixed ERROR: into terminating NativeCommandError records.
    $p = Start-Process -FilePath $GodotExe -ArgumentList $GodotArgs -Wait -PassThru -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $text = ((Get-Content $stdout -Raw -ErrorAction SilentlyContinue), (Get-Content $stderr -Raw -ErrorAction SilentlyContinue)) -join [Environment]::NewLine
    $text | Set-Content "$LogBase.log"
    return [pscustomobject]@{ ExitCode=$p.ExitCode; Text=$text; Log="$LogBase.log" }
}

$version = Invoke-GodotCapture -GodotArgs @("--version") -LogBase (Join-Path $out "godot-version")
if ($version.ExitCode -ne 0) { throw "Godot --version failed; see $($version.Log)" }
$tests = @(Get-ChildItem (Join-Path $project "scripts") -Filter "*_test.gd" -File | Sort-Object Name)
if ($tests.Count -eq 0) { throw "No *_test.gd files found." }
$results = @()
foreach ($test in $tests) {
    Write-Host "Running $($test.Name)"
    $relative = "res://scripts/$($test.Name)"
    $run = Invoke-GodotCapture -GodotArgs @("--headless","--path",('"' + $project + '"'),"--script",$relative) -LogBase (Join-Path $out $test.BaseName)
    $failedMarker = $run.Text -match '(?im)^\s*(?:SCRIPT ERROR:|ERROR:|FAIL(?:ED)?\b|.*ALL FAIL\b)'
    $passed = ($run.ExitCode -eq 0) -and (-not $failedMarker)
    $results += [pscustomobject]@{ Test=$test.Name; ExitCode=$run.ExitCode; Result=$(if($passed){"PASS"}else{"REVIEW"}); Log=$run.Log }
}
$results | Export-Csv (Join-Path $out "results.csv") -NoTypeInformation
$results | Format-Table -AutoSize
Write-Host "Reports: $out"
Write-Host "NOTE: PASS indicates clean test exit without recognized failure messages, not visual/device acceptance."
if ($results | Where-Object { $_.Result -ne "PASS" }) { exit 1 }
