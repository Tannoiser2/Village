class_name Board3D
extends Node3D
## Il villaggio sul tavolo: tabellone (con Locanda, Birrificio e Porto quando servono), le fattorie dei
## giocatori, i familiari (i meeple del modulo TTS, con il numero della generazione), cubi, segnalini,
## clienti, navi. Due modi:
## - 3D: trascina per ruotare, rotella o pizzico per lo zoom, tasto destro (o Maiusc+trascina) per spostare;
## - 2D: vista dall'alto piatta (telecamera ortogonale, familiari sdraiati), trascina per spostare.
## Clic sugli anelli luminosi per scegliere.

signal target_clicked(key: String)
signal target_hovered(key: String)

const D = preload("res://scripts/data/vl_data.gd")
const HALF := 11.225                # metà del tabellone in unità (2245 px / 100)
const FS := 6.0                     # lato di una fattoria
const MEEPLE_SCALE := 0.47
const TOP := 0.012                  # altezza dei pezzi appoggiati sul tabellone

var eng: VLEngine
var st: VLState
var cam: Camera3D
var yaw := 0.0
var pitch := 56.0
var dist := 31.0
var focus := Vector3(0, 0, 4.6)
var _yaw_t := 0.0
var _pitch_t := 56.0
var _dist_t := 31.0
var _focus_t := Vector3(0, 0, 4.6)
var flat := false                   # vista 2D

var meeple_mesh: Mesh
var lay_mesh: Mesh
var ship_mesh: Mesh
var gen_tex := {}
var meeples := {}                   # id -> Node3D
var meeple_at := {}                 # id -> Vector3 (ultima destinazione)
var ships := {}                     # posto -> Node3D
var dyn: Node3D                     # pezzi ricostruiti a ogni aggiornamento
var targets := {}
var rings := {}
var hover_key := ""
var _drag := false
var _drag_moved := 0.0
var _pan := false
var _touches := {}
var _pinch_d := 0.0
var _t := 0.0
var mats := {}
var farm_center := {}               # posto -> Vector3
var chron_tile := {}                # dove stanno le cronache grandi: {"pos","size"} e le tombe
var graves_tile := {}


static func px(p: Vector2) -> Vector3:
	return Vector3((p.x - D.BOARD_PX / 2.0) / 100.0, 0.0, (p.y - D.BOARD_PX / 2.0) / 100.0)


func _ready() -> void:
	st = eng.st
	meeple_mesh = load("res://assets/models/meeple.obj")
	lay_mesh = load("res://assets/models/meeple_lay.obj")
	ship_mesh = load("res://assets/models/ship.obj")
	for g in 4:
		gen_tex[g + 1] = load("res://assets/models/gen%d.jpg" % (g + 1))
	_build_env()
	_build_table()
	_build_board()
	_build_farms()
	dyn = Node3D.new()
	add_child(dyn)
	for m in st.members:
		var node := _make_meeple(m)
		node.visible = false
		add_child(node)
		meeples[m["id"]] = node
	if st.port:
		for s in st.n:
			var sh := _make_ship(s)
			add_child(sh)
			ships[s] = sh
	_apply_cam()
	refresh()


func _process(delta: float) -> void:
	_t += delta
	var k := minf(1.0, delta * 9.0)
	yaw = lerpf(yaw, _yaw_t, k)
	pitch = lerpf(pitch, _pitch_t, k)
	dist = lerpf(dist, _dist_t, k)
	focus = focus.lerp(_focus_t, k)
	_apply_cam()
	var pulse := 0.7 + 0.3 * sin(_t * 5.0)
	for key in rings:
		var r: MeshInstance3D = rings[key]
		var s := (1.25 if key == hover_key else 1.0) * (0.95 + 0.08 * sin(_t * 5.0))
		r.scale = Vector3(s, 1, s)
		var m: StandardMaterial3D = r.material_override
		m.albedo_color.a = pulse


# ================================================================== scena

