# Requires Python 3.10+ and the official Godot 4.3 console executable.
param(
    [string]$GodotExe = "C:\ReapersReaper\Tools\Godot43-Windows.exe",
    [string]$OutputRoot = "C:\ReapersReaper\TestResults",
    [switch]$Capture,
    [int]$TimeoutSeconds = 120
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if (!(Test-Path -PathType Leaf $GodotExe)) { throw "Godot executable missing: $GodotExe" }
$python = Get-Command python -ErrorAction Stop
$out = Join-Path $OutputRoot ((Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8))
$runnerArgs = @((Join-Path $repo 'tools\testing\run_godot_tests.py'), '--godot', $GodotExe, '--output', $out, '--timeout', $TimeoutSeconds)
if ($Capture) { $runnerArgs += '--capture' }
& $python.Source @runnerArgs
exit $LASTEXITCODE
