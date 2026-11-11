# Hector MVP: one simple turn loop (recruit -> action -> auto battle -> settle).
# Usage: powershell -ExecutionPolicy Bypass -File .\tools\run_mvp.ps1
param(
    [string]$Godot = "D:\SOFT\Godot\Godot_v4.7.2-stable_win64.exe"
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot

if (-not (Test-Path $Godot)) {
    throw "Godot not found: $Godot"
}

& $Godot --path $ProjectRoot "res://scenes/mvp.tscn"
