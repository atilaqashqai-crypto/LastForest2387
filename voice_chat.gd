extends Node
## In-game voice chat. Everyone in the match hears everyone (through the server).
## Mic -> 16 kHz mono -> 8-bit mu-law -> server -> other players.

const RATE := 16000
const CHUNK := 640             # samples per packet (40 ms)
const GAIN := 2.0
const VAD_LEVEL := 0.012       # mic level needed to start sending
const HANG_TIME := 0.5         # keep sending a little after you stop talking
const GEN_BUFFER := 0.4        # seconds of playback buffer
const MAX_BACKLOG := 0.22      # seconds; older audio is skipped to stay in sync
const MU := 255.0

var mic_on := true
var capture: AudioEffectCapture = null
var mic_player: AudioStreamPlayer = null
var mic_ready := false
var perm_asked := false
var perm_ok := false
var perm_timer := 0.0
var ratio := 3.0
var phase := 0.0
var acc := 0.0
var cnt := 0
var pending := PackedFloat32Array()
var hang := 0.0
var talk_timer := 0.0
var voices: Dictionary = {}
var dec_table := PackedFloat32Array()
var log_mu := 1.0
var ui: CanvasLayer = null
var mic_btn: Button = null
var talk_label: Label = null

func _ready() -> void:
	log_mu = log(1.0 + MU)
	dec_table.resize(256)
	for i in 256:
		var y := clampf((float(i) - 128.0) / 127.0, -1.0, 1.0)
		dec_table[i] = signf(y) * (pow(1.0 + MU, absf(y)) - 1.0) / MU

func _active() -> bool:
	return Network.is_online and Network.game_started and not Network.is_dedicated and multiplayer.multiplayer_peer != null

func _process(delta: float) -> void:
	var act := _active()
	if ui != null:
		ui.visible = act
	if not act:
		_stop_voices()
		return
	if ui == null:
		_build_ui()
	if not mic_ready:
		_setup_mic()
	_place_ui()
	_mic_tick(delta)
	_speaker_tick(delta)

# ---------------- UI ----------------
func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.layer = 50
	add_child(ui)
	mic_btn = Button.new()
	mic_btn.size = Vector2(150, 56)
	mic_btn.pressed.connect(_toggle_mic)
	ui.add_child(mic_btn)
	talk_label = Label.new()
	talk_label.add_theme_font_size_override("font_size", 20)
	ui.add_child(talk_label)
	_update_btn()

func _place_ui() -> void:
	var vp := get_viewport().get_visible_rect().size
	mic_btn.position = Vector2(vp.x * 0.5 - 235.0, 14.0)
	talk_label.position = Vector2(30.0, 290.0)

func _toggle_mic() -> void:
	mic_on = not mic_on
	_update_btn()

func _update_btn() -> void:
	mic_btn.text = "Mic: ON" if mic_on else "Mic: OFF"

# ---------------- microphone ----------------
func _has_permission() -> bool:
	if OS.get_name() != "Android":
		return true
	for p in OS.get_granted_permissions():
		if str(p).ends_with("RECORD_AUDIO"):
			return true
	return false

func _setup_mic() -> void:
	if not perm_asked:
		perm_asked = true
		if OS.get_name() == "Android" and not _has_permission():
			OS.request_permission("RECORD_AUDIO")
	if capture == null:
		var sil := AudioServer.get_bus_index("VoiceSilent")
		if sil == -1:
			AudioServer.add_bus()
			sil = AudioServer.bus_count - 1
			AudioServer.set_bus_name(sil, "VoiceSilent")
			AudioServer.set_bus_mute(sil, true)
		var mic := AudioServer.get_bus_index("VoiceMic")
		if mic == -1:
			AudioServer.add_bus()
			mic = AudioServer.bus_count - 1
			AudioServer.set_bus_name(mic, "VoiceMic")
			AudioServer.set_bus_send(mic, "VoiceSilent")
			var cap := AudioEffectCapture.new()
			cap.buffer_length = 0.25
			AudioServer.add_bus_effect(mic, cap)
		capture = AudioServer.get_bus_effect(mic, 0) as AudioEffectCapture
		ratio = float(AudioServer.get_mix_rate()) / float(RATE)
	if mic_player == null:
		mic_player = AudioStreamPlayer.new()
		mic_player.stream = AudioStreamMicrophone.new()
		mic_player.bus = "VoiceMic"
		add_child(mic_player)
	mic_player.play()
	perm_ok = _has_permission()
	mic_ready = true

