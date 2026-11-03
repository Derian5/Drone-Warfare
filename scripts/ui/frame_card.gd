class_name FrameCard
extends Button
## Frame choice in the assembly editor (ui/editor/frame_card.tscn).

signal hovered(id: String, inside: bool)

var frame: FrameData

func setup(data: FrameData) -> void:
	frame = data
	%Picture.texture = data.icon
	%Name.text = data.display_name
	%Role.text = data.role
	mouse_entered.connect(func(): hovered.emit(frame.id, true))
	mouse_exited.connect(func(): hovered.emit(frame.id, false))

func refresh(selected: bool, available: bool, unlock_text: String) -> void:
	disabled = not available
	%Role.text = frame.role if available else unlock_text
	modulate = Color.WHITE if available else Color(1, 1, 1, 0.55)
	theme_type_variation = &"ModuleTileInstalled" if selected else &"ModuleTile"
	tooltip_text = "%s — %s\n%s" % [frame.display_name, frame.role, frame.description] if available else "%s\n%s" % [frame.display_name, unlock_text]
