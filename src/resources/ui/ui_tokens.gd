class_name UITokens
extends RefCounted
## Single source of truth for UI values.
## The theme resource is generated from these values by tools/ui/build_theme.gd.
## Keep gameplay and debug code out of this file.

# --- Palette: warm brown / brass, carried over from the original UI ---
const SCREEN := Color("140d0a")
const SHADE := Color(0.043, 0.027, 0.02, 0.72)
const PANEL := Color("291b13")
const RAISED := Color("3a2618")
const RAISED_HOVER := Color("45301d")
const PRESSED := Color("241710")
const SUNKEN := Color("1e130e")
const LINE := Color("543a27")
const BORDER := Color("c4914d")
const BORDER_SOFT := Color("6e4c31")
const TEXT := Color("ffe8c4")
const TEXT_DIM := Color("dcc5a2")
const TEXT_MUTED := Color("c4a880")
const ACCENT := Color("ffd17a")
const ACCENT_STRONG := Color("ffe1a3")
const SUCCESS := Color("bdd9a5")
const WARNING := Color("ffd08c")
const DANGER := Color("e08a72")
const PRIMARY_TEXT := Color("241710")
const SHADOW := Color(0, 0, 0, 0.42)
## HUD panels sit on busy pixel art; the extra shade keeps text readable.
const SHADOW_SOFT := Color(0, 0, 0, 0.28)
const TEXT_SHADOW := Color(0, 0, 0, 0.45)
## Effect tints: the vignette, the refused-action flash and the stamp flash kept
## their original warm values when they moved out of per-script Color() literals.
const VIGNETTE := Color("570a0b")
const REFUSE_TINT := Color("ffb8a8")
const STAMP_FLASH := Color("fff0ad")

# Order slips: the paper surface owns a separate, readable ink palette.
const PAPER := Color("ead7ad")
const PAPER_EDGE := Color("b38c57")
const INK := Color("352419")
const INK_MUTED := Color("705437")
const INK_SUCCESS := Color("3e5d3b")
const INK_WARNING := Color("8b3b28")

# --- Type scale: pixel font, integer multiples only ---
const FONT_BODY := 12
const FONT_TITLE := 24
const FONT_HERO := 36
const LINE_SEPARATION := 4

# --- Spacing (4px grid) ---
const SPACE_1 := 4
const SPACE_2 := 8
const SPACE_3 := 12
const SPACE_4 := 16
const SPACE_6 := 24
const SPACE_8 := 32

# --- Sizes ---
const CONTROL_HEIGHT := 28
const CONTROL_HEIGHT_SMALL := 20
const HEADER_HEIGHT := 32
const ROW_HEIGHT := 24
const TAB_HEIGHT := 24
const ICON_SMALL := 16
const ICON := 24
const SCROLLBAR_WIDTH := 4

# --- Shape ---
const RADIUS_BUTTON := 4
const RADIUS_PANEL := 6
const BORDER_PANEL := 2
const BORDER_CONTROL := 1
const FOCUS_EXPAND := 1
