[CmdletBinding(SupportsShouldProcess = $true)]
param()

$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$taskPrefix = $taskRoot + [IO.Path]::DirectorySeparatorChar

# Keep the verified release and every unique review record before deleting caches.
$taskArchive = Join-Path $taskRoot 'dist/檐下千秋-v10-可玩性修复版-20260915.zip'
$taskExpected = 'A7021FE9F01E80F86ED59085855706CFE23B6560A6AF85EE24BDD6B3420D942F'
if ((Get-FileHash -LiteralPath $taskArchive -Algorithm SHA256).Hash -ne $taskExpected) {
    throw 'Release archive changed. Review the cleanup plan before proceeding.'
}
$taskEvidenceIndex = Join-Path $taskRoot 'LLM-tmp/验证记录/2026-09-15-可玩性/补充原始记录/归档索引.json'
$taskEvidence = Get-Content -LiteralPath $taskEvidenceIndex -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($taskRecord in $taskEvidence) {
    $taskRetained = [IO.Path]::GetFullPath((Join-Path $taskRoot $taskRecord.retained))
    if (-not $taskRetained.StartsWith($taskPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Evidence path is outside the workspace.'
    }
    if ((Get-FileHash -LiteralPath $taskRetained -Algorithm SHA256).Hash -ne $taskRecord.sha256) {
        throw "Retained evidence changed: $taskRetained"
    }
}

# Explicit disposable paths only. Source, assets, AI records and release ZIPs remain.
$taskTargets = @(
    'tmp',
    '.tools/go.zip',
    '.tools/godot-official.zip',
    '.tools/python-embed.zip',
    'LLM-tmp/客户端/.godot',
    'LLM-tmp/04-工具/tech-full.txt',
    'LLM-tmp/.review',
    'Art_Material/Official/首届AI赋能数字创意设计与应用赛项-波克IP素材/灵画师/Thumbs.db',
    'output/参赛材料/本科组_Track1_第二队/Task02/Original/美术源文件/Official/首届AI赋能数字创意设计与应用赛项-波克IP素材/灵画师/Thumbs.db'
)
$taskChecked = @()
$taskTotalBytes = 0L
foreach ($taskRelative in $taskTargets) {
    $taskPath = [IO.Path]::GetFullPath((Join-Path $taskRoot $taskRelative))
    if (-not $taskPath.StartsWith($taskPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Cleanup target is outside the workspace: $taskPath"
    }
    if (-not (Test-Path -LiteralPath $taskPath)) { continue }
    $taskItem = Get-Item -LiteralPath $taskPath -Force
    $taskChildren = @(Get-ChildItem -LiteralPath $taskPath -Recurse -Force)
    foreach ($taskEntry in @($taskItem) + $taskChildren) {
        if ($taskEntry.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Review linked path before cleanup: $($taskEntry.FullName)"
        }
    }
    if ($taskItem.PSIsContainer) {
        $taskTotalBytes += ($taskChildren | Where-Object { -not $_.PSIsContainer } | Measure-Object -Property Length -Sum).Sum
    } else {
        $taskTotalBytes += $taskItem.Length
    }
    $taskChecked += $taskPath
}

foreach ($taskPath in $taskChecked) {
    if ($PSCmdlet.ShouldProcess($taskPath, 'Delete verified disposable files')) {
        Remove-Item -LiteralPath $taskPath -Recurse -Force
    }
}
if ($WhatIfPreference) {
    Write-Output "Preview only: $($taskChecked.Count) paths, $taskTotalBytes bytes. No files deleted."
} else {
    Write-Output "Deleted $($taskChecked.Count) paths, $taskTotalBytes bytes."
}
