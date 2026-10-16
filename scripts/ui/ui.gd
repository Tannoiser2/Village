class_name UI
extends RefCounted
## Stile grafico di Village: pergamene, assi di legno, rosso mattone e verde prato del tabellone.
## Titoli in Uncial Antiqua (come i nomi sulle carte), testo in IM Fell English, numeri e pulsanti
## in Almendra.

const INK := Color("#3a2213")        # inchiostro sulla pergamena
const INK2 := Color("#6b4a2b")       # testo secondario
const BRICK := Color("#a3321f")      # rosso dei tetti
const MEADOW := Color("#4f7a22")     # verde prato
const SAND := Color("#f3e4c1")
const GOLD := Color("#d9a520")
const LIGHT := Color("#fff3dc")      # testo chiaro sul legno
const RED := Color("#a8231a")
const GREEN := Color("#2e6b25")
const DARK := Color("#24140a")

static var _tex := {}
static var font_title: Font
static var font_body: Font
static var font_bold: Font
static var font_heavy: Font
static var font_italic: Font


static func init_fonts() -> void:
	if font_title != null:
		return
	font_title = load("res://assets/fonts/UncialAntiqua-Regular.ttf")
	font_body = load("res://assets/fonts/IMFellEnglish-Regular.ttf")
	font_italic = load("res://assets/fonts/IMFellEnglish-Italic.ttf")
	font_bold = load("res://assets/fonts/Almendra-Bold.ttf")
	font_heavy = font_bold


static func tex(path: String) -> Texture2D:
	if not _tex.has(path):
		_tex[path] = load(path)
	return _tex[path]


static func token(name: String) -> Texture2D:
	return tex("res://assets/tokens/%s.png" % name)


static func villager(id: int) -> Texture2D:
	return tex("res://assets/cards/v%d.jpg" % id)


static func customer(ci: int) -> Texture2D:
	return tex("res://assets/cards/c%d.jpg" % VLData.CUSTOMERS[ci]["img"])


static func goal_tex(g: Array) -> Texture2D:
	return tex("res://assets/cards/%s%d.jpg" % ["gs" if g[0] == "s" else "gg", int(g[1])])


static func captain_tex(c: int) -> Texture2D:
	if c == 100:
		return villager(28)
	return tex("res://assets/cards/cap%d.jpg" % c)


static func pcolor(cid: int) -> Color:
	return VLData.COLORS[cid]["color"]


## Colore del giocatore leggibile sulla pergamena.
static func ink_of(cid: int) -> Color:
	match cid:
		1: return Color("#9a6f00")
		3: return Color("#7d7259")
		4: return Color("#575d57")
	return VLData.COLORS[cid]["color"].darkened(0.12)


static func ccolor(c: String) -> Color:
	return VLData.CUBE[c]["color"]


## Riquadro piatto (evidenziazioni, celle).
static func panel_style(bg: Color, border: Color, bw := 1, radius := 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(10)
	return sb


## Pergamena con i bordi strappati.
static func paper(dark := false, margin := 18.0) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = tex("res://assets/ui/parchment_dark.png" if dark else "res://assets/ui/parchment.png")
	sb.set_texture_margin_all(40)
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	sb.set_content_margin_all(margin)
	return sb


## Asse di legno: "wood", "wood_hover", "wood_dark", "brick", "meadow", "wood_off"…
static func plank(kind := "wood", margin := 12.0) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = tex("res://assets/ui/%s.png" % kind)
	sb.set_texture_margin_all(14)
	sb.content_margin_left = margin + 4
	sb.content_margin_right = margin + 4
	sb.content_margin_top = margin * 0.5
	sb.content_margin_bottom = margin * 0.5
	return sb


static func label(text: String, size := 20, col := INK, font: Font = null) -> Label:
	init_fonts()
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if font != null:
		l.add_theme_font_override("font", font)
	return l


static func title(text: String, size := 40, col := INK) -> Label:
	init_fonts()
	var l := label(text, size, col, font_title)
	if col.get_luminance() > 0.6:
		l.add_theme_color_override("font_outline_color", Color(0.15, 0.08, 0.03, 0.9))
		l.add_theme_constant_override("outline_size", 8)
	return l


static func wrap(text: String, size: int, width: float, col := INK, font: Font = null) -> Label:
	var l := label(text, size, col, font)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(width, 0)
	return l


static func icon_rect(t: Texture2D, sz: Vector2) -> TextureRect:
	var r := TextureRect.new()
	r.texture = t
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = sz
	r.size = sz
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Un cubetto colorato disegnato (per i costi e le risorse).
static func cube_icon(c: String, sz := 22.0) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(sz, sz)
	var col := ccolor(c) if VLData.CUBE.has(c) else Color("#8a8a8a")
	p.add_theme_stylebox_override("panel", panel_style(col, col.darkened(0.45), 2, 3))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## Icona e numero affiancati.
static func counter(t: Texture2D, n: int, sz := 30.0, col := INK) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 2)
	hb.add_child(icon_rect(t, Vector2(sz, sz)))
	hb.add_child(label(str(n), int(sz * 0.8), col, font_bold))
	return hb


