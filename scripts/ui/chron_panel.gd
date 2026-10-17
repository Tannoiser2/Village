class_name ChronPanel
extends Control
## Le cronache del villaggio e le tombe anonime con il loro aspetto originale, nel pannello di destra:
## il libro stampato sul tabellone (2-4 giocatori) oppure la tessera grande (Locanda o 5 giocatori).
## Ogni familiare morto appare nella sua casella con il numero della generazione.

const D = preload("res://scripts/data/vl_data.gd")
const BOARD_K := 2048.0 / 2245.0          # pixel del tabellone base salvato (2048) / pixel originali
## Ritagli del tabellone base (pixel originali 2245) per le cronache e le tombe stampate.
const SMALL_CHRON := Rect2(1395, 1585, 605, 410)
const SMALL_GRAVES := Rect2(150, 1740, 330, 310)
## Ritaglio del libro nella tessera grande (1400 x 980).
const BIG_CHRON := Rect2(150, 95, 1150, 600)

var st: VLState
var width := 330.0
var chron_rect := Rect2()                 # dove si disegna il libro
var graves_rect := Rect2()
var extra_y := 0.0                        # riga sotto (Bardo, sepolture in mare)


func setup(state: VLState, w: float) -> void:
	st = state
	width = w
	mouse_filter = Control.MOUSE_FILTER_STOP
	# il libro a tutta larghezza, le tombe sotto (a destra il Bardo e le sepolture in mare)
	var src: Rect2 = BIG_CHRON if st.big_chron else SMALL_CHRON
	var h := w * src.size.y / src.size.x
	chron_rect = Rect2(0, 0, w, h)
	var gh := 124.0
	var gw := gh * (D.GRAVES_BIG_PX.x / D.GRAVES_BIG_PX.y if st.big_chron else SMALL_GRAVES.size.x / SMALL_GRAVES.size.y)
	graves_rect = Rect2(0, h + 6, gw, gh)
	extra_y = h + 6
	var hh := maxf(chron_rect.end.y, graves_rect.end.y)
	if _extra_lines().size() > 0:
		hh = maxf(hh, extra_y + 24.0 * _extra_lines().size())
	custom_minimum_size = Vector2(w, hh)
	size = custom_minimum_size
	tooltip_text = _tip()


func _extra_lines() -> Array:
	var out := []
	var bard := []
	for m in st.members:
		if m["loc"] == "bard":
			bard.append("%s %d" % [st.pname(m["owner"]), m["gen"]])
	if not bard.is_empty():
		out.append("Con il Bardo:")
		out.append(", ".join(bard))
	if st.port:
		var sea := []
		var free := 0
		for i in st.burials.size():
			if int(st.burials[i]) == -1:
				free += 1
		for m in st.members:
			if str(m["loc"]).begins_with("sea:"):
				sea.append("%s %d" % [st.pname(m["owner"]), m["gen"]])
		out.append("Sepolture in mare:")
		out.append(", ".join(sea) if not sea.is_empty() else "nessuna")
		out.append("libere %d" % free)
	return out


func _tip() -> String:
	var parts := []
	for sec in D.SECTIONS:
		var free := 0
		for v in st.chron[sec]:
			if int(v) == -1:
				free += 1
		parts.append("%s: %d %s" % [D.SECTION[sec]["name"], free, "libera" if free == 1 else "libere"])
	var gf := st.graves_free()
	parts.append("Tombe anonime: %d %s" % [gf, "libera" if gf == 1 else "libere"])
	return "\n".join(parts)


## Centro di una casella delle cronache nel disegno.
func _chron_pt(sec: String, i: int) -> Vector2:
	if st.big_chron:
		var q: Vector2 = D.CHRON_BIG_POS[sec][i]
		return chron_rect.position + (q - BIG_CHRON.position) * (chron_rect.size.x / BIG_CHRON.size.x)
	var q2: Vector2 = D.CHRON_SMALL_POS[sec][i]
	return chron_rect.position + (q2 - SMALL_CHRON.position) * (chron_rect.size.x / SMALL_CHRON.size.x)


