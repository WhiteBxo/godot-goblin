extends CanvasLayer
## Full-screen night tint for the settlement. The host map decides when it shows.

func set_night(night: bool) -> void:
	visible = night