func _build_env() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var pm := PanoramaSkyMaterial.new()
	pm.panorama = load("res://assets/env/sky.jpg")
	pm.energy_multiplier = 0.9
	sky.sky_material = pm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#d8c8a8")
	e.ambient_light_energy = 0.32
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	e.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_energy = 0.78
	sun.light_color = Color("#fff0d6")
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 70.0
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-35, 150, 0)
	fill.light_energy = 0.25
	fill.light_color = Color("#c8d8ff")
	add_child(fill)
	cam = Camera3D.new()
	cam.fov = 42.0
	cam.far = 300.0
	add_child(cam)
	cam.current = true


func _build_table() -> void:
	var t := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(78, 1.0, 64)
	t.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/env/table.jpg")
	m.uv1_scale = Vector3(3, 2, 1)
	m.roughness = 0.75
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	t.material_override = m
	t.position = Vector3(2, -0.62, 6)
	add_child(t)


func _tile(tex_path: String, w: float, h: float, pos: Vector3, thick := 0.08, edge := Color("#4a2c14")) -> Node3D:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w, thick, h)
	body.mesh = bm
	body.material_override = _mat(edge, 0.9)
	body.position.y = -thick / 2.0
	root.add_child(body)
	var top := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(w, h)
	top.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(tex_path)
	mat.roughness = 1.0
	mat.metallic_specular = 0.0
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if tex_path.ends_with(".png"):
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = 0.5
		body.visible = false
	top.material_override = mat
	top.position.y = 0.002
	root.add_child(top)
	root.position = pos
	add_child(root)
	return root


func _build_board() -> void:
	var name := ("innport" if st.port else "inn") if st.inn else ("port" if st.port else "base")
	_tile("res://assets/board/board_%s.jpg" % name, D.BOARD_PX / 100.0, D.BOARD_PX / 100.0, Vector3.ZERO, 0.16)
	if st.big_chron:
		if st.inn:
			# cronache e tombe nuove sotto il tabellone (Locanda e Birrificio coprono quelle stampate)
			chron_tile = {"pos": Vector3(HALF + 4.9, 0.0, -1.2), "size": Vector2(8.4, 8.4 * 980.0 / 1400.0)}
			graves_tile = {"pos": Vector3(HALF + 2.6, 0.0, 4.6), "size": Vector2(3.4, 3.4 * 512.0 / 406.0)}
		else:
			# 5 giocatori senza Locanda: le tessere nuove coprono quelle del tabellone
			chron_tile = {"pos": px(Vector2(1700, 1790)) + Vector3(0, 0.03, 0), "size": Vector2(8.6, 8.6 * 980.0 / 1400.0)}
			graves_tile = {"pos": px(Vector2(300, 1880)) + Vector3(0, 0.03, 0), "size": Vector2(3.6, 3.6 * 512.0 / 406.0)}
		_tile("res://assets/board/chron5.jpg", chron_tile["size"].x, chron_tile["size"].y, chron_tile["pos"], 0.05)
		_tile("res://assets/board/graves5.png", graves_tile["size"].x, graves_tile["size"].y, graves_tile["pos"], 0.05)


func _build_farms() -> void:
	var nn := st.n
	for s in nn:
		var x := (float(s) - (nn - 1) / 2.0) * (FS + 0.8)
		var c := Vector3(x, 0, HALF + 0.9 + FS / 2.0)
		farm_center[s] = c
		var key: String = D.COLORS[st.players[s]["color"]]["key"]
		_tile("res://assets/farms/%s.jpg" % key, FS, FS, c, 0.07)
		var nm := Label3D.new()
		nm.text = st.players[s]["name"]
		nm.font = UI.font_title if UI.font_title != null else null
		nm.font_size = 96
		nm.pixel_size = 0.006
		nm.outline_size = 18
		nm.modulate = D.COLORS[st.players[s]["color"]]["color"].lightened(0.25)
		nm.outline_modulate = Color(0.12, 0.06, 0.02)
		nm.rotation_degrees = Vector3(-90, 0, 0)
		nm.position = c + Vector3(0, 0.03, -FS / 2.0 - 0.32)
		add_child(nm)