func _grave_pt(i: int) -> Vector2:
	if st.big_chron:
		var q: Vector2 = D.GRAVES_BIG_POS[i]
		return graves_rect.position + q * (graves_rect.size.x / D.GRAVES_BIG_PX.x)
	var q2: Vector2 = D.GRAVES_SMALL_POS[i]
	return graves_rect.position + (q2 - SMALL_GRAVES.position) * (graves_rect.size.x / SMALL_GRAVES.size.x)


func _draw() -> void:
	if st == null:
		return
	var slot: float
	if st.big_chron:
		draw_texture_rect_region(UI.tex("res://assets/board/chron5.jpg"), chron_rect, BIG_CHRON)
		draw_texture_rect(UI.tex("res://assets/board/graves5.png"), graves_rect, false)
		slot = 84.0 * chron_rect.size.x / BIG_CHRON.size.x
	else:
		var bt := UI.tex("res://assets/board/board_base.jpg")
		draw_texture_rect_region(bt, chron_rect, Rect2(SMALL_CHRON.position * BOARD_K, SMALL_CHRON.size * BOARD_K))
		draw_texture_rect_region(bt, graves_rect, Rect2(SMALL_GRAVES.position * BOARD_K, SMALL_GRAVES.size * BOARD_K))
		slot = 74.0 * chron_rect.size.x / SMALL_CHRON.size.x
	draw_rect(chron_rect, Color(0.25, 0.14, 0.06), false, 2.0)
	draw_rect(graves_rect, Color(0.25, 0.14, 0.06), false, 2.0)
	# caselle coperte (meno giocatori)
	for sec in D.SECTIONS:
		for i in st.chron[sec].size():
			if int(st.chron[sec][i]) == -2:
				_cover(_chron_pt(sec, i), slot)
	for i in st.graves.size():
		if int(st.graves[i]) == -2:
			_cover(_grave_pt(i), slot)
	# familiari morti
	for m in st.members:
		var l := str(m["loc"])
		if l.begins_with("chron:"):
			var parts := l.split(":")
			_meeple(_chron_pt(parts[1], int(parts[2])), slot, m)
		elif l.begins_with("grave:"):
			_meeple(_grave_pt(int(l.substr(6))), slot * 0.8, m)
	# Bardo e sepolture in mare
	var lines := _extra_lines()
	var x0 := graves_rect.end.x + 10
	var y := extra_y + 18.0
	for t in lines:
		draw_string(UI.font_body, Vector2(x0, y), t, HORIZONTAL_ALIGNMENT_LEFT, width - x0, 17, UI.INK2)
		y += 24.0


func _cover(c: Vector2, slot: float) -> void:
	var r := Rect2(c - Vector2(slot, slot * 1.25) / 2.0, Vector2(slot, slot * 1.25))
	draw_rect(r, Color(0.16, 0.1, 0.05, 0.62))
	draw_line(r.position, r.end, Color(0.9, 0.8, 0.6, 0.5), 1.5)


func _meeple(c: Vector2, slot: float, m: Dictionary) -> void:
	var key: String = D.COLORS[st.players[m["owner"]]["color"]]["key"]
	var ms := slot * 1.15
	draw_texture_rect(UI.tex("res://assets/ui/meeple_%s.png" % key), Rect2(c - Vector2(ms, ms) / 2.0, Vector2(ms, ms)), false)
	var gs := str(int(m["gen"]))
	var fs := int(maxf(10.0, ms * 0.42))
	var w := UI.font_bold.get_string_size(gs, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var tp := c + Vector2(-w / 2.0, fs * 0.55)
	draw_string_outline(UI.font_bold, tp, gs, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0.1, 0.05, 0.02))
	draw_string(UI.font_bold, tp, gs, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
