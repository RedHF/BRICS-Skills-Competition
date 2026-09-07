param([string]$BaseUrl = "http://127.0.0.1:8090")
$ErrorActionPreference = "Stop"
$playerId = "smoke_$(Get-Random)"
$authHeaders = @{}
function Post-Json([string]$Path, [hashtable]$Body) {
    Invoke-RestMethod -Method Post -Uri ($BaseUrl + $Path) -Headers $authHeaders -ContentType 'application/json; charset=utf-8' -Body ($Body | ConvertTo-Json -Depth 12)
}
$health = Invoke-RestMethod ($BaseUrl + '/healthz')
if ($health.status -ne 'ok') { throw 'health check failed' }
$player = Post-Json '/api/v1/auth/register' @{ username = $playerId; password = [guid]::NewGuid().ToString() }
$authHeaders = @{ Authorization = 'Bearer ' + $player.access_token }
$playerId = $player.player.id
$session = Post-Json '/api/v1/events/prologue/prologue_bridge/start' @{ player_id = $playerId }
$sid = $session.session_id
$strokes = @()
foreach ($stroke in $session.puzzle.steps[0].trace.strokes) {
    $points = [System.Collections.Generic.List[object]]::new()
    $points.Add(@($stroke[0][0], $stroke[0][1]))
    for ($j = 1; $j -lt $stroke.Count; $j++) {
        for ($k = 1; $k -le 50; $k++) {
            $fraction = $k / 50.0
            $x = $stroke[$j - 1][0] + $fraction * ($stroke[$j][0] - $stroke[$j - 1][0])
            $y = $stroke[$j - 1][1] + $fraction * ($stroke[$j][1] - $stroke[$j - 1][1])
            $points.Add(@($x, $y))
        }
    }
    $strokes += ,$points.ToArray()
}
$puzzle = Post-Json "/api/v1/sessions/$sid/puzzle" @{ step_id = 'bridge_trace'; strokes = $strokes }
if (-not $puzzle.complete) { throw 'trace validation failed' }
$choice = Post-Json "/api/v1/sessions/$sid/choice" @{ action = 'keep' }
$battle = Post-Json "/api/v1/sessions/$sid/battle" @{ duration_ms = 1000; actions = @(@{ skill = '斗拱'; at_ms = 0 }, @{ skill = '挥墨'; at_ms = 0 }, @{ skill = '挥墨'; at_ms = 500 }, @{ skill = '挥墨'; at_ms = 1000 }) }
$settled = Post-Json "/api/v1/sessions/$sid/finish" @{}
$repeat = Post-Json "/api/v1/sessions/$sid/finish" @{}
if (-not $battle.won -or -not $settled.settled -or $repeat.reason -ne 'already_settled') { throw 'settlement verification failed' }
$logout = Post-Json '/api/v1/auth/logout' @{}
[pscustomobject]@{ player = $playerId; trace = $puzzle.complete; choice = $choice.accepted; battle = $battle.won; stars = $settled.result.stars; repeat = $repeat.reason } | ConvertTo-Json
