class_name AudioService
extends Node
## Sound effects and music. Call the static functions from anywhere; they do nothing when no
## AudioService node exists (headless tests). Music loop points come from the audio manifest because the
## raw WAVs carry none.

static var instance: AudioService

const SFX_VOICES := 10
const MUSIC_FADE := 0.6

var master := 1.0
var sfx_volume := 1.0
var music_volume := 0.8
var _voices: Array[AudioStreamPlayer] = []
var _next_voice := 0
var _music: Array[AudioStreamPlayer] = []
var _music_index := 0
var _current_music := ""
var _streams := {}
var _base_music_pitch := 1.0
var played: Array[String] = []


func _ready() -> void:
	instance = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	for _i in SFX_VOICES:
		var voice := AudioStreamPlayer.new()
		voice.bus = "Master"
		add_child(voice)
		_voices.append(voice)
	for _i in 2:
		var player := AudioStreamPlayer.new()
		player.bus = "Master"
		add_child(player)
		_music.append(player)


func _exit_tree() -> void:
	if instance == self:
		instance = null


static func sfx(name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if instance != null:
		instance._play_sfx(name, volume_db, pitch)


static func music(name: String) -> void:
	if instance != null:
		instance._play_music(name)


static func stop_music() -> void:
	if instance != null:
		instance._play_music("")


static func music_pitch(pitch: float) -> void:
	if instance != null:
		for player in instance._music:
			player.pitch_scale = pitch


static func current_music() -> String:
	return instance._current_music if instance != null else ""


func _load_stream(entry: Dictionary, is_music: bool) -> AudioStream:
	var path := "res://assets/audio/" + String(entry["file"])
	if not _streams.has(path):
		var stream := load(path) as AudioStreamWAV
		if stream != null and is_music:
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			stream.loop_begin = int(entry["loop_begin"])
			stream.loop_end = int(entry["loop_end"])
		_streams[path] = stream
	return _streams[path]


func _play_sfx(name: String, volume_db: float, pitch: float) -> void:
	played.append(name)
	if played.size() > 64:
		played.pop_front()
	var entry: Dictionary = Db.audio_manifest()["sfx"].get(name, {})
	if entry.is_empty() or _voices.is_empty():
		return
	var voice := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	voice.stream = _load_stream(entry, false)
	voice.volume_db = float(entry["volume_db"]) + volume_db + linear_to_db(maxf(0.0001, master * sfx_volume))
	voice.pitch_scale = pitch
	voice.play()


func _play_music(name: String) -> void:
	if name == _current_music:
		return
	_current_music = name
	var old := _music[_music_index]
	_music_index = 1 - _music_index
	var fresh := _music[_music_index]
	var tween := create_tween().set_parallel(true)
	if old.playing:
		tween.tween_property(old, "volume_db", -60.0, MUSIC_FADE)
		tween.tween_callback(old.stop).set_delay(MUSIC_FADE)
	if name == "":
		return
	var entry: Dictionary = Db.audio_manifest()["music"].get(name, {})
	if entry.is_empty():
		return
	fresh.stream = _load_stream(entry, true)
	fresh.pitch_scale = 1.0
	fresh.volume_db = -60.0
	fresh.play()
	tween.tween_property(fresh, "volume_db", float(entry["volume_db"]) + linear_to_db(maxf(0.0001, master * music_volume)), MUSIC_FADE)
