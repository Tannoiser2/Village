class_name FarmPanel
extends Control
## La plancia originale di una famiglia, disegnata nel pannello di sinistra: segnatempo sulle nuvole,
## grano nei campi, familiari nell'aia, cubi influenza sul muro di casa, segnalini del primo giocatore.

const D = preload("res://scripts/data/vl_data.gd")
## Dove stanno i cubi (coordinate della plancia 1024 x 1024): lungo il muro di casa, dopo moneta » cubo.
const CUBE_X := [478.0, 580.0, 682.0, 784.0]
const CUBE_Y := 652.0

var st: VLState
var seat := 0
var side := 200.0


func setup(state: VLState, s: int, sz: float) -> void:
	st = state
	seat = s
	side = sz
	custom_minimum_size = Vector2(sz, sz)
	size = Vector2(sz, sz)
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = _tip()


func _p(v: Vector2) -> Vector2:
	return v * (side / 1024.0)


func _tip() -> String:
	var pl: Dictionary = st.players[seat]
	var t := "Tempo della vita: %d passi al ponte." % (D.TIME_STEPS - int(pl["time"]))
	t += "\nGrano %d di %d." % [int(pl["grain"]), D.GRAIN_MAX]
	var c := []
	for k in D.CUBES:
		c.append("%s %d" % [D.cube_name(k), int(pl["cubes"][k])])
	t += "\nCubi: " + ", ".join(c) + "."
	return t


func _draw() -> void:
	if st == null:
		return
	var pl: Dictionary = st.players[seat]
	var key: String = D.COLORS[pl["color"]]["key"]
	var col: Color = D.COLORS[pl["color"]]["color"]
	var k := side / 1024.0
	draw_texture_rect(UI.tex("res://assets/farms/%s.jpg" % key), Rect2(Vector2.ZERO, Vector2(side, side)), false)
	var f: Font = UI.font_bold
	# grano nei campi
	var gt := UI.token("grain")
	for g in int(pl["grain"]):
		var c := _p(D.GRAIN_POS[g])
		var sz := Vector2(84, 128) * k
		draw_texture_rect(gt, Rect2(c - sz / 2.0, sz), false)
	# cubi influenza sul muro di casa
	var cs := maxf(13.0, 64.0 * k)
	for i in D.CUBES.size():
		var cc: String = D.CUBES[i]
		var n := int(pl["cubes"][cc])
		var ctr := _p(Vector2(CUBE_X[i], CUBE_Y))
		var r := Rect2(ctr - Vector2(cs, cs) / 2.0, Vector2(cs, cs))
		var cubec: Color = D.CUBE[cc]["color"]
		if n == 0:
			cubec = Color(cubec, 0.28)
		draw_rect(r.grow(1.5), Color(0.1, 0.05, 0.02, 0.85 if n > 0 else 0.3))
		draw_rect(r, cubec)
		draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.28)), Color(1, 1, 1, 0.18 if n > 0 else 0.06))
		var fs := int(maxf(12.0, cs * 0.82))
		var txt := str(n)
		var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var tp := ctr + Vector2(-w / 2.0, fs * 0.36)
		draw_string_outline(f, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0.12, 0.06, 0.02))
		draw_string(f, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#fff3dc"))
	# familiari nell'aia (con il numero della generazione)
	var mt := UI.tex("res://assets/ui/meeple_%s.png" % key)
	var fam := st.farm(seat)
	fam.sort_custom(func(a, b): return int(a["gen"]) < int(b["gen"]))
	var cols := 4 if fam.size() <= 8 else 5
	var cw := D.YARD.size.x / cols
	var ms := maxf(18.0, 104.0 * k)
	for i in fam.size():
		var r2 := i / cols
		var c2 := i % cols
		var ctr2 := _p(Vector2(D.YARD.position.x + cw * (c2 + 0.5), D.YARD.position.y + 62 + r2 * 122))
		draw_texture_rect(mt, Rect2(ctr2 - Vector2(ms, ms) / 2.0, Vector2(ms, ms)), false)
		var gs := str(int(fam[i]["gen"]))
		var fs2 := int(maxf(11.0, ms * 0.42))
		var w2 := f.get_string_size(gs, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x
		var tp2 := ctr2 + Vector2(-w2 / 2.0, fs2 * 0.55)
		draw_string_outline(f, tp2, gs, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, 3, Color(0.1, 0.05, 0.02))
		draw_string(f, tp2, gs, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, Color.WHITE)
	# segnatempo sulla nuvola
	var tc := _p(D.TIME_POS[int(pl["time"])])
	var rad := maxf(9.0, 44.0 * k)
	draw_circle(tc + Vector2(0, 2), rad + 2.5, Color(0, 0, 0, 0.35))
	draw_circle(tc, rad + 2.0, Color(0.1, 0.05, 0.02))
	draw_circle(tc, rad, col)
	draw_circle(tc - Vector2(rad, rad) * 0.25, rad * 0.45, Color(1, 1, 1, 0.22))
	if int(pl["deaths"]) > 0:
		draw_arc(tc, rad + 5.0, 0, TAU, 32, UI.RED, 3.0)
	# primo giocatore e prossimo primo giocatore
	var ts := 150.0 * k
	if st.first == seat:
		draw_texture_rect(UI.token("start"), Rect2(_p(Vector2(262, 190)) - Vector2(ts, ts) / 2.0, Vector2(ts, ts)), false)
	if st.next_owner == seat:
		draw_texture_rect(UI.token("next"), Rect2(_p(Vector2(430, 200)) - Vector2(ts, ts) / 2.0, Vector2(ts, ts)), false)