func farm_pos(s: int, p: Vector2) -> Vector3:
	return farm_center[s] + Vector3((p.x / 1024.0 - 0.5) * FS, 0, (p.y / 1024.0 - 0.5) * FS)


func _mat(c: Color, rough := 0.55) -> StandardMaterial3D:
	var key := "%s_%f" % [c.to_html(), rough]
	if mats.has(key):
		return mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	mats[key] = m
	return m


func _tex_mat(path: String, alpha := true) -> StandardMaterial3D:
	var key := "tex_" + path
	if mats.has(key):
		return mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(path)
	m.roughness = 0.9
	if alpha:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.4
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mats[key] = m
	return m


# ================================================================== pezzi

func _make_meeple(m: Dictionary) -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = meeple_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = gen_tex[int(m["gen"])]
	mat.albedo_color = D.COLORS[st.players[m["owner"]]["color"]]["color"]
	mat.roughness = 0.6
	mi.material_override = mat
	mi.scale = Vector3.ONE * MEEPLE_SCALE
	root.add_child(mi)
	return root


func _set_lying(node: Node3D, lying: bool) -> void:
	var mi: MeshInstance3D = node.get_node("Body")
	var want: Mesh = lay_mesh if lying else meeple_mesh
	if mi.mesh != want:
		mi.mesh = want


func _make_ship(s: int) -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = ship_mesh
	mi.material_override = _mat(D.COLORS[st.players[s]["color"]]["color"], 0.5)
	mi.scale = Vector3.ONE * 0.75
	mi.position.y = 0.3
	root.add_child(mi)
	return root


func _cube(c: String, pos: Vector3, sz := 0.17) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(sz, sz, sz)
	mi.mesh = bm
	mi.material_override = _mat(D.CUBE[c]["color"], 0.5)
	mi.position = pos + Vector3(0, sz / 2.0, 0)
	mi.rotation.y = fmod(pos.x * 7.3 + pos.z * 3.1, 1.0)
	dyn.add_child(mi)


func _disc(pos: Vector3, c: Color, r := 0.15, h := 0.08) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 20
	mi.mesh = cm
	mi.material_override = _mat(c, 0.35)
	mi.position = pos + Vector3(0, h / 2.0, 0)
	dyn.add_child(mi)
	return mi


func _quad(tex_path: String, pos: Vector3, w: float, h: float, alpha := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w, 0.03, h)
	mi.mesh = bm
	mi.material_override = _tex_mat(tex_path, alpha)
	mi.position = pos + Vector3(0, 0.02, 0)
	dyn.add_child(mi)
	return mi


func _label(text: String, pos: Vector3, size := 64, col := Color("#fff2c0")) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = UI.font_bold
	l.font_size = size
	l.pixel_size = 0.006
	l.outline_size = 14
	l.modulate = col
	l.outline_modulate = Color(0.15, 0.07, 0.02)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.position = pos
	dyn.add_child(l)
	return l


# ================================================================== aggiornamento

## Offset per più pezzi nello stesso posto (in riga, a zig-zag).
static func _spread(i: int, k: int, step := 0.42) -> Vector3:
	if k <= 1:
		return Vector3.ZERO
	var x := (float(i) - (k - 1) / 2.0) * step
	return Vector3(x, 0, (0.12 if i % 2 == 1 else -0.12))


func refresh() -> void:
	if st == null:
		return
	for c in dyn.get_children():
		c.queue_free()
	_refresh_meeples()
	_refresh_spaces()
	_refresh_market()
	_refresh_farms()
	_refresh_markers()
	if st.port:
		_refresh_port()


