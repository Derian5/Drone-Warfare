@tool
class_name SfxEntry
extends Resource

@export var id := ""
@export var stream: AudioStream
@export_range(-40, 12) var volume_db := -12.0
## Minimum seconds between two plays of this sound.
@export var min_gap := 0.05
@export var random_pitch := 0.0
