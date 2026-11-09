# Hector 开发入口：定位 Godot 可执行文件并运行。
# 用法：
#   .\tools\run.ps1            # 启动游戏窗口
#   .\tools\run.ps1 -Mode test # 无头冒烟测试
#   .\tools\run.ps1 -Mode import

param(
    [ValidateSet("play", "test", "import")]
    [string]$Mode = "play",
    [string]$Godot = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot

if (-not $Godot) {
    if ($env:GODOT_BIN) {
        $Godot = $env:GODOT_BIN
    } else {
        $candidate = Get-ChildItem "D:\SOFT\Godot" -Filter "Godot_v*_console.exe" -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending | Select-Object -First 1
        if ($candidate) {
            $Godot = $candidate.FullName
        }
    }
}

if (-not $Godot -or -not (Test-Path $Godot)) {
    throw "找不到 Godot 可执行文件。请设置 GODOT_BIN，或用 -Godot 指定路径。"
}

switch ($Mode) {
    "play" {
        & $Godot --path $ProjectRoot
    }
    "test" {
        & $Godot --headless --path $ProjectRoot --script "res://tests/smoke_test.gd"
        exit $LASTEXITCODE
    }
    "import" {
        & $Godot --headless --path $ProjectRoot --import
        exit $LASTEXITCODE
    }
}
