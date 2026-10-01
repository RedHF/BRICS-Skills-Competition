[CmdletBinding(SupportsShouldProcess = $true)]
param()
$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ($taskRoot -ne 'C:\Users\Admin\Documents\GitHub\BRICS-Skills-Competition') { throw 'Unexpected workspace.' }
$taskPrefix = $taskRoot + [IO.Path]::DirectorySeparatorChar
$taskScopes = @('LLM_Temp/', '配音文本/', 'output/本地档案/提交包重复素材/', 'output/本地档案/原始可变字体/', 'output/参赛材料/本科组_Track1_第二队/')
$taskReportPath = Join-Path $taskRoot 'docs/重复文件清理-2026-10-01.json'
$taskReport = Get-Content -LiteralPath $taskReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($taskReport.status -ne 'planned') { throw 'Plan already executed or invalid.' }
$taskDeletePaths = @{}
foreach ($taskRecord in $taskReport.files) { $taskDeletePaths[$taskRecord.delete] = $true }
$taskHashes = @{}
foreach ($taskRecord in $taskReport.files) {
    if (-not @($taskScopes | Where-Object { $taskRecord.delete.StartsWith($_, [StringComparison]::Ordinal) }).Count) { throw 'Deletion outside authorized scope.' }
    if ($taskDeletePaths.ContainsKey($taskRecord.retain)) { throw 'Retained copy is scheduled for deletion.' }
    foreach ($taskRelative in @($taskRecord.delete, $taskRecord.retain)) {
        $taskPath = [IO.Path]::GetFullPath((Join-Path $taskRoot $taskRelative))
        if (-not $taskPath.StartsWith($taskPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Path outside workspace.' }
        $taskItem = Get-Item -LiteralPath $taskPath -Force
        if ($taskItem.PSIsContainer) { throw 'Expected regular file.' }
        $taskAncestor = $taskItem
        while ($taskAncestor -and $taskAncestor.FullName -ne $taskRoot) {
            if ($taskAncestor.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Linked path encountered.' }
            $taskAncestor = if ($taskAncestor -is [IO.FileInfo]) { $taskAncestor.Directory } else { $taskAncestor.Parent }
        }
        if (-not $taskHashes.ContainsKey($taskPath)) { $taskHashes[$taskPath] = (Get-FileHash -LiteralPath $taskPath -Algorithm SHA256).Hash }
        if ($taskHashes[$taskPath] -ne $taskRecord.sha256) { throw "Hash mismatch: $taskRelative" }
    }
}
foreach ($taskRecord in $taskReport.files) {
    $taskPath = [IO.Path]::GetFullPath((Join-Path $taskRoot $taskRecord.delete))
    if ($PSCmdlet.ShouldProcess($taskPath, 'Delete byte-identical redundant file')) { Remove-Item -LiteralPath $taskPath -Force }
}
if ($WhatIfPreference) { return }
foreach ($taskScope in $taskScopes) {
    $taskDir = [IO.Path]::GetFullPath((Join-Path $taskRoot $taskScope.TrimEnd('/')))
    if (-not $taskDir.StartsWith($taskPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Directory outside workspace.' }
    if (-not (Test-Path -LiteralPath $taskDir)) { continue }
    foreach ($taskEmpty in (Get-ChildItem -LiteralPath $taskDir -Directory -Recurse -Force | Sort-Object { $_.FullName.Length } -Descending)) {
        if (-not @(Get-ChildItem -LiteralPath $taskEmpty.FullName -Force).Count) { Remove-Item -LiteralPath $taskEmpty.FullName -Force }
    }
    if (-not @(Get-ChildItem -LiteralPath $taskDir -Force).Count) { Remove-Item -LiteralPath $taskDir -Force }
}
foreach ($taskRecord in $taskReport.files) {
    $taskRetained = [IO.Path]::GetFullPath((Join-Path $taskRoot $taskRecord.retain))
    if ((Get-FileHash -LiteralPath $taskRetained -Algorithm SHA256).Hash -ne $taskRecord.sha256) { throw 'Retained copy verification failed.' }
}
$taskReport.status = 'completed'
$taskReport | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $taskReportPath -Encoding UTF8
Write-Output "Deleted $($taskReport.delete_files) identical copies; $($taskReport.delete_bytes) bytes. Every retained copy verified."
