class_name MobileSupport
extends RefCounted
## Single place that answers "is this a touch build?".
## Gameplay and UI keep reading the same InputMap actions; only the way the
## player produces them changes, so nothing downstream needs a second code path.

## Opt-in switch for desktop playtesting of the touch HUD.
const FORCE_ARGUMENT := "--touch-controls"

static var _forced := false
static var _forced_read := false


static func should_show_touch_controls() -> bool:
	if is_forced():
		return true
	return OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()


static func is_forced() -> bool:
	if not _forced_read:
		_forced_read = true
		for argument: String in OS.get_cmdline_user_args() + OS.get_cmdline_args():
			if argument == FORCE_ARGUMENT:
				_forced = true
				break
	return _forced


## Touch HUD replaces keycaps with plain wording, so on-screen hints stop
## telling phone players to press keys they do not have.
static func is_touch_ui() -> bool:
	return should_show_touch_controls()
