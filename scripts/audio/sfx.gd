class_name Sfx
extends Node
## Plays sounds from an SfxLibrary resource (audio/sfx_library.tres) and the music track.
## Replace the .wav files in audio/sfx or point entries to new streams in the library.

@export var library: SfxLibrary

var muted := false:
	set(value):
		muted = value
		if _music != null:
			_music.stream_paused = value

var _entries := {}
var _last := {}
var _voices: Array = []
var _music: AudioStreamPlayer

func _ready() -> void:
	if library == null:
		return
	for entry in library.sounds:
		if entry != null and entry.stream != null:
			_entries[entry.id] = entry
	for i in range(maxi(1, library.max_voices)):
		var player = AudioStreamPlayer.new()
		add_child(player)
		_voices.append(player)
	if library.music != null:
		var stream = library.music
		if "loop" in stream:
			stream.loop = true
		_music = AudioStreamPlayer.new()
		_music.stream = stream
		_music.volume_db = library.music_volume_db
		add_child(_music)
		_music.play()
		_music.stream_paused = muted

func play(id: String) -> void:
	if muted or not _entries.has(id):
		return
	var entry: SfxEntry = _entries[id]
	var now = Time.get_ticks_msec() / 1000.0
	if now - float(_last.get(id, -100.0)) < entry.min_gap:
		return
	_last[id] = now
	for player in _voices:
		if not player.playing:
			player.stream = entry.stream
			player.volume_db = entry.volume_db
			player.pitch_scale = 1.0 + randf_range(-entry.random_pitch, entry.random_pitch)
			player.play()
			return
