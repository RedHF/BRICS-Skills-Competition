param(
    [string]$BaseUrl = 'https://api.okinto.com/v1',
    [string]$Model = 'gpt-image-2.5',
    [string]$Size = '1024x1536',
    [string]$Only = '',
    [switch]$Force
)
$ErrorActionPreference = 'Stop'
if (-not $env:IMAGE_API_KEY) { throw 'Set IMAGE_API_KEY in the current process before generating.' }
$jobs = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'rubbings-prompts.jsonl') -Encoding UTF8 | ForEach-Object { $_ | ConvertFrom-Json }
$clientFolder = -join @([char]0x5ba2, [char]0x6237, [char]0x7aef)
$assetRoot = Join-Path $PSScriptRoot ('../../LLM-tmp/' + $clientFolder + '/assets/rubbings')
New-Item -ItemType Directory -Path $assetRoot -Force | Out-Null
foreach ($job in $jobs) {
    if ($Only -and $job.out -ne $Only) { continue }
    $target = Join-Path $PSScriptRoot $job.out
    if ($Force -or -not (Test-Path -LiteralPath $target)) {
        $payload = @{ model = $Model; prompt = $job.prompt; n = 1; size = $Size } | ConvertTo-Json -Depth 4
        $headers = @{ Authorization = 'Bearer ' + $env:IMAGE_API_KEY }
        Write-Output ('Generating ' + $job.out + ' with ' + $Model)
        try {
            $result = Invoke-RestMethod -Method Post -Uri ($BaseUrl.TrimEnd('/') + '/images/generations') -Headers $headers -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($payload)) -TimeoutSec 300
        } catch {
            # Do not print response bodies, request headers or signed image URLs.
            $reason = $_.Exception.Message
            if ($_.ErrorDetails.Message) {
                try {
                    $detail = $_.ErrorDetails.Message | ConvertFrom-Json
                    $safeMessage = [string]$detail.error.message
                    if ($safeMessage) { $reason += ' / ' + ($safeMessage -replace 'sk-[A-Za-z0-9_-]+', '[redacted]' -replace 'https?://\S+', '[url]') }
                } catch { }
            }
            throw ('Image generation failed for ' + $job.out + ': ' + $reason)
        } finally { $headers.Clear() }
        $item = @($result.data)[0]
        if ($item.b64_json) {
            [IO.File]::WriteAllBytes($target, [Convert]::FromBase64String($item.b64_json))
        } elseif ($item.url) {
            Invoke-WebRequest -UseBasicParsing -Uri $item.url -OutFile $target -TimeoutSec 120
        } else { throw ('No image returned for ' + $job.out) }
        Add-Type -AssemblyName System.Drawing
        $bitmap = [Drawing.Image]::FromFile($target)
        try { Write-Output ('Saved ' + $job.out + ' (' + $bitmap.Width + 'x' + $bitmap.Height + ')') } finally { $bitmap.Dispose() }
    }
    Copy-Item -LiteralPath $target -Destination (Join-Path $assetRoot $job.out) -Force
}
