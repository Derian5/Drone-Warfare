@tool
class_name SfxLibrary
extends Resource

@export var sounds: Array[SfxEntry] = []
@export var music: AudioStream
@export_range(-40, 6) var music_volume_db := -15.0
@export var max_voices := 8
