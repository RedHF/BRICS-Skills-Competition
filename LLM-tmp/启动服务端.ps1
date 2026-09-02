param(
    [int]$Port = 8090,
    [string]$DataPath = "data/save.json"
)

$ErrorActionPreference = "Stop"
$serverDir = Join-Path $PSScriptRoot "服务端"
$go = Get-Command go -ErrorAction SilentlyContinue
if ($null -eq $go) {
    throw "未找到 Go。请安装 Go 1.22 或更高版本后重试。"
}
Push-Location $serverDir
try {
    & $go.Source run ./cmd/server -addr (":$Port") -content ./content/chapters.json -data $DataPath
} finally {
    Pop-Location
}
