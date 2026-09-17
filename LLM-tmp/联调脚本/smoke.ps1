param([string]$BaseUrl = "http://127.0.0.1:8090")
$ErrorActionPreference = "Stop"
function Post-Json([string]$Path, [hashtable]$Body) {
    Invoke-RestMethod -Method Post -Uri ($BaseUrl + $Path) -ContentType 'application/json; charset=utf-8' -Body ($Body | ConvertTo-Json -Depth 12)
}
$health = Invoke-RestMethod ($BaseUrl + '/healthz')
if ($health.status -ne 'ok') { throw 'health check failed' }
if ($health.content_version -ne 9) { throw 'requires content v9' }
$player = Post-Json '/api/v1/players' @{}
if ($player.player.completed_events.PSObject.Properties.Count -gt 0 -or $player.player.memory_ledger.Count -gt 0) { throw 'Use a fresh isolated test save; smoke does not overwrite existing progress.' }
$active = Invoke-RestMethod ($BaseUrl + '/api/v1/sessions')
if ($null -ne $active.session) { throw 'Use a fresh isolated test save; an event is already active.' }
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
$catalog = Invoke-RestMethod ($BaseUrl + '/api/v1/catalog')
$actions = [System.Collections.Generic.List[object]]::new()
$hp = [int]$session.battle.enemy_hp
$ready = @{'斗拱'=0; '挥墨'=0}
$at = 0
while ($hp -gt 0 -and $at -lt ([int]$session.battle.duration_sec * 1000)) {
    foreach ($skill in @('斗拱','挥墨')) {
        if ($at -lt $ready[$skill]) { continue }
        $spec = $catalog.skills.$skill
        $actions.Add(@{skill=$skill; at_ms=$at})
        $ready[$skill] = $at + [int]$spec.cooldown_ms
        $hp -= [int]$spec.damage
    }
    if ($hp -le 0) { break }
    $at += 500
}
$battle = Post-Json "/api/v1/sessions/$sid/battle" @{ duration_ms = $at + 1; actions = $actions.ToArray() }
$settled = Post-Json "/api/v1/sessions/$sid/finish" @{}
$repeat = Post-Json "/api/v1/sessions/$sid/finish" @{}
if (-not $battle.won -or -not $settled.settled -or $repeat.reason -ne 'already_settled') { throw 'settlement verification failed' }
[pscustomobject]@{ player = $playerId; trace = $puzzle.complete; choice = $choice.accepted; battle = $battle.won; stars = $settled.result.stars; repeat = $repeat.reason } | ConvertTo-Json