func member_target(m: Dictionary, idx: int, cnt: int) -> Dictionary:
	var l: String = m["loc"]
	var s: int = m["owner"]
	var lying := flat
	var p := Vector3.ZERO
	var vis := true
	if l == "farm":
		var cols := 4
		var r := idx / cols
		var c := idx % cols
		p = farm_pos(s, Vector2(D.YARD.position.x + 45 + c * 85, D.YARD.position.y + 60 + r * 110))
	elif l.begins_with("craft:"):
		p = px(D.CRAFT[l.substr(6)]["pos"]) + _spread(idx, cnt)
	elif l.begins_with("council:"):
		p = px(D.COUNCIL_POS[int(l.substr(8)) - 1]) + _spread(idx, cnt, 0.3)
	elif l.begins_with("city:"):
		p = px(D.CITY[l.substr(5)]["pos"]) + Vector3(-0.15, 0, 0.35) + _spread(idx, cnt, 0.36)
	elif l.begins_with("church:"):
		p = px(D.WINDOW_POS[int(l.substr(7))]) + _spread(idx, cnt, 0.3)
	elif l == "inn":
		p = px(Vector2(1468, 1926)) + _spread(idx, cnt, 0.36)
	elif l.begins_with("mission:"):
		p = px(D.SEA[l.substr(8)]["mpos"])
	elif l.begins_with("chron:"):
		var parts := l.split(":")
		p = chron_pos(parts[1], int(parts[2]))
		lying = true
	elif l.begins_with("grave:"):
		p = grave_pos(int(l.substr(6)))
		lying = true
	elif l.begins_with("sea:"):
		p = px(D.BURIAL_POS[int(l.substr(4))])
		lying = true
	elif l == "bard":
		var k := 0
		for o in st.members:
			if o["loc"] == "bard" and o["id"] < m["id"]:
				k += 1
		p = (chron_tile.get("pos", px(Vector2(1700, 2060))) if st.big_chron else px(Vector2(1700, 2060))) + Vector3(-1.5 + k * 0.5, 0, 2.2 if st.big_chron else 0.0)
		lying = true
	else:
		vis = false
	return {"pos": p + Vector3(0, TOP, 0), "lying": lying, "vis": vis}


func chron_pos(sec: String, i: int) -> Vector3:
	if st.big_chron:
		var q: Vector2 = D.CHRON_BIG_POS[sec][i]
		var sz: Vector2 = chron_tile["size"]
		return chron_tile["pos"] + Vector3((q.x / D.CHRON_BIG_PX.x - 0.5) * sz.x, 0.03, (q.y / D.CHRON_BIG_PX.y - 0.5) * sz.y)
	return px(D.CHRON_SMALL_POS[sec][i])


func grave_pos(i: int) -> Vector3:
	if st.big_chron:
		var q: Vector2 = D.GRAVES_BIG_POS[i]
		var sz: Vector2 = graves_tile["size"]
		return graves_tile["pos"] + Vector3((q.x / D.GRAVES_BIG_PX.x - 0.5) * sz.x, 0.03, (q.y / D.GRAVES_BIG_PX.y - 0.5) * sz.y)
	return px(D.GRAVES_SMALL_POS[i])