static func button(text: String, w := 200.0, h := 54.0, size := 24) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, h)
	b.add_theme_font_size_override("font_size", size)
	return b


static func _skin(b: Button, base: String, hover: String) -> Button:
	b.add_theme_stylebox_override("normal", plank(base))
	b.add_theme_stylebox_override("hover", plank(hover))
	b.add_theme_stylebox_override("pressed", plank("wood_dark"))
	return b


## Pulsante principale (rosso mattone).
static func primary(b: Button) -> Button:
	return _skin(b, "brick", "brick_hover")


## Pulsante "prato" (azioni online, conferme secondarie, consigli dell'IA).
static func meadow(b: Button) -> Button:
	return _skin(b, "meadow", "meadow_hover")


static func selected(b: Button, kind := "meadow") -> Button:
	return _skin(b, kind, kind + "_hover")


static func plain(b: Button) -> Button:
	return _skin(b, "wood", "wood_hover")


static func make_theme() -> Theme:
	init_fonts()
	var th := Theme.new()
	th.default_font = font_body
	th.default_font_size = 21
	th.set_stylebox("normal", "Button", plank("wood"))
	th.set_stylebox("hover", "Button", plank("wood_hover"))
	th.set_stylebox("pressed", "Button", plank("wood_dark"))
	th.set_stylebox("disabled", "Button", plank("wood_off"))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", LIGHT)
	th.set_color("font_hover_color", "Button", Color.WHITE)
	th.set_color("font_pressed_color", "Button", Color("#ffd98a"))
	th.set_color("font_disabled_color", "Button", Color("#d8cfc0"))
	th.set_color("font_outline_color", "Button", Color(0.18, 0.09, 0.03, 0.85))
	th.set_constant("outline_size", "Button", 5)
	th.set_font("font", "Button", font_bold)
	th.set_font_size("font_size", "Button", 22)
	th.set_color("font_color", "Label", INK)
	th.set_stylebox("panel", "Panel", paper())
	th.set_stylebox("panel", "PanelContainer", paper())
	th.set_font("normal_font", "RichTextLabel", font_body)
	th.set_font("bold_font", "RichTextLabel", font_bold)
	th.set_font("italics_font", "RichTextLabel", font_italic)
	th.set_font_size("normal_font_size", "RichTextLabel", 20)
	th.set_font_size("bold_font_size", "RichTextLabel", 19)
	th.set_font_size("italics_font_size", "RichTextLabel", 20)
	th.set_color("default_color", "RichTextLabel", INK)
	th.set_font("font", "LineEdit", font_bold)
	th.set_font_size("font_size", "LineEdit", 24)
	th.set_color("font_color", "LineEdit", INK)
	th.set_color("font_placeholder_color", "LineEdit", Color(0.42, 0.29, 0.17, 0.6))
	th.set_color("caret_color", "LineEdit", INK)
	th.set_stylebox("normal", "LineEdit", panel_style(Color("#fbf1dc"), Color("#8a6a45"), 2, 6))
	th.set_stylebox("focus", "LineEdit", panel_style(Color("#fffaf0"), MEADOW, 3, 6))
	th.set_font("font", "TooltipLabel", font_body)
	th.set_font_size("font_size", "TooltipLabel", 20)
	th.set_color("font_color", "TooltipLabel", INK)
	th.set_stylebox("panel", "TooltipPanel", paper(false, 12))
	th.set_font("font", "CheckBox", font_bold)
	th.set_font_size("font_size", "CheckBox", 22)
	th.set_color("font_color", "CheckBox", INK)
	th.set_color("font_hover_color", "CheckBox", MEADOW)
	th.set_color("font_pressed_color", "CheckBox", INK)
	th.set_color("font_hover_pressed_color", "CheckBox", MEADOW)
	for k in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		th.set_stylebox(k, "CheckBox", StyleBoxEmpty.new())
	var sep := StyleBoxLine.new()
	sep.color = Color(0.42, 0.29, 0.17, 0.45)
	sep.thickness = 2
	th.set_stylebox("separator", "HSeparator", sep)
	return th