func _mic_tick(delta: float) -> void:
	if capture == null:
		return
	# After the player taps "Allow", restart the microphone once.
	perm_timer -= delta
	if perm_timer <= 0.0:
		perm_timer = 2.0
		if not perm_ok and _has_permission():
			perm_ok = true
			mic_player.stop()
			mic_player.play()
	var avail := capture.get_frames_available()
	if avail <= 0:
		return
	var frames: PackedVector2Array = capture.get_buffer(avail)
	var level := 0.0
	for f in frames:
		acc += (f.x + f.y) * 0.5
		cnt += 1
		phase += 1.0
		if phase >= ratio:
			phase -= ratio
			var o := clampf(acc / float(maxi(cnt, 1)) * GAIN, -1.0, 1.0)
			acc = 0.0
			cnt = 0
			pending.append(o)
			level = maxf(level, absf(o))
	if level > VAD_LEVEL:
		hang = HANG_TIME
	else:
		hang = maxf(hang - delta, 0.0)
	while pending.size() >= CHUNK:
		var chunk := pending.slice(0, CHUNK)
		pending = pending.slice(CHUNK)
		if mic_on and hang > 0.0:
			_send_chunk(chunk)

func _enc(x: float) -> int:
	var v := clampf(x, -1.0, 1.0)
	var y := signf(v) * log(1.0 + MU * absf(v)) / log_mu
	return int(round(y * 127.0)) + 128

func _send_chunk(chunk: PackedFloat32Array) -> void:
	var bytes := PackedByteArray()
	bytes.resize(chunk.size())
	for i in chunk.size():
		bytes[i] = _enc(chunk[i])
	talk_timer = 0.3
	if multiplayer.is_server():
		_relay(multiplayer.get_unique_id(), bytes)
	else:
		_rpc_voice_up.rpc_id(1, bytes)

# ---------------- network ----------------
@rpc("any_peer", "unreliable")
func _rpc_voice_up(data: PackedByteArray) -> void:
	if multiplayer.is_server():
		_relay(multiplayer.get_remote_sender_id(), data)

func _relay(sender: int, data: PackedByteArray) -> void:
	for pid in multiplayer.get_peers():
		if pid != sender:
			_rpc_voice_down.rpc_id(pid, sender, data)
	if sender != multiplayer.get_unique_id() and not Network.is_dedicated:
		_play(sender, data)

@rpc("authority", "unreliable")
func _rpc_voice_down(sender: int, data: PackedByteArray) -> void:
	_play(sender, data)

# ---------------- playback ----------------
func _make_voice() -> Dictionary:
	var p := AudioStreamPlayer.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = GEN_BUFFER
	p.stream = gen
	add_child(p)
	p.play()
	return {"player": p, "pb": p.get_stream_playback(), "last": Time.get_ticks_msec()}

func _play(sender: int, data: PackedByteArray) -> void:
	if not _active():
		return
	var v = voices.get(sender)
	if v == null:
		v = _make_voice()
		voices[sender] = v
	var pb = v["pb"]
	if pb == null:
		return
	var avail: int = pb.get_frames_available()
	var total := int(GEN_BUFFER * RATE)
	if float(total - avail) / float(RATE) > MAX_BACKLOG:
		return
	var n := mini(data.size(), avail)
	var frames := PackedVector2Array()
	frames.resize(n)
	for i in n:
		var s := dec_table[data[i]]
		frames[i] = Vector2(s, s)
	pb.push_buffer(frames)
	v["last"] = Time.get_ticks_msec()

func _speaker_tick(delta: float) -> void:
	talk_timer = maxf(talk_timer - delta, 0.0)
	var now := Time.get_ticks_msec()
	var names := PackedStringArray()
	if talk_timer > 0.0:
		names.append("You")
	var gone: Array = []
	for id in voices.keys():
		var v = voices[id]
		var age: int = now - int(v["last"])
		if age < 400:
			var info = Network.players.get(int(id), {})
			names.append(str(info.get("name", "Player")))
		elif age > 30000:
			gone.append(id)
	for id2 in gone:
		var vv = voices[id2]
		if is_instance_valid(vv["player"]):
			vv["player"].queue_free()
		voices.erase(id2)
	talk_label.text = ("Talking: " + ", ".join(names)) if names.size() > 0 else ""

func _stop_voices() -> void:
	if voices.is_empty():
		return
	for id in voices.keys():
		var v = voices[id]
		if is_instance_valid(v["player"]):
			v["player"].queue_free()
	voices.clear()
	pending = PackedFloat32Array()