func _refresh_meeples() -> void:
	var groups := {}
	for m in st.members:
		var key: String = str(m["loc"])
		if key == "farm":
			key = "farm%d" % m["owner"]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(m["id"])
	for key in groups:
		var ids: Array = groups[key]
		for i in ids.size():
			var m: Dictionary = st.members[ids[i]]
			var node: Node3D = meeples[m["id"]]
			var tg := member_target(m, i, ids.size())
			node.visible = tg["vis"]
			if not tg["vis"]:
				meeple_at.erase(m["id"])
				continue
			_set_lying(node, tg["lying"])
			var to: Vector3 = tg["pos"]
			if tg["lying"]:
				node.rotation_degrees = Vector3(0, 0, 0)
			else:
				node.rotation_degrees = Vector3(0, 0, 0)
			if not meeple_at.has(m["id"]) or Engine.is_editor_hint():
				node.position = to
			elif (meeple_at[m["id"]] as Vector3).distance_to(to) > 0.01:
				var tw := create_tween()
				var from := node.position
				var mid := (from + to) / 2.0 + Vector3(0, 0.9, 0)
				tw.tween_property(node, "position", mid, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
				tw.tween_property(node, "position", to, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
			meeple_at[m["id"]] = to


func _refresh_spaces() -> void:
	for sp in D.SPACES:
		if not st.space_active(sp):
			continue
		var arr: Array = st.spaces[sp]
		var c0 := px(D.SPACE[sp]["pos"])
		var k := arr.size()
		var cols := mini(4, k)
		for i in k:
			var r := i / 4
			var c := i % 4
			var off := Vector3((float(c) - (cols - 1) / 2.0) * 0.24, 0, (float(r) - 0.5) * 0.24)
			_cube(str(arr[i]), c0 + off + Vector3(0, TOP, 0))
	# sacchetto nero della chiesa
	var bag := st.bag_members().size()
	if bag > 0:
		_label("%d nel sacchetto" % bag, px(D.BAG_POS) + Vector3(0, 0.6, 0), 52)


func _refresh_market() -> void:
	for i in st.front_n:
		if st.front[i] >= 0:
			_quad("res://assets/cards/c%d.jpg" % D.CUSTOMERS[st.front[i]]["img"], px(D.MARKET_FRONT_POS[i]), 1.0, 1.0, false)
	for i in 5:
		if st.queue[i] >= 0:
			_quad("res://assets/cards/c%d.jpg" % D.CUSTOMERS[st.queue[i]]["img"], px(D.MARKET_QUEUE_POS[i]), 0.95, 0.95, false)
	if st.pile.size() > 0:
		_quad("res://assets/cards/c_back.jpg", px(Vector2(1080, 420)), 0.9, 0.9, false)
		_label(str(st.pile.size()), px(Vector2(1080, 420)) + Vector3(0, 0.4, 0), 48)


func _refresh_farms() -> void:
	for s in st.n:
		var pl: Dictionary = st.players[s]
		var col: Color = D.COLORS[pl["color"]]["color"]
		# segnatempo
		var tp := farm_pos(s, D.TIME_POS[int(pl["time"])])
		_disc(tp + Vector3(0, TOP, 0.12), col, 0.2, 0.12)
		# grano
		for g in int(pl["grain"]):
			_quad("res://assets/tokens/grain.png", farm_pos(s, D.GRAIN_POS[g]), 0.45, 0.62)
		# merci, monete e cubi sotto la fattoria
		var row: Vector3 = farm_center[s] + Vector3(-FS / 2.0 + 0.4, 0, FS / 2.0 + 0.55)
		var x := 0.0
		var items := []
		items.append(["coin", int(pl["coins"])])
		for g in ["horse", "ox", "plow", "wagon", "scroll", "beer", "cocoa", "tea"]:
			if int(pl["goods"][g]) > 0:
				items.append([g, int(pl["goods"][g])])
		for it in items:
			var p := row + Vector3(x, 0, 0)
			_quad("res://assets/tokens/%s.png" % it[0], p, 0.62, 0.46 if it[0] != "coin" else 0.62)
			_label(str(it[1]), p + Vector3(0.28, 0.35, 0.2), 46)
			x += 0.78
		var row2: Vector3 = farm_center[s] + Vector3(-FS / 2.0 + 0.4, 0, FS / 2.0 + 1.3)
		var x2 := 0.0
		for c in D.CUBES:
			var k := int(pl["cubes"][c])
			for j in mini(k, 6):
				_cube(c, row2 + Vector3(x2 + (j % 3) * 0.19, 0, (j / 3) * 0.19))
			if k > 0:
				_label(str(k), row2 + Vector3(x2 + 0.25, 0.4, 0.25), 44)
				x2 += 0.9
		# primo giocatore e prossimo primo giocatore
		if st.first == s:
			_quad("res://assets/tokens/start.png", farm_center[s] + Vector3(-FS / 2.0 + 0.55, 0.02, -FS / 2.0 + 0.55), 0.85, 0.85)
		if st.next_owner == s:
			_quad("res://assets/tokens/next.png", farm_center[s] + Vector3(FS / 2.0 - 0.55, 0.02, -FS / 2.0 + 0.55), 0.7, 0.7)


func _refresh_markers() -> void:
	# prestigio
	var at := {}
	for s in st.n:
		var pp: int = st.players[s]["pp"]
		var k := posmod(pp, 80)
		var cnt: int = at.get(k, 0)
		at[k] = cnt + 1
		var p := px(D.track_pos(pp)) + Vector3(0, TOP + cnt * 0.085, 0)
		_disc(p, D.COLORS[st.players[s]["color"]]["color"], 0.17, 0.08)
		if pp >= 80:
			_label("+80", p + Vector3(0, 0.45, 0), 40)
	# segnalini sulle città
	if not st.port:
		for c in D.CITIES:
			var k2 := 0
			for s in st.n:
				if c in st.players[s]["cities"]:
					_disc(px(D.CITY[c]["pos"]) + Vector3(0.45, TOP, -0.35 + k2 * 0.2), D.COLORS[st.players[s]["color"]]["color"], 0.12, 0.07)
					k2 += 1
	# prossimo primo giocatore ancora libero
	if st.next_owner < 0:
		_quad("res://assets/tokens/next.png", px(D.NEXT_POS), 0.55, 0.55)


func _refresh_port() -> void:
	var by_node := {}
	for s in st.n:
		var at: String = st.players[s]["ship"]["at"]
		var k: int = by_node.get(at, 0)
		by_node[at] = k + 1
		var p := px(D.SEA[at]["pos"]) + Vector3(-0.35 + k * 0.35, TOP, 0.2 * k)
		var sh: Node3D = ships[s]
		if sh.position.distance_to(p) > 0.01:
			var tw := create_tween()
			tw.tween_property(sh, "position", p, 0.5).set_trans(Tween.TRANS_SINE)
		sh.visible = true
	for isl in ["CH", "CO", "TE"]:
		var info: Dictionary = D.SEA[isl]
		var left := st.stack_left(info["stack"])
		if left > 0:
			_quad("res://assets/tokens/%s.png" % info["stack"], px(info["spos"]), 0.6, 0.5)
			_label(str(left), px(info["spos"]) + Vector3(0.3, 0.4, 0.2), 44)


# ================================================================== bersagli cliccabili

func set_targets(t: Dictionary) -> void:
	for k in rings:
		rings[k].queue_free()
	rings.clear()
	targets = t
	hover_key = ""
	for k in t:
		var r := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.36
		tm.outer_radius = 0.48
		r.mesh = tm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(1.0, 0.86, 0.35, 0.95)
		m.emission_enabled = true
		m.emission = Color(1.0, 0.8, 0.3)
		m.emission_energy_multiplier = 2.2
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		r.material_override = m
		r.position = t[k] + Vector3(0, 0.1, 0)
		add_child(r)
		rings[k] = r


func _pick(pos: Vector2) -> String:
	var best := ""
	var bd := 44.0
	for k in targets:
		var p3: Vector3 = targets[k]
		if cam.is_position_behind(p3):
			continue
		var sp := cam.unproject_position(p3)
		var dd := sp.distance_to(pos)
		if dd < bd:
			bd = dd
			best = k
	return best


func space_pos(sp: String) -> Vector3:
	return px(D.SPACE[sp]["pos"])


func sea_pos(node: String) -> Vector3:
	return px(D.SEA[node]["pos"])


func member_pos(id: int) -> Vector3:
	return meeple_at.get(id, Vector3.ZERO)


# ================================================================== telecamera

func _apply_cam() -> void:
	if cam == null:
		return
	if flat:
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = dist * 0.82
		cam.position = focus + Vector3(0, 60, 0)
		cam.look_at(focus, Vector3(0, 0, -1))
		return
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	var p := deg_to_rad(pitch)
	var yw := deg_to_rad(yaw)
	var off := Vector3(sin(yw) * cos(p), sin(p), cos(yw) * cos(p)) * dist
	cam.position = focus + off
	if pitch > 88.5:
		cam.look_at(focus, Vector3(-sin(yw), 0, -cos(yw)))
	else:
		cam.look_at(focus, Vector3.UP)


## Alterna 3D e 2D (vista dall'alto piatta).
func set_flat(on: bool) -> void:
	flat = on
	if flat:
		_dist_t = clampf(_dist_t, 8.0, 46.0)
	refresh()


func reset_view() -> void:
	_yaw_t = _near_yaw(0.0)
	_pitch_t = 56.0
	_dist_t = 31.0
	_focus_t = Vector3(0, 0, 4.6)


## Inquadra un punto del tavolo (tabellone, fattoria…).
func look_at_point(p: Vector3, d := 16.0) -> void:
	_focus_t = Vector3(p.x, 0, p.z)
	_dist_t = d


func farm_view(s: int) -> void:
	look_at_point(farm_center[s] + Vector3(0, 0, 0.8), 13.0)


func _near_yaw(a: float) -> float:
	while a - _yaw_t > 180.0:
		a -= 360.0
	while _yaw_t - a > 180.0:
		a += 360.0
	return a


func rotate_view(dy: float) -> void:
	if not flat:
		_yaw_t += dy


func zoom(f: float) -> void:
	_dist_t = clampf(_dist_t * f, 5.0, 60.0)


func _pan_by(rel: Vector2) -> void:
	var yw := 0.0 if flat else deg_to_rad(yaw)
	var right := Vector3(cos(yw), 0, -sin(yw))
	var fwd := Vector3(-sin(yw), 0, -cos(yw))
	var f := dist * (0.0011 if flat else 0.0016)
	_focus_t += (-right * rel.x + fwd * rel.y) * f
	_focus_t.x = clampf(_focus_t.x, -24, 26)
	_focus_t.z = clampf(_focus_t.z, -14, 26)


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			zoom(0.9)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			zoom(1.1)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag = true
				_drag_moved = 0.0
			else:
				if _drag and _drag_moved < 8.0:
					var k := _pick(mb.position)
					if k != "":
						target_clicked.emit(k)
				_drag = false
		elif mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			_pan = mb.pressed
	elif ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		if _touches.size() >= 2:
			return
		if _drag and not mm.shift_pressed and not flat:
			_drag_moved += mm.relative.length()
			_yaw_t -= mm.relative.x * 0.3
			_pitch_t = clampf(_pitch_t + mm.relative.y * 0.25, 18.0, 89.0)
		elif _pan or (_drag and (mm.shift_pressed or flat)):
			_drag_moved += mm.relative.length()
			_pan_by(mm.relative)
		else:
			var k2 := _pick(mm.position)
			if k2 != hover_key:
				hover_key = k2
				target_hovered.emit(k2)
	elif ev is InputEventScreenTouch:
		var stt := ev as InputEventScreenTouch
		if stt.pressed:
			_touches[stt.index] = stt.position
		else:
			_touches.erase(stt.index)
		_pinch_d = 0.0
	elif ev is InputEventScreenDrag:
		var sd := ev as InputEventScreenDrag
		_touches[sd.index] = sd.position
		if _touches.size() >= 2:
			var ks := _touches.keys()
			var d2: float = (_touches[ks[0]] as Vector2).distance_to(_touches[ks[1]])
			if _pinch_d > 0.0:
				_dist_t = clampf(_dist_t * _pinch_d / maxf(1.0, d2), 5.0, 60.0)
			_pinch_d = d2
			_drag_moved = 99.0
	elif ev is InputEventMagnifyGesture:
		zoom(1.0 / (ev as InputEventMagnifyGesture).factor)
	elif ev is InputEventPanGesture:
		_pan_by((ev as InputEventPanGesture).delta * 12.0)
