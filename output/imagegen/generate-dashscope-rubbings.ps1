param(
    [string]$ApiKey = $env:DASHSCOPE_API_KEY,
    [string]$BaseUrl = 'https://dashscope.aliyuncs.com',
    [string]$Model = 'qwen-image-3.0-pro',
    [string]$Size = '1024*1536',
    [switch]$Force,
    [string]$Only = ''
)
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ApiKey)) { throw 'Set DASHSCOPE_API_KEY in the current process before generating.' }
$jobs = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'rubbings-prompts.jsonl') -Encoding UTF8 | ForEach-Object { $_ | ConvertFrom-Json }
$assetRoot = Join-Path $PSScriptRoot '../../LLM-tmp/客户端/assets/rubbings'
New-Item -ItemType Directory -Path $assetRoot -Force | Out-Null
foreach ($job in $jobs) {
    if ($Only -and $job.out -ne $Only) { continue }
    $target = Join-Path $PSScriptRoot $job.out
    if ((Test-Path -LiteralPath $target) -and -not $Force) { Copy-Item -LiteralPath $target -Destination (Join-Path $assetRoot $job.out) -Force; continue }
    $payload = [pscustomobject]@{
        model = $Model
        input = [pscustomobject]@{ messages = @([pscustomobject]@{ role = 'user'; content = @([pscustomobject]@{ text = [string]$job.prompt }) }) }
        parameters = [pscustomobject]@{ size = $Size; n = 1 }
    } | ConvertTo-Json -Depth 8
    Write-Output ('Generating ' + $job.out + ' with ' + $Model)
    try {
        $result = Invoke-RestMethod -Method Post -Uri ($BaseUrl.TrimEnd('/') + '/api/v1/services/aigc/multimodal-generation/generation') -Headers @{ Authorization = 'Bearer ' + $ApiKey; 'X-DashScope-Async' = 'disable' } -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($payload)) -TimeoutSec 600
    } catch {
        $reason = $_.Exception.Message
        if ($_.ErrorDetails.Message) { $reason += ' / ' + ($_.ErrorDetails.Message -replace 'sk-[A-Za-z0-9._-]+', '[redacted]' -replace 'https?://\S+', '[url]' -replace '\s+', ' ') }
        throw ('Image generation failed for ' + $job.out + ': ' + $reason)
    }
    $item = @($result.output.choices[0].message.content | Where-Object { $_.type -eq 'image' })[0]
    if ($null -eq $item -or [string]::IsNullOrWhiteSpace([string]$item.image)) { throw ('No image returned for ' + $job.out) }
    Invoke-WebRequest -UseBasicParsing -Uri ([string]$item.image) -OutFile $target -TimeoutSec 300
    Copy-Item -LiteralPath $target -Destination (Join-Path $assetRoot $job.out) -Force
    Add-Type -AssemblyName System.Drawing
    $bitmap = [Drawing.Image]::FromFile($target)
    try { Write-Output ('Saved ' + $job.out + ' (' + $bitmap.Width + 'x' + $bitmap.Height + ')') } finally { $bitmap.Dispose() }
}
