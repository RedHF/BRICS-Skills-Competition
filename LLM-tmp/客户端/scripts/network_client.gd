class_name NetworkClient
extends Node

## Thin HTTP adapter. The client never computes an authoritative score when a
## server response is available; all puzzle, battle, choice, and settlement
## requests carry a session id and are accepted only after server validation.

signal request_finished(operation: String, ok: bool, payload: Dictionary, message: String)

@export var base_url := "http://127.0.0.1:8080"
var _next_request_id := 1
var _pending: Dictionary = {}

func _ready() -> void:
	base_url = str(ProjectSettings.get_setting("yanxia/server_url", base_url)).rstrip("/")

func request_json(operation: String, path: String, method: int, payload: Dictionary = {}) -> void:
	var request := HTTPRequest.new()
	request.timeout = 4.0
	add_child(request)
	var request_id := _next_request_id
	_next_request_id += 1
	_pending[request_id] = {"operation": operation, "request": request}
	request.request_completed.connect(_on_request_completed.bind(request_id))
	var headers := PackedStringArray(["Content-Type: application/json", "Accept: application/json"])
	var body := ""
	if not payload.is_empty():
		body = JSON.stringify(payload)
	var err := request.request(base_url + path, headers, method, body)
	if err != OK:
		_pending.erase(request_id)
		request.queue_free()
		request_finished.emit(operation, false, {}, "无法发起网络请求（错误码 %s）" % err)

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, request_id: int) -> void:
	var item: Dictionary = _pending.get(request_id, {})
	_pending.erase(request_id)
	var request = item.get("request")
	if is_instance_valid(request):
		request.queue_free()
	var operation := str(item.get("operation", "request"))
	var payload: Dictionary = {}
	var text := body.get_string_from_utf8()
	if not text.strip_edges().is_empty():
		var parsed = JSON.parse_string(text)
		if parsed is Dictionary:
			payload = parsed
	# Preserve the distinction between a reachable server rejecting a request
	# and a transport failure; gameplay only falls back on the latter.
	payload["_transport_ok"] = result == HTTPRequest.RESULT_SUCCESS
	var ok := result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300
	var message := ""
	if not ok:
		message = str(payload.get("error", payload.get("message", "服务器暂不可用（%s/%s）" % [result, response_code])))
	request_finished.emit(operation, ok, payload, message)

func create_player(player_id: String = "") -> void:
	var payload := {"display_name": "无名拓印师"}
	if not player_id.strip_edges().is_empty():
		payload["player_id"] = player_id.strip_edges()
	request_json("create_player", "/api/v1/players", HTTPClient.METHOD_POST, payload)

func get_player(player_id: String) -> void:
	request_json("get_player", "/api/v1/players/%s" % player_id.uri_encode(), HTTPClient.METHOD_GET)

func start_event(player_id: String, chapter_id: String, event_id: String) -> void:
	request_json("start_event", "/api/v1/events/%s/%s/start" % [chapter_id.uri_encode(), event_id.uri_encode()], HTTPClient.METHOD_POST, {"player_id": player_id})

func submit_puzzle(session_id: String, step_id: String, answer: String) -> void:
	request_json("submit_puzzle", "/api/v1/sessions/%s/puzzle" % session_id.uri_encode(), HTTPClient.METHOD_POST, {"step_id": step_id, "answer": answer})

func get_session(session_id: String) -> void:
	request_json("get_session", "/api/v1/sessions/%s" % session_id.uri_encode(), HTTPClient.METHOD_GET)

func submit_battle(session_id: String, input: Dictionary) -> void:
	request_json("submit_battle", "/api/v1/sessions/%s/battle" % session_id.uri_encode(), HTTPClient.METHOD_POST, input)

func submit_choice(session_id: String, action: String) -> void:
	var payload := {"action": action}
	if action.begins_with("forget:"):
		payload = {"action": "forget", "forget_memory_id": action.trim_prefix("forget:")}
	request_json("submit_choice", "/api/v1/sessions/%s/choice" % session_id.uri_encode(), HTTPClient.METHOD_POST, payload)

func settle(session_id: String) -> void:
	request_json("settle", "/api/v1/sessions/%s/finish" % session_id.uri_encode(), HTTPClient.METHOD_POST)
