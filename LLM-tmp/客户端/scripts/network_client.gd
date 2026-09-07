class_name NetworkClient
extends Node

var base_url := "http://127.0.0.1:8090"
var last_error := ""
var access_token := ""
var last_status := 0

func request_json(path: String, method: int = HTTPClient.METHOD_GET, payload: Dictionary = {}) -> Dictionary:
	last_status = 0
	var request := HTTPRequest.new()
	request.timeout = 10.0
	request.max_redirects = 0
	add_child(request)
	var body := JSON.stringify(payload) if method == HTTPClient.METHOD_POST else ""
	var headers := PackedStringArray(["Content-Type: application/json"])
	if not access_token.is_empty(): headers.append("Authorization: Bearer " + access_token)
	var error := request.request(base_url + path, headers, method, body)
	if error != OK:
		last_error = "无法发起请求：%s" % error
		request.queue_free()
		return {}
	var response: Array = await request.request_completed
	request.queue_free()
	if response[0] != HTTPRequest.RESULT_SUCCESS:
		last_error = "连接服务端失败（%s）。进度以服务端存档为准，请恢复连接后重试。" % response[0]
		return {}
	var parser := JSON.new()
	if parser.parse(response[3].get_string_from_utf8()) != OK or parser.data is not Dictionary:
		last_error = "服务端返回了无效 JSON。"
		return {}
	last_status = int(response[1])
	var data: Dictionary = parser.data
	if response[1] < 200 or response[1] >= 300:
		last_error = "请求失败（%s）：%s" % [response[1], str(data.error.message)]
		return {}
	last_error = ""
	return data
