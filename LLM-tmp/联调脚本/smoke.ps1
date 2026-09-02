param(
    [string]$BaseUrl = "http://127.0.0.1:8090"
)

$ErrorActionPreference = "Stop"
$headers = @{ "Content-Type" = "application/json" }
$playerId = "smoke_$(Get-Random)"

function Post-Json([string]$Path, [hashtable]$Body) {
    return Invoke-RestMethod -Method Post -Uri ($BaseUrl + $Path) -Headers $headers -Body ($Body | ConvertTo-Json -Depth 8)
}

$health = Invoke-RestMethod -Method Get -Uri ($BaseUrl + "/healthz")
if ($health.status -ne "ok") { throw "health check failed" }
$player = Post-Json "/api/v1/players" @{ player_id = $playerId; display_name = "联调玩家" }
$session = Post-Json "/api/v1/events/prologue/prologue_bridge/start" @{ player_id = $playerId }
$sid = $session.session_id
$puzzle = Post-Json "/api/v1/sessions/$sid/puzzle" @{ step_id = "bridge_trace"; answer = "平安"; action = "trace" }
$battle = Post-Json "/api/v1/sessions/$sid/battle" @{ duration_ms = 1000; waves_cleared = 1; hits_taken = 0; actions = @(@{ skill = "斗拱"; at_ms = 100 }) }
$choice = Post-Json "/api/v1/sessions/$sid/choice" @{ action = "keep" }
$settled = Post-Json "/api/v1/sessions/$sid/settle" @{}
$repeat = Post-Json "/api/v1/sessions/$sid/finish" @{}

[pscustomobject]@{
    health = $health.status
    puzzle_complete = $puzzle.complete
    battle_won = $battle.won
    choice_accepted = $choice.accepted
    settled = $settled.settled
    stars = $settled.result.stars
    ink_marks = $settled.player.ink_marks
    repeat_reason = $repeat.reason
} | ConvertTo-Json
