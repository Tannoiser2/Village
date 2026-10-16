extends Control
## Vista di gioco: il villaggio in 3D (o in 2D dall'alto) al centro, le famiglie a sinistra, mercato,
## Locanda, Porto e cronaca a destra, le decisioni in basso. Gli spazi selezionabili si illuminano.

const D = preload("res://scripts/data/vl_data.gd")
const LX := 10.0
const LW := 380.0
const RX := 1536.0
const RW := 374.0
const MW := RX - LX - LW - 30.0

var main
var config: Dictionary
var engine: VLEngine
var st: VLState
var online = null
var humans: Array = []
var pending: Dictionary = {}
var board: Board3D

# nodi
var top_lbl: Label
var sub_lbl: Label
var flat_btn: Button
var rows_box: VBoxContainer
var side_box: VBoxContainer
var chron: RichTextLabel
var act_panel: PanelContainer
var act_title: Label
var act_body: VBoxContainer
var modal: Control
var tip: PanelContainer
var tip_lbl: Label
var online_lbl: Label
var target_map := {}          # chiave 3D -> Callable
var target_info := {}         # chiave 3D -> testo
var wiz := {}                 # passo in corso della scelta del turno
var hint := {}                # mossa consigliata dall'IA per la decisione in corso
var sel := {}                 # selezioni in corso (cubi, merci, salite…)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size = Vector2(1920, 1080)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	online = config.get("online", null)

	engine = VLEngine.new()
	add_child(engine)
	engine.setup(config)
	st = engine.st
	engine.ai_delay = config.get("ai_delay", 0.6)
	if online != null:
		humans = [online.seat]
		online.view = self
		add_child(online)
		engine.online = online
		if online.role != "host":
			online.heartbeat_loop()
	else:
		for s in st.n:
			if not st.players[s]["ai"]:
				humans.append(s)
	engine.pause_enabled = humans.size() > 0

	board = Board3D.new()
	board.eng = engine
	add_child(board)
	board.target_clicked.connect(_on_target)
	board.target_hovered.connect(_on_hover)

	_build_top()
	_build_cam()
	_build_left()
	_build_right()
	_build_action()
	modal = Control.new()
	modal.size = Vector2(1920, 1080)
	modal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(modal)
	tip = PanelContainer.new()
	tip.add_theme_stylebox_override("panel", UI.paper(false, 14))
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip_lbl = UI.label("", 20)
	tip_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_lbl.custom_minimum_size = Vector2(380, 0)
	tip.add_child(tip_lbl)
	tip.visible = false
	add_child(tip)
	_build_online_label()

	engine.changed.connect(refresh)
	engine.log_added.connect(_on_log)
	engine.decision_requested.connect(_on_decision)
	engine.pause_requested.connect(_on_pause)
	engine.game_ended.connect(_on_game_end)
	engine.fx.connect(_on_fx)
	refresh()
	if online != null and online.catchup:
		online_status("Riprendo la partita dal punto in cui era…")
	engine.run.call_deferred()


func _exit_tree() -> void:
	if engine != null:
		engine.abort = true


# =================================================================== costruzione

func _panel(pos: Vector2, sz: Vector2, dark := false) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.paper(dark, 18))
	p.position = pos
	p.size = sz
	p.custom_minimum_size = sz
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(p)
	return p


func _build_top() -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.plank("wood_dark", 14))
	p.position = Vector2(LX + LW + 10, 8)
	p.custom_minimum_size = Vector2(RX - LX - LW - 20, 72)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(p)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	p.add_child(hb)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", -2)
	hb.add_child(vb)
	top_lbl = UI.title("Village", 30, UI.LIGHT)
	vb.add_child(top_lbl)
	sub_lbl = UI.label("", 19, Color("#f3dfb8"))
	sub_lbl.clip_text = true
	sub_lbl.custom_minimum_size = Vector2(380, 0)
	vb.add_child(sub_lbl)
	hb.add_child(Audio.toggle_button("music", 132, 48))
	hb.add_child(Audio.toggle_button("sfx", 132, 48))
	for spec in [["Regole", _show_rules_popup], ["Diario", _show_log], ["Menu", _ask_quit]]:
		var b := UI.button(spec[0], 96, 48, 20)
		b.pressed.connect(spec[1])
		hb.add_child(b)


## Comandi della telecamera e passaggio 3D / 2D.
func _build_cam() -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.paper(true, 10))
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.position = Vector2(LX + LW + 18, 88)
	add_child(p)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	p.add_child(vb)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 4)
	vb.add_child(hb)
	flat_btn = UI.button("2D", 64, 44, 22)
	flat_btn.tooltip_text = "Passa alla vista 2D dall'alto (e ritorno al 3D)"
	flat_btn.pressed.connect(_toggle_flat)
	hb.add_child(flat_btn)
	for spec in [["<", "Ruota a sinistra (Q)", func(): board.rotate_view(-30)], [">", "Ruota a destra (E)", func(): board.rotate_view(30)],
			["+", "Avvicina", func(): board.zoom(0.85)], ["-", "Allontana", func(): board.zoom(1.18)]]:
		var b := UI.button(spec[0], 48, 44, 24)
		b.tooltip_text = spec[1]
		b.pressed.connect(spec[2])
		hb.add_child(b)
	var hb2 := HBoxContainer.new()
	hb2.add_theme_constant_override("separation", 4)
	vb.add_child(hb2)
	var v1 := UI.button("Villaggio", 128, 40, 18)
	v1.tooltip_text = "Inquadra tutto il tavolo (Home)"
	v1.pressed.connect(func(): board.reset_view())
	hb2.add_child(v1)
	var v3 := UI.button("Cronache", 124, 40, 18)
	v3.tooltip_text = "Inquadra le cronache del villaggio e le tombe"
	v3.pressed.connect(func(): board.chron_view())
	hb2.add_child(v3)
	var v2 := UI.button("Fattorie", 120, 40, 18)
	v2.tooltip_text = "Inquadra le fattorie delle famiglie"
	v2.pressed.connect(func(): board.look_at_point(Vector3(0, 0, Board3D.HALF + 4.5), 22.0))
	hb2.add_child(v2)


func _toggle_flat() -> void:
	board.set_flat(not board.flat)
	flat_btn.text = "3D" if board.flat else "2D"
	flat_btn.tooltip_text = "Torna alla vista 3D" if board.flat else "Passa alla vista 2D dall'alto"


func _build_left() -> void:
	var sc := ScrollContainer.new()
	sc.position = Vector2(LX, 8)
	sc.size = Vector2(LW, 1064)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(sc)
	rows_box = VBoxContainer.new()
	rows_box.add_theme_constant_override("separation", 6)
	rows_box.custom_minimum_size = Vector2(LW - 8, 0)
	sc.add_child(rows_box)


func _build_right() -> void:
	var p := _panel(Vector2(RX, 8), Vector2(RW, 1064))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	p.add_child(vb)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(RW - 36, 560)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(sc)
	side_box = VBoxContainer.new()
	side_box.add_theme_constant_override("separation", 6)
	side_box.custom_minimum_size = Vector2(RW - 44, 0)
	sc.add_child(side_box)
	vb.add_child(HSeparator.new())
	vb.add_child(UI.title("Cronaca", 26))
	chron = RichTextLabel.new()
	chron.bbcode_enabled = true
	chron.scroll_following = true
	chron.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chron.add_theme_font_size_override("normal_font_size", 18)
	chron.add_theme_font_size_override("bold_font_size", 17)
	vb.add_child(chron)
	vb.add_child(UI.label("Trascina: ruota (in 2D sposta) · rotella: zoom\nTasto destro o Maiusc+trascina: sposta", 16, UI.INK2, UI.font_italic))


func _build_action() -> void:
	act_panel = PanelContainer.new()
	act_panel.add_theme_stylebox_override("panel", UI.paper(true, 22))
	act_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	act_panel.custom_minimum_size = Vector2(MW, 0)
	add_child(act_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	act_panel.add_child(vb)
	act_title = UI.wrap("", 23, MW - 50, UI.INK, UI.font_bold)
	vb.add_child(act_title)
	var sc := ScrollContainer.new()
	sc.name = "Scroll"
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(sc)
	act_body = VBoxContainer.new()
	act_body.add_theme_constant_override("separation", 6)
	act_body.custom_minimum_size = Vector2(MW - 56, 0)
	sc.add_child(act_body)
	_place_action.call_deferred()


func _place_action() -> void:
	await get_tree().process_frame
	var sc: ScrollContainer = act_body.get_parent()
	var h := act_body.get_combined_minimum_size().y
	sc.custom_minimum_size = Vector2(MW - 50, minf(h, 520.0))
	act_panel.size = Vector2.ZERO
	act_panel.reset_size()
	act_panel.position = Vector2(LX + LW + 15, 1072 - act_panel.size.y)


# =================================================================== aggiornamento

var _dirty := false


## Gli aggiornamenti si raccolgono: al massimo uno per fotogramma.
func refresh() -> void:
	if _dirty:
		return
	_dirty = true
	_do_refresh.call_deferred()


func _do_refresh() -> void:
	_dirty = false
	if engine == null or not engine.setup_done or not is_inside_tree():
		return
	board.refresh()
	_refresh_top()
	_refresh_rows()
	_refresh_side()
	if pending.is_empty():
		_idle_message()
		board.set_targets({})


func _phase_text() -> String:
	match engine.phase:
		"turn": return "Azioni nel villaggio"
		"market": return "Giorno di mercato"
		"mass": return "Messa"
		"final": return "Ultime azioni"
		"end": return "Fine della partita"
	return ""


func _refresh_top() -> void:
	top_lbl.text = "Village · round %d" % maxi(1, st.round_no)
	var t := _phase_text()
	t += " · cubi rimasti %d" % st.cubes_left()
	t += " · cronache libere %d, tombe %d" % [st.chron_free(), st.graves_free()]
	if st.port:
		var bfree := 0
		for v in st.burials:
			if int(v) == -1:
				bfree += 1
		t += ", in mare %d" % bfree
	sub_lbl.text = t


func _can_see(s: int) -> bool:
	if engine.game_over:
		return true
	if online != null:
		return s == online.seat
	if st.players[s]["ai"]:
		return false
	if humans.size() == 1:
		return true
	return engine.current == s and not pending.is_empty()


func _refresh_rows() -> void:
	for c in rows_box.get_children():
		rows_box.remove_child(c)
		c.queue_free()
	for s in st.n:
		rows_box.add_child(_player_row(s))


func _player_row(s: int) -> Control:
	var pl: Dictionary = st.players[s]
	var col: Color = UI.ink_of(pl["color"])
	var box := PanelContainer.new()
	var active: bool = engine.current == s and not engine.game_over
	box.add_theme_stylebox_override("panel", UI.paper(active, 14))
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and ev.double_click:
			board.farm_view(s))
	box.tooltip_text = "Doppio clic: inquadra la fattoria"
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	box.add_child(vb)
	var see := _can_see(s)
	# intestazione
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	vb.add_child(hb)
	hb.add_child(UI.icon_rect(UI.tex("res://assets/ui/meeple_%s.png" % D.COLORS[pl["color"]]["key"]), Vector2(40, 40)))
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", -6)
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(nv)
	var nm := UI.title(pl["name"] + ("  (IA)" if pl["ai"] else ""), 24, col)
	nm.clip_text = true
	nm.custom_minimum_size = Vector2(170, 0)
	nv.add_child(nm)
	var tags := []
	if st.first == s:
		tags.append("primo giocatore")
	if st.next_owner == s:
		tags.append("prossimo primo")
	if int(pl["deaths"]) > 0:
		tags.append("un familiare sta per morire")
	nv.add_child(UI.label(" · ".join(tags), 16, UI.BRICK, UI.font_bold))
	var ppv := VBoxContainer.new()
	ppv.add_theme_constant_override("separation", -8)
	var ppl := UI.label("%d" % pl["pp"], 32, UI.INK, UI.font_heavy)
	ppl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ppv.add_child(ppl)
	ppv.add_child(UI.label("prestigio", 14, UI.INK2, UI.font_italic))
	ppv.tooltip_text = "Punti prestigio sul percorso (i punti finali si aggiungono alla fine)"
	hb.add_child(ppv)
	# tempo della vita, monete, grano
	var tr := HBoxContainer.new()
	tr.add_theme_constant_override("separation", 2)
	vb.add_child(tr)
	for i in D.TIME_STEPS:
		var cell := Panel.new()
		cell.custom_minimum_size = Vector2(14, 14)
		var on: bool = i == int(pl["time"])
		cell.add_theme_stylebox_override("panel", UI.panel_style(UI.pcolor(pl["color"]) if on else Color(0.42, 0.29, 0.17, 0.15), UI.INK if on else Color(0.42, 0.29, 0.17, 0.5), 2 if on else 1, 7))
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.add_child(cell)
	var bridge := UI.label("ponte", 14, UI.INK2, UI.font_italic)
	tr.add_child(bridge)
	tr.tooltip_text = "Tempo della vita: %d passi al ponte. Quando lo attraversa muore un familiare." % (D.TIME_STEPS - int(pl["time"]))
	tr.mouse_filter = Control.MOUSE_FILTER_STOP
	var sp0 := Control.new()
	sp0.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tr.add_child(sp0)
	tr.add_child(UI.counter(UI.token("coin"), pl["coins"], 22))
	tr.add_child(UI.counter(UI.token("grain"), pl["grain"], 22))
	# cubi e merci
	var rr := HFlowContainer.new()
	rr.add_theme_constant_override("h_separation", 6)
	rr.add_theme_constant_override("v_separation", 2)
	vb.add_child(rr)
	for c in D.CUBES:
		var ch := HBoxContainer.new()
		ch.add_theme_constant_override("separation", 2)
		ch.add_child(UI.cube_icon(c, 18))
		ch.add_child(UI.label(str(pl["cubes"][c]), 19, UI.INK, UI.font_bold))
		ch.tooltip_text = "Cubi %s (%s)" % [D.cube_name(c), D.CUBE[c]["long"]]
		ch.mouse_filter = Control.MOUSE_FILTER_STOP
		rr.add_child(ch)
	for g in D.GOODS:
		if int(pl["goods"][g]) > 0:
			var gc := UI.counter(UI.token(g), pl["goods"][g], 22)
			gc.tooltip_text = D.good_name(g, int(pl["goods"][g]))
			gc.mouse_filter = Control.MOUSE_FILTER_STOP
			rr.add_child(gc)
	# famiglia
	var fam := {}
	var pool := 0
	var bag := 0
	for m in st.members:
		if m["owner"] != s:
			continue
		if m["loc"] == "farm":
			fam[m["gen"]] = int(fam.get(m["gen"], 0)) + 1
		elif m["loc"] == "pool":
			pool += 1
		elif m["loc"] == "bag":
			bag += 1
	var ft := []
	for g in [1, 2, 3, 4]:
		for k in int(fam.get(g, 0)):
			ft.append(str(g))
	var fl := UI.label("In fattoria: %s · da nascere %d%s · cronache %d" % [" ".join(ft) if not ft.is_empty() else "nessuno", pool, (" · nel sacchetto %d" % bag) if bag > 0 else "", st.chron_count(s)], 17, UI.INK2)
	fl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fl.custom_minimum_size = Vector2(LW - 40, 0)
	vb.add_child(fl)
	# clienti, carte, obiettivi, nave
	var extra := []
	var cust: Array = pl["customers"]
	if see:
		var cp := 0
		for ci in cust:
			cp += int(D.CUSTOMERS[ci]["pp"])
		extra.append("clienti %d (%d punti)" % [cust.size(), cp])
	else:
		extra.append("clienti %d" % cust.size())
	if st.inn:
		extra.append("abitanti %d" % pl["hand"].size())
	if not st.port:
		extra.append("città %d" % pl["cities"].size())
	vb.add_child(UI.label(" · ".join(extra), 17, UI.INK2))
	if see and not pl["hand"].is_empty():
		var cf := HFlowContainer.new()
		cf.add_theme_constant_override("h_separation", 3)
		for cid in pl["hand"]:
			var t := UI.icon_rect(UI.villager(cid), Vector2(40, 63))
			t.mouse_filter = Control.MOUSE_FILTER_STOP
			t.tooltip_text = "%s (%s): %s" % [D.VILLAGERS[cid]["name"], _kind_text(D.VILLAGERS[cid]["kind"]), D.VILLAGERS[cid]["text"]]
			cf.add_child(t)
		vb.add_child(cf)
	if st.goals_on:
		if see:
			for g in pl["goals"]:
				var gl := UI.label("· " + Describe.goal_text(g), 15, UI.INK2, UI.font_italic)
				gl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				gl.custom_minimum_size = Vector2(LW - 40, 0)
				vb.add_child(gl)
		elif pl["goals"].size() > 0:
			vb.add_child(UI.label("obiettivi di vita segreti: %d" % pl["goals"].size(), 15, UI.INK2, UI.font_italic))
		for g in pl["goals_done"]:
			vb.add_child(UI.label("Fatto: " + st.goal_def(g)["name"], 15, UI.GREEN, UI.font_bold))
	if st.port:
		var sh: Dictionary = pl["ship"]
		var hold := []
		for it in sh["hold"]:
			var kind := str(it).get_slice(":", 0)
			hold.append("familiare" if kind == "member" else ("forziere" if kind == "chest" else ("grano" if kind == "grain" else D.good_name(kind))))
		var where: String = "in porto" if sh["at"] == "P" else D.SEA[sh["at"]].get("name", "in mare")
		var ct := "nave %s%s%s" % [where, (" · capitano da %d" % int(D.CAPTAINS[int(sh["cap"])]["cost"])) if int(sh["cap"]) >= 0 and int(sh["cap"]) < 100 else (" · Ammiraglio" if int(sh["cap"]) == 100 else ""), (" · stiva: " + ", ".join(hold)) if not hold.is_empty() else ""]
		var sl := UI.label(ct, 16, UI.INK2, UI.font_italic)
		sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sl.custom_minimum_size = Vector2(LW - 40, 0)
		vb.add_child(sl)
	return box


func _kind_text(k: String) -> String:
	match k:
		"end": return "si tiene fino alla fine"
		"any": return "quando vuoi nel tuo turno"
	return "in un momento preciso"


func _refresh_side() -> void:
	for c in side_box.get_children():
		side_box.remove_child(c)
		c.queue_free()
	side_box.add_child(UI.title("Mercato", 26))
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 4)
	f.add_theme_constant_override("v_separation", 4)
	for i in st.front_n:
		if st.front[i] >= 0:
			var t := UI.icon_rect(UI.customer(st.front[i]), Vector2(84, 84))
			t.mouse_filter = Control.MOUSE_FILTER_STOP
			var cu: Dictionary = D.CUSTOMERS[st.front[i]]
			t.tooltip_text = "Cliente: %s » %d punti" % [Describe.need_text(cu["need"]), cu["pp"]]
			f.add_child(t)
	side_box.add_child(f)
	var qn := 0
	for i in 5:
		if st.queue[i] >= 0:
			qn += 1
	side_box.add_child(UI.label("in coda %d · nella pila %d" % [qn, st.pile.size()], 17, UI.INK2, UI.font_italic))
	side_box.add_child(UI.title("Cronache", 26))
	for sec in D.SECTIONS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 3)
		var nm := UI.label(D.SECTION[sec]["name"], 17, D.SECTION[sec]["color"].darkened(0.2), UI.font_bold)
		nm.custom_minimum_size = Vector2(196, 0)
		row.add_child(nm)
		for v in st.chron[sec]:
			row.add_child(_slot_box(int(v)))
		side_box.add_child(row)
	var gr := HBoxContainer.new()
	gr.add_theme_constant_override("separation", 3)
	var gl := UI.label("Tombe anonime", 17, UI.INK2, UI.font_bold)
	gl.custom_minimum_size = Vector2(196, 0)
	gr.add_child(gl)
	for v in st.graves:
		gr.add_child(_slot_box(int(v)))
	side_box.add_child(gr)
	if st.port:
		var br := HBoxContainer.new()
		br.add_theme_constant_override("separation", 3)
		var bl := UI.label("Sepolture in mare", 17, UI.INK2, UI.font_bold)
		bl.custom_minimum_size = Vector2(196, 0)
		br.add_child(bl)
		for v in st.burials:
			br.add_child(_slot_box(int(v)))
		side_box.add_child(br)
	if st.inn:
		side_box.add_child(UI.title("Locanda", 26))
		var lf := HBoxContainer.new()
		lf.add_theme_constant_override("separation", 6)
		for d in st.decks.size():
			var dv := VBoxContainer.new()
			dv.add_theme_constant_override("separation", 0)
			if st.decks[d].is_empty():
				dv.add_child(UI.label("vuoto", 17, UI.INK2))
			else:
				var top: int = st.decks[d][-1]
				var t2 := UI.icon_rect(UI.villager(top), Vector2(96, 152))
				t2.mouse_filter = Control.MOUSE_FILTER_STOP
				t2.tooltip_text = "%s · costa %s\n%s" % [D.VILLAGERS[top]["name"], D.cost_text(D.VILLAGERS[top]["cost"]), D.VILLAGERS[top]["text"]]
				dv.add_child(t2)
				dv.add_child(UI.label("mazzo %d · %d" % [d + 1, st.decks[d].size()], 15, UI.INK2))
			lf.add_child(dv)
		side_box.add_child(lf)
	if st.port:
		side_box.add_child(UI.title("Porto", 26))
		var cf := HFlowContainer.new()
		cf.add_theme_constant_override("h_separation", 4)
		for k in 3:
			var n: int = st.captains[k].size()
			cf.add_child(UI.label("capitani da %d: %d" % [k + 1, n], 17, UI.INK2))
		side_box.add_child(cf)
		var mi := []
		for isl in D.MISSIONS:
			if int(st.missions[isl]) >= 0:
				mi.append("%s (%s)" % [D.SEA[isl]["name"], st.pname(st.members[int(st.missions[isl])]["owner"])])
		if not mi.is_empty():
			side_box.add_child(UI.wrap("Missioni: " + ", ".join(mi), 16, RW - 50, UI.INK2))


## Casella delle cronache: libera, coperta (meno giocatori) o occupata (colore della famiglia).
func _slot_box(v: int) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(18, 18)
	var col := Color(0.42, 0.29, 0.17, 0.12)
	var border := Color(0.42, 0.29, 0.17, 0.6)
	if v == -2:
		col = Color(0.2, 0.15, 0.1, 0.55)
	elif v >= 0:
		col = UI.pcolor(st.players[v]["color"])
		border = UI.INK
	p.add_theme_stylebox_override("panel", UI.panel_style(col, border, 1, 9))
	p.tooltip_text = "coperta" if v == -2 else ("libera" if v == -1 else st.pname(v))
	return p


func _idle_message() -> void:
	_clear_body()
	if engine.game_over:
		act_title.text = "Partita finita."
		_place_action.call_deferred()
		return
	var s := engine.current
	var t := ""
	if s >= 0 and s < st.n and st.players[s]["ai"]:
		t = "%s sta pensando…" % engine.pname(s)
	elif online != null and s >= 0 and s != online.seat:
		t = "Tocca a %s…" % engine.pname(s)
	if engine.log_lines.size() > 0:
		t = (t + "\n" if t != "" else "") + str(engine.log_lines[-1])
	act_title.text = t
	_place_action.call_deferred()


func _on_log(t: String) -> void:
	var line := t
	if t.begins_with("—"):
		line = "\n[b][color=#8a2a14]%s[/color][/b]" % t
	chron.append_text(line + "\n")
	if pending.is_empty():
		_idle_message()


func _on_fx(kind: String, data: Dictionary) -> void:
	Audio.suspended = online != null and online.catchup
	match kind:
		"move":
			match str(data.get("a", "")):
				"harvest": Audio.play("harvest", -4.0)
				"market": pass
				"none": Audio.play("cube", -2.0)
				"sail": Audio.play("splash", -4.0)
				_: Audio.play("pawn")
		"market":
			Audio.play("market", -3.0)
		"sale":
			Audio.play("coin", -4.0)
		"mass":
			Audio.play("bell", -6.0)
		"death":
			Audio.play("toll", -6.0)
		"card":
			Audio.play("card", -2.0)
		"round":
			Audio.play("cube", -4.0)


# =================================================================== decisioni

func _who() -> String:
	return "%s, " % engine.pname(int(pending["seat"])) if humans.size() > 1 else ""


func _clear_body() -> void:
	for c in act_body.get_children():
		act_body.remove_child(c)
		c.queue_free()
	target_map = {}
	target_info = {}


func _on_decision(req: Dictionary) -> void:
	if humans.size() > 1 and online == null and not req.get("_shown", false) and int(req["seat"]) != int(get_meta("last_seat", -1)):
		req["_shown"] = true
		set_meta("last_seat", int(req["seat"]))
		_curtain(int(req["seat"]), func(): _on_decision(req))
		return
	pending = req
	wiz = {}
	sel = {}
	hint = {}
	if config.get("hints", true):
		var s: int = req["seat"]
		var r = engine.ais[s].decide(engine, s, req.duplicate())
		hint = {"r": r}
	refresh()
	_clear_body()
	Audio.play("turn", -10.0)
	_show_decision()


func _show_decision() -> void:
	_clear_body()
	board.set_targets({})
	var req := pending
	act_title.text = _who() + str(req.get("title", ""))
	match str(req["type"]):
		"turn": _turn_ui()
		"after": _after_ui()
		"cubes2": _cubes2_ui()
		"good": _good_ui()
		"priv": _priv_ui()
		"inn_buy": _inn_ui()
		"island": _island_ui()
		"family": _list_ui(req["options"].map(func(a): return Describe.action(st, int(req["seat"]), a)), true)
		"herb": _herb_ui()
		"noble": _noble_ui()
		"city": _city_ui()
		"abbot": _member_ui(req["options"], func(id): return id)
		"use_card": _yesno_ui()
		"market": _market_ui()
		"scrap": _scrap_ui()
		"priest": _pick_members_ui(req["pieces"], 4, "Estrai questi")
		"mass_buy": _pick_members_ui(req["options"], int(req["max"]), "Compra (1 moneta ciascuno)")
		"mass_up": _mass_up_ui()
		"death": _death_ui()
		_:
			_provide(null)
			return
	_place_action.call_deferred()


func _provide(r) -> void:
	pending = {}
	wiz = {}
	_clear_body()
	board.set_targets({})
	tip.visible = false
	refresh()
	engine.provide_decision(r)


func _flow() -> HFlowContainer:
	var f := HFlowContainer.new()
	f.custom_minimum_size = Vector2(MW - 60, 0)
	f.add_theme_constant_override("h_separation", 6)
	f.add_theme_constant_override("v_separation", 6)
	act_body.add_child(f)
	return f


func _btn(text: String, cb: Callable, hinted := false, size := 19, h := 44.0) -> Button:
	var b := UI.button(text, 0, h, size)
	b.pressed.connect(cb)
	if hinted:
		UI.selected(b, "meadow")
		b.tooltip_text = "Consiglio dell'IA"
	return b


func _back_btn(f: Container) -> void:
	var b := UI.button("Indietro", 0, 44, 19)
	b.add_theme_stylebox_override("normal", UI.plank("wood_dark"))
	b.pressed.connect(func():
		wiz = {}
		sel = {}
		_show_decision())
	f.add_child(b)


# ------------------------------------------------------------------ turno

func _hint_move() -> Dictionary:
	var r = hint.get("r", null)
	if r is int and r >= 0 and r < pending["moves"].size():
		return pending["moves"][r]
	return {}


func _turn_ui() -> void:
	var req := pending
	var moves: Array = req["moves"]
	var hm := _hint_move()
	var hc: int = int(hint["r"]["id"]) if hint.get("r", null) is Dictionary and hint["r"].get("k", "") == "card" else -1
	if wiz.get("step", "") == "act":
		_turn_actions()
		return
	if wiz.get("step", "") == "space":
		_turn_spaces()
		return
	if wiz.get("step", "") == "sail":
		_sail_ui()
		return
	# scelta del cubo: spazi con i loro cubi
	var targets := {}
	var spaces := {}
	for m in moves:
		var src: Dictionary = m["src"]
		if src["t"] == "space":
			if not spaces.has(src["sp"]):
				spaces[src["sp"]] = {}
			spaces[src["sp"]][src["c"]] = true
	var grid := VBoxContainer.new()
	grid.add_theme_constant_override("separation", 4)
	act_body.add_child(grid)
	var row := HFlowContainer.new()
	row.custom_minimum_size = Vector2(MW - 60, 0)
	row.add_theme_constant_override("h_separation", 14)
	row.add_theme_constant_override("v_separation", 6)
	grid.add_child(row)
	for sp in D.SPACES:
		if not spaces.has(sp):
			continue
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 3)
		var hl: bool = not hm.is_empty() and hm["src"].get("sp", "") == sp
		var nm := UI.label(D.SPACE[sp]["name"] + ":", 20, UI.GREEN if hl else UI.INK, UI.font_bold)
		cell.add_child(nm)
		var cnt := {}
		for c in st.spaces[sp]:
			cnt[c] = int(cnt.get(c, 0)) + 1
		for c in ["pk", "br", "gr", "or", "pl"]:
			if not spaces[sp].has(c):
				continue
			var b := Button.new()
			b.custom_minimum_size = Vector2(46, 40)
			b.text = str(cnt[c]) if cnt[c] > 1 else ""
			b.tooltip_text = "Prendi un cubo %s da %s" % [D.cube_name(c), D.SPACE[sp]["name"]] + (" (peste: perdi 2 tempi)" if c == "pl" else "")
			var col: Color = D.CUBE[c]["color"]
			var sb := UI.panel_style(col, UI.GOLD if (hl and hm["src"].get("c", "") == c) else col.darkened(0.5), 4 if (hl and hm["src"].get("c", "") == c) else 2, 5)
			b.add_theme_stylebox_override("normal", sb)
			b.add_theme_stylebox_override("hover", UI.panel_style(col.lightened(0.2), UI.GOLD, 3, 5))
			b.add_theme_stylebox_override("pressed", sb)
			var src := {"t": "space", "sp": sp, "c": c}
			b.pressed.connect(func(): _pick_src(src))
			cell.add_child(b)
		row.add_child(cell)
		var key: String = "sp:" + sp
		targets[key] = board.space_pos(sp)
		var only_c: String = spaces[sp].keys()[0] if spaces[sp].size() == 1 else ""
		target_map[key] = func():
			if only_c != "":
				_pick_src({"t": "space", "sp": sp, "c": only_c})
			else:
				act_title.text = "%s: scegli quale cubo prendere." % D.SPACE[sp]["name"]
		target_info[key] = "%s: %s" % [D.SPACE[sp]["name"], ", ".join(st.spaces[sp].map(func(c): return D.cube_name(c)))]
	board.set_targets(targets)
	# pozzo, Vecchio saggio, azione gratuita, carte
	var f := _flow()
	var wells := {}
	var others := {}
	for m in moves:
		var t: String = m["src"]["t"]
		if t == "well":
			wells[m["src"]["c"]] = true
		elif t in ["oldman", "free"]:
			others[t] = true
	for c in wells:
		var src2 := {"t": "well", "c": c}
		f.add_child(_btn("Pozzo: 3 cubi %s » azione a scelta" % D.cube_name(c), func(): _pick_src(src2), not hm.is_empty() and hm["src"]["t"] == "well" and hm["src"]["c"] == c))
	if others.has("oldman"):
		f.add_child(_btn("Vecchio saggio: 3 punti e azione gratuita", func(): _pick_src({"t": "oldman"}), not hm.is_empty() and hm["src"]["t"] == "oldman"))
	if others.has("free"):
		f.add_child(_btn("Scegli la tua ultima azione (gratuita)", func(): _pick_src({"t": "free"}), true))
	for cid in req.get("cards", []):
		var c2: int = cid
		var b2 := _btn("Gioca %s" % D.VILLAGERS[cid]["name"], func(): _provide({"k": "card", "id": c2}), hc == cid)
		b2.tooltip_text = D.VILLAGERS[cid]["text"]
		f.add_child(b2)
	if moves.is_empty():
		f.add_child(_btn("Passa", func(): _provide(0)))


func _pick_src(src: Dictionary) -> void:
	wiz = {"step": "act", "src": src}
	if src["t"] in ["well", "oldman", "free"]:
		wiz["step"] = "space"
	_show_decision()


## Pozzo, Vecchio saggio o azione finale: prima si sceglie lo spazio azione.
func _turn_spaces() -> void:
	var src: Dictionary = wiz["src"]
	act_title.text = _who() + "%s: quale azione vuoi fare?" % Describe.src_text(src)
	var hm := _hint_move()
	var avail := {}
	for m in pending["moves"]:
		if m["src"] == src:
			avail[_space_of(m["a"])] = true
	var f := _flow()
	var targets := {}
	for sp in D.SPACES:
		if not avail.has(sp):
			continue
		var sp2: String = sp
		f.add_child(_btn(D.SPACE[sp]["name"], func():
			wiz["space"] = sp2
			wiz["step"] = "act"
			_show_decision(), not hm.is_empty() and hm["src"] == src and _space_of(hm["a"]) == sp))
		targets["sp:" + sp] = board.space_pos(sp)
		target_map["sp:" + sp] = func():
			wiz["space"] = sp2
			wiz["step"] = "act"
			_show_decision()
		target_info["sp:" + sp] = D.SPACE[sp]["name"]
	board.set_targets(targets)
	_back_btn(f)


static func _space_of(a: Dictionary) -> String:
	match str(a.get("a", "none")):
		"harvest": return "harvest"
		"family": return "family"
		"craft": return "crafts"
		"market": return "market"
		"travel", "sail": return "travel"
		"council": return "council"
		"church": return "church"
		"inn": return "inn"
	return ""


func _turn_actions() -> void:
	var src: Dictionary = wiz["src"]
	var s: int = pending["seat"]
	var sp: String = wiz.get("space", src.get("sp", ""))
	act_title.text = _who() + "%s · %s: scegli l'azione" % [Describe.src_text(src), D.SPACE[sp]["name"] if sp != "" else ""]
	var hm := _hint_move()
	var moves: Array = pending["moves"]
	var col := GridContainer.new()
	col.columns = 2
	col.add_theme_constant_override("h_separation", 6)
	col.add_theme_constant_override("v_separation", 5)
	act_body.add_child(col)
	var targets := {}
	var has_sail := false
	for i in moves.size():
		var m: Dictionary = moves[i]
		if m["src"] != src:
			continue
		var a: Dictionary = m["a"]
		if a.get("a", "none") != "none" and _space_of(a) != sp:
			continue
		if a.get("a", "") == "sail":
			has_sail = true
		var idx := i
		var hl: bool = not hm.is_empty() and _same(hm, m)
		var b := _btn(Describe.action(st, s, a), func(): _provide(idx), hl, 17, 42.0)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.x = (MW - 74) / 2.0
		b.clip_text = true
		b.tooltip_text = Describe.action(st, s, a) + ("\n(consiglio dell'IA)" if hl else "")
		col.add_child(b)
		# bersagli sul tabellone per scegliere il familiare o la città
		var key := _target_key(a)
		if key != "" and not targets.has(key):
			targets[key] = _target_pos(a)
			target_map[key] = func(): _provide(idx)
			target_info[key] = Describe.action(st, s, a)
	board.set_targets(targets)
	var f := _flow()
	if has_sail or (sp == "travel" and st.port):
		f.add_child(_btn("Rotta a scelta sulla mappa…", func():
			wiz["step"] = "sail"
			sel = {}
			_show_decision()))
	_back_btn(f)


func _same(a: Dictionary, b: Dictionary) -> bool:
	return var_to_str(a.get("src", {})) == var_to_str(b.get("src", {})) and var_to_str(a.get("a", {})) == var_to_str(b.get("a", {}))


func _target_key(a: Dictionary) -> String:
	match str(a.get("a", "")):
		"travel":
			return "city:%d:%s" % [int(a["m"]), a["to"]] if not a.get("toll", false) else ""
	return ""


func _target_pos(a: Dictionary) -> Vector3:
	if a.get("a", "") == "travel":
		return Board3D.px(D.CITY[a["to"]]["pos"])
	return Vector3.ZERO


# ------------------------------------------------------------------ viaggio per mare a scelta

func _sail_ui() -> void:
	var s: int = pending["seat"]
	var pl: Dictionary = st.players[s]
	var sh: Dictionary = pl["ship"]
	var src: Dictionary = wiz["src"]
	if not sel.has("path"):
		sel = {"cap": int(sh["cap"]) if sh["at"] != "P" else -2, "helm": false, "load": [], "path": [], "land": false}
	var f := _flow()
	# 1. capitano
	if sh["at"] == "P" and int(sel["cap"]) == -2:
		act_title.text = _who() + "Scegli il capitano da ingaggiare (gli altri passi oltre il primo si pagano come indicato)"
		for c in st.hireable(s):
			var c2: int = c
			var spec: Dictionary = D.ADMIRAL if c == 100 else D.CAPTAINS[c]
			var t := "Ammiraglio" if c == 100 else "Capitano da %d" % int(spec["cost"])
			t += ": %s » %d %s" % [Describe.cubes_text(spec["pay"]), spec["steps"], "passo" if int(spec["steps"]) == 1 else "passi"]
			var b := _btn(t, func():
				sel["cap"] = c2
				_show_decision())
			b.icon = UI.captain_tex(c)
			b.expand_icon = true
			b.custom_minimum_size = Vector2(0, 70)
			f.add_child(b)
		_back_btn(f)
		return
	# 2. carico (in porto)
	if sh["at"] == "P" and not sel.get("loaded", false):
		act_title.text = _who() + "Carica la nave: fino a 3 pezzi di tipo diverso (poi scegli la rotta)"
		var items := []
		for g in ["horse", "ox", "plow", "wagon", "scroll"]:
			if int(pl["goods"][g]) > 0:
				items.append(g)
		if int(pl["grain"]) > 0:
			items.append("grain")
		for m in st.distinct_gen(st.farm(s)):
			items.append("member:%d" % m["id"])
		for it in items:
			var it2: String = it
			var kind: String = it.get_slice(":", 0)
			var on: bool = it in sel["load"]
			var label := ("familiare %d" % st.members[int(it.get_slice(":", 1))]["gen"]) if kind == "member" else ("grano" if kind == "grain" else D.good_name(kind))
			var b2 := _btn(("» " if on else "") + label, func():
				if it2 in sel["load"]:
					sel["load"].erase(it2)
				elif sel["load"].size() < 3:
					var kinds: Array = sel["load"].map(func(x): return str(x).get_slice(":", 0))
					if not (it2.get_slice(":", 0) in kinds) or st.has_card(s, "quartermaster"):
						sel["load"].append(it2)
				_show_decision(), on)
			f.add_child(b2)
		if st.has_card(s, "helmsman"):
			var hb := _btn(("» " if sel["helm"] else "") + "Timoniere (1 passo gratis in più)", func():
				sel["helm"] = not sel["helm"]
				_show_decision(), sel["helm"])
			f.add_child(hb)
		var ok := UI.primary(UI.button("Scegli la rotta", 240, 44, 20))
		ok.pressed.connect(func():
			sel["loaded"] = true
			_show_decision())
		f.add_child(ok)
		_back_btn(f)
		return
	# 3. rotta
	var path: Array = sel["path"]
	var cur: String = path[-1] if not path.is_empty() else str(sh["at"])
	var spec2: Dictionary = (D.ADMIRAL if int(sel["cap"]) == 100 else D.CAPTAINS[int(sel["cap"])]) if int(sel["cap"]) >= 0 else {}
	var cost := st.step_cost(spec2, path.size(), sel["helm"] or bool(sh["helm"]))
	var tt := 0
	for nd in path:
		if D.SEA[nd]["kind"] == "time":
			tt += 1
	var cap_cost: int = int(spec2.get("cost", 0)) if sh["at"] == "P" else 0
	var afford: bool = st._missing(s, cost) <= int(pl["coins"]) - cap_cost
	act_title.text = _who() + "Rotta: clicca le acque vicine sulla mappa. %d %s, %s%s%s" % [path.size(), "tratto" if path.size() == 1 else "tratti", Describe.tempi(tt),
		(", " + Describe.cubes_text(cost)) if not cost.is_empty() else ", nessun cubo", "" if afford else " (non puoi pagarlo!)"]
	var targets := {}
	for nb in D.sea_neighbors(cur):
		if nb == "P":
			continue
		targets["sea:" + nb] = board.sea_pos(nb)
		var nb2: String = nb
		target_map["sea:" + nb] = func():
			sel["path"].append(nb2)
			_show_decision()
		target_info["sea:" + nb] = D.SEA[nb].get("name", "Acque del tempo: perdi 1 tempo")
		f.add_child(_btn("» " + D.SEA[nb].get("name", "acque del tempo"), func():
			sel["path"].append(nb2)
			_show_decision()))
	board.set_targets(targets)
	if not path.is_empty():
		var undo := _btn("Togli l'ultimo tratto", func():
			sel["path"].pop_back()
			_show_decision())
		f.add_child(undo)
	var at_island: bool = not path.is_empty() and D.SEA[cur]["kind"] == "island"
	if afford and not path.is_empty():
		var mk := func(land: bool) -> Dictionary:
			var a := {"a": "sail", "path": sel["path"].duplicate(), "land": land}
			if sh["at"] == "P":
				a["cap"] = sel["cap"]
				a["load"] = sel["load"].duplicate()
				a["helm"] = sel["helm"]
			return {"k": "move", "src": src, "a": a}
		if at_island:
			var b3 := UI.primary(UI.button("Approda a %s" % D.SEA[cur]["name"], 0, 44, 19))
			b3.pressed.connect(func(): _provide(mk.call(true)))
			f.add_child(b3)
		var b4 := UI.button("Fermati qui" + (" senza approdare" if at_island else ""), 0, 44, 19)
		b4.pressed.connect(func(): _provide(mk.call(false)))
		f.add_child(b4)
	if st.has_card(s, "cartographer") and path.is_empty():
		for isl in D.ISLANDS:
			if isl == sh["at"]:
				continue
			var isl2: String = isl
			f.add_child(_btn("Cartografo: vai a %s" % D.SEA[isl]["name"], func():
				var a2 := {"a": "sail", "carto": isl2, "land": true, "path": []}
				if sh["at"] == "P":
					a2["cap"] = sel["cap"]
					a2["load"] = sel["load"].duplicate()
					a2["helm"] = sel["helm"]
				_provide({"k": "move", "src": src, "a": a2})))
	_back_btn(f)


# ------------------------------------------------------------------ altre decisioni

func _after_ui() -> void:
	var f := _flow()
	var r = hint.get("r", null)
	for cid in pending.get("cards", []):
		var c2: int = cid
		var b := _btn("Gioca %s" % D.VILLAGERS[cid]["name"], func(): _provide({"k": "card", "id": c2}), r is Dictionary and r.get("k", "") == "card" and int(r.get("id", -1)) == cid)
		b.tooltip_text = D.VILLAGERS[cid]["text"]
		f.add_child(b)
	if pending.get("juggler", false):
		f.add_child(_btn("Giocoliere: 2 punti e un'altra azione", func(): _provide({"k": "juggler"}), r is Dictionary and r.get("k", "") == "juggler"))
	var e := UI.primary(UI.button("Fine del turno", 220, 44, 20))
	e.pressed.connect(func(): _provide({"k": "end"}))
	f.add_child(e)


func _cubes2_ui() -> void:
	var k: int = int(pending.get("k", 2))
	if not sel.has("list"):
		sel["list"] = []
	var f := _flow()
	var hl: Array = hint.get("r", []) if hint.get("r", null) is Array else []
	for c in D.CUBES:
		var c2: String = c
		var left: int = int(st.supply[c]) - sel["list"].count(c)
		var b := Button.new()
		b.text = "%s (%d)" % [D.cube_name(c), left]
		b.custom_minimum_size = Vector2(150, 48)
		b.icon = null
		var col: Color = D.CUBE[c]["color"]
		b.add_theme_stylebox_override("normal", UI.panel_style(col, UI.GOLD if c in hl else col.darkened(0.5), 3, 6))
		b.add_theme_stylebox_override("hover", UI.panel_style(col.lightened(0.15), UI.GOLD, 3, 6))
		b.disabled = left <= 0 or sel["list"].size() >= k
		b.pressed.connect(func():
			sel["list"].append(c2)
			_show_decision())
		f.add_child(b)
	var chosen := HBoxContainer.new()
	chosen.add_theme_constant_override("separation", 6)
	chosen.add_child(UI.label("Scelti: ", 20, UI.INK, UI.font_bold))
	for c in sel["list"]:
		chosen.add_child(UI.cube_icon(c, 28))
	act_body.add_child(chosen)
	var f2 := _flow()
	var ok := UI.primary(UI.button("Conferma", 180, 46, 21))
	ok.disabled = sel["list"].size() < k and _supply_left() > 0
	ok.pressed.connect(func(): _provide(sel["list"].duplicate()))
	f2.add_child(ok)
	var rs := UI.button("Ricomincia", 160, 46, 21)
	rs.pressed.connect(func():
		sel["list"] = []
		_show_decision())
	f2.add_child(rs)


func _supply_left() -> int:
	var t := 0
	for c in D.CUBES:
		t += maxi(0, int(st.supply[c]) - sel["list"].count(c))
	return t


func _good_ui() -> void:
	var f := _flow()
	for g in pending["options"]:
		var g2: String = g
		var b := _btn(D.good_name(g), func(): _provide(g2), hint.get("r", "") == g)
		b.icon = UI.token(g)
		b.expand_icon = true
		b.custom_minimum_size = Vector2(170, 64)
		f.add_child(b)


func _priv_ui() -> void:
	var f := _flow()
	for l in pending["options"]:
		var l2: int = l
		f.add_child(_btn("%d° livello: %s" % [l, D.PRIV[l]], func(): _provide(l2), hint.get("r", -1) == l))
	f.add_child(_btn("Nessun privilegio", func(): _provide(0)))


func _inn_ui() -> void:
	var f := _flow()
	var opts: Array = pending["options"]
	for d in st.decks.size():
		if st.decks[d].is_empty():
			continue
		var top: int = st.decks[d][-1]
		var d2: int = d
		var b := Button.new()
		b.custom_minimum_size = Vector2(150, 238)
		b.icon = UI.villager(top)
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.tooltip_text = "%s · costa %s\n%s" % [D.VILLAGERS[top]["name"], D.cost_text(D.VILLAGERS[top]["cost"]), D.VILLAGERS[top]["text"]]
		b.disabled = not (d in opts)
		if hint.get("r", -2) == d:
			UI.selected(b, "meadow")
		b.pressed.connect(func(): _provide(d2))
		f.add_child(b)
	var no := UI.button("Nessuno", 160, 238, 21)
	no.pressed.connect(func(): _provide(-1))
	f.add_child(no)
	act_body.add_child(UI.label("Passa il mouse sulle carte per leggerne l'effetto.", 17, UI.INK2, UI.font_italic))


func _island_ui() -> void:
	var opts: Dictionary = pending["opts"]
	var isl: String = pending["isl"]
	if not sel.has("sell"):
		sel = {"sell": opts["sell"].duplicate(), "take": opts["take"], "take2": false, "mission": (opts["mission"][0] if not opts["mission"].is_empty() else -1)}
	var f := _flow()
	for g in opts["sell"]:
		var g2: String = g
		var on: bool = g in sel["sell"]
		f.add_child(_btn(("» " if on else "") + "Vendi %s (%d punti)" % [D.good_name(g), D.SEA[isl]["sell"][g]], func():
			if g2 in sel["sell"]:
				sel["sell"].erase(g2)
			else:
				sel["sell"].append(g2)
			_show_decision(), on))
	if opts["take"]:
		var kind: String = D.SEA[isl]["stack"]
		f.add_child(_btn(("» " if sel["take"] else "") + "Carica %s" % ("un forziere" if kind == "chest" else D.good_name(kind)), func():
			sel["take"] = not sel["take"]
			_show_decision(), sel["take"]))
		if opts["take2"]:
			f.add_child(_btn(("» " if sel["take2"] else "") + "Quartiermastro: caricane 2", func():
				sel["take2"] = not sel["take2"]
				_show_decision(), sel["take2"]))
	for mid in opts["mission"]:
		var m2: int = mid
		var on2: bool = int(sel["mission"]) == mid
		f.add_child(_btn(("» " if on2 else "") + "Missione con il familiare %d (%d punti)" % [st.members[mid]["gen"], D.SEA[isl]["mpp"]], func():
			sel["mission"] = -1 if int(sel["mission"]) == m2 else m2
			_show_decision(), on2))
	var ok := UI.primary(UI.button("Conferma", 180, 44, 20))
	ok.pressed.connect(func(): _provide(sel.duplicate(true)))
	f.add_child(ok)


func _list_ui(labels: Array, allow_none: bool) -> void:
	var col := VBoxContainer.new()
	act_body.add_child(col)
	for i in labels.size():
		var i2 := i
		col.add_child(_btn(labels[i], func(): _provide(i2), hint.get("r", -1) == i))
	if allow_none:
		col.add_child(_btn("Niente", func(): _provide(-1)))


func _herb_ui() -> void:
	var f := _flow()
	f.add_child(_btn("Lascia il segnatempo dov'è", func(): _provide("stay"), true))
	f.add_child(_btn("Subito prima del ponte (la prossima morte arriva presto)", func(): _provide("before")))
	f.add_child(_btn("Subito dopo il ponte (la prossima morte si allontana)", func(): _provide("after")))


func _noble_ui() -> void:
	var r = hint.get("r", {})
	for d in pending["decks"].size():
		var deck: Array = pending["decks"][d]
		if deck.is_empty():
			continue
		act_body.add_child(UI.label("Mazzo %d" % (d + 1), 20, UI.INK, UI.font_bold))
		var f := _flow()
		for cid in deck:
			var d2: int = d
			var c2: int = cid
			var b := Button.new()
			b.custom_minimum_size = Vector2(76, 120)
			b.icon = UI.villager(cid)
			b.expand_icon = true
			b.tooltip_text = "%s: %s" % [D.VILLAGERS[cid]["name"], D.VILLAGERS[cid]["text"]]
			if r is Dictionary and int(r.get("c", -1)) == cid:
				UI.selected(b, "meadow")
			b.pressed.connect(func(): _provide({"d": d2, "c": c2}))
			f.add_child(b)


func _city_ui() -> void:
	var f := _flow()
	var targets := {}
	for c in pending["options"]:
		var c2: String = c
		var rw: String = {"pp3": "3 punti", "coin": "1 moneta", "cubes2": "2 cubi a scelta"}[D.CITY[c]["reward"]]
		f.add_child(_btn("%s (%s)" % [D.CITY[c]["name"], rw], func(): _provide(c2), hint.get("r", "") == c))
		targets["c:" + c] = Board3D.px(D.CITY[c]["pos"])
		target_map["c:" + c] = func(): _provide(c2)
		target_info["c:" + c] = "%s: %s" % [D.CITY[c]["name"], rw]
	board.set_targets(targets)


func _member_ui(ids: Array, map: Callable) -> void:
	var f := _flow()
	var targets := {}
	for id in ids:
		var id2: int = id
		f.add_child(_btn("%s (%s)" % [Describe.member(st, id), st.loc_name(st.members[id]["loc"])], func(): _provide(map.call(id2)), hint.get("r", -1) == id))
		targets["m:%d" % id] = board.member_pos(id)
		target_map["m:%d" % id] = func(): _provide(map.call(id2))
		target_info["m:%d" % id] = Describe.member(st, id)
	board.set_targets(targets)


func _yesno_ui() -> void:
	var f := _flow()
	var key: String = pending["key"]
	var cid := st.card_id(key)
	act_body.add_child(UI.wrap(D.VILLAGERS[cid]["text"], 19, MW - 60, UI.INK2, UI.font_italic))
	f.add_child(_btn("Sì, gioca %s" % D.VILLAGERS[cid]["name"], func(): _provide(true), hint.get("r", false) == true))
	f.add_child(_btn("No, la tengo", func(): _provide(false), hint.get("r", true) == false))


func _market_ui() -> void:
	var opts: Array = pending["options"]
	var f := _flow()
	var s: int = pending["seat"]
	var hr = hint.get("r", -1)
	for i in opts.size():
		var o: Dictionary = opts[i]
		var i2 := i
		match str(o["k"]):
			"cust":
				var ci: int = (st.front if o["where"] == "f" else st.queue)[int(o["i"])]
				var cu: Dictionary = D.CUSTOMERS[ci]
				var b := Button.new()
				b.custom_minimum_size = Vector2(240, 90)
				b.icon = UI.customer(ci)
				b.expand_icon = true
				b.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
				b.text = "%d punti\n%s%s" % [cu["pp"], Describe.need_text(cu["need"]), " (in coda)" if o["where"] == "q" else ""]
				b.add_theme_font_size_override("font_size", 18)
				if hr == i:
					UI.selected(b, "meadow")
				b.pressed.connect(func(): _provide(i2))
				f.add_child(b)
			"cocoa":
				f.add_child(_btn("Vendi un cesto di cacao (%d punti)" % D.COCOA_PP, func(): _provide(i2), hr == i))
			"tea":
				f.add_child(_btn("Vendi una balla di tè (%d punti e 1 moneta)" % D.TEA_PP, func(): _provide(i2), hr == i))
			"pass":
				var p := UI.button("Passa (non vendi più oggi)", 0, 90, 19)
				if hr == i:
					UI.selected(p, "meadow")
				p.pressed.connect(func(): _provide(i2))
				f.add_child(p)


func _scrap_ui() -> void:
	var f := _flow()
	for i in pending["options"]:
		var i2: int = i
		var ci: int = st.front[i]
		var b := Button.new()
		b.custom_minimum_size = Vector2(200, 80)
		b.icon = UI.customer(ci)
		b.expand_icon = true
		b.text = "%d punti" % D.CUSTOMERS[ci]["pp"]
		if hint.get("r", -2) == i:
			UI.selected(b, "meadow")
		b.pressed.connect(func(): _provide(i2))
		f.add_child(b)
	f.add_child(_btn("No, tengo il Rigattiere", func(): _provide(-1)))


func _pick_members_ui(ids: Array, mx: int, ok_text: String) -> void:
	if not sel.has("picks"):
		sel["picks"] = []
		if hint.get("r", null) is Array:
			sel["picks"] = hint["r"].duplicate()
	var f := _flow()
	for id in ids:
		var id2: int = id
		var m: Dictionary = st.members[id]
		var on: bool = id in sel["picks"]
		f.add_child(_btn(("» " if on else "") + "%s %d" % [st.pname(m["owner"]), m["gen"]], func():
			if id2 in sel["picks"]:
				sel["picks"].erase(id2)
			elif sel["picks"].size() < mx:
				sel["picks"].append(id2)
			_show_decision(), on))
	var f2 := _flow()
	var ok := UI.primary(UI.button("%s (%d)" % [ok_text, sel["picks"].size()], 0, 46, 20))
	ok.pressed.connect(func(): _provide(sel["picks"].duplicate()))
	f2.add_child(ok)
	var no := UI.button("Nessuno", 160, 46, 20)
	no.pressed.connect(func(): _provide([]))
	f2.add_child(no)


func _mass_up_ui() -> void:
	var s: int = pending["seat"]
	if not sel.has("moves"):
		sel["moves"] = (hint["r"] as Dictionary).duplicate() if hint.get("r", null) is Dictionary else {}
	var grain: int = st.players[s]["grain"]
	var tot := 0
	for id in sel["moves"]:
		tot += VLState.climb_cost(int(str(st.members[id]["loc"]).substr(7)), int(sel["moves"][id]))
	act_body.add_child(UI.label("Grano: %d · costo scelto: %d. Tra le vetrate: 1, 2 e 4 grano." % [grain, tot], 19, UI.RED if tot > grain else UI.INK2, UI.font_italic))
	for id in pending["members"]:
		var id2: int = id
		var m: Dictionary = st.members[id]
		var w0 := int(str(m["loc"]).substr(7))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(UI.label("Familiare %d (vetrata da %d):" % [m["gen"], D.WINDOW_PTS[w0]], 19, UI.INK, UI.font_bold))
		for w in range(w0, 4):
			var w2 := w
			var cur: int = int(sel["moves"].get(id, w0))
			var b := UI.button("%d punti%s" % [D.WINDOW_PTS[w], "" if w == w0 else " (%d grano)" % VLState.climb_cost(w0, w)], 0, 40, 18)
			if cur == w:
				UI.selected(b, "meadow")
			b.pressed.connect(func():
				if w2 == w0:
					sel["moves"].erase(id2)
				else:
					sel["moves"][id2] = w2
				_show_decision())
			row.add_child(b)
		act_body.add_child(row)
	var f := _flow()
	var ok := UI.primary(UI.button("Conferma", 180, 44, 20))
	ok.disabled = tot > grain
	ok.pressed.connect(func(): _provide(sel["moves"].duplicate()))
	f.add_child(ok)
	f.add_child(_btn("Nessuno sale", func(): _provide({})))


func _death_ui() -> void:
	var bard: bool = pending.get("bard", false)
	if not sel.has("bard"):
		sel["bard"] = hint.get("r", {}).get("bard", false) if hint.get("r", null) is Dictionary else false
	var hr = hint.get("r", {})
	var f := _flow()
	var targets := {}
	for id in pending["options"]:
		var id2: int = id
		var m: Dictionary = st.members[id]
		var sec := st.section_of(str(m["loc"]))
		var dest := "tomba anonima"
		if sec != "":
			var free := false
			for v in st.chron[sec]:
				if int(v) == -1:
					free = true
			dest = "cronache (%s)" % D.SECTION[sec]["name"] if free else ("sepoltura in mare" if st.port and (m["loc"] == "ship" or str(m["loc"]).begins_with("mission:")) else "tomba anonima")
		f.add_child(_btn("Familiare %d (%s) » %s" % [m["gen"], st.loc_name(m["loc"]), "cronache (Bardo)" if sel["bard"] else dest], func(): _provide({"m": id2, "bard": sel["bard"]}), hr is Dictionary and int(hr.get("m", -1)) == id))
		targets["m:%d" % id] = board.member_pos(id)
		target_map["m:%d" % id] = func(): _provide({"m": id2, "bard": sel["bard"]})
		target_info["m:%d" % id] = "Familiare %d (%s)" % [m["gen"], st.loc_name(m["loc"])]
	board.set_targets(targets)
	if bard:
		var c := CheckBox.new()
		c.text = "Usa il Bardo: va comunque nelle cronache, in più"
		c.button_pressed = sel["bard"]
		c.toggled.connect(func(on):
			sel["bard"] = on
			_show_decision())
		act_body.add_child(c)


func _on_target(key: String) -> void:
	if pending.is_empty() or not target_map.has(key):
		return
	(target_map[key] as Callable).call()


func _on_hover(key: String) -> void:
	if key == "" or not target_info.has(key):
		tip.visible = false
		return
	tip_lbl.text = target_info[key]
	tip.reset_size()
	var mp := get_viewport().get_mouse_position()
	tip.position = (mp + Vector2(18, 18)).clamp(Vector2.ZERO, Vector2(1920, 1080) - tip.size)
	tip.visible = true


# =================================================================== finestre

func _clear_modal() -> void:
	for c in modal.get_children():
		modal.remove_child(c)
		c.queue_free()
	modal.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _open_modal(title_text: String, w := 700.0) -> VBoxContainer:
	_clear_modal()
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.1, 0.05, 0.02, 0.55)
	shade.size = Vector2(1920, 1080)
	modal.add_child(shade)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UI.paper(false, 34))
	box.custom_minimum_size = Vector2(w, 0)
	modal.add_child(box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	box.add_child(vb)
	var t := UI.title(title_text, 38)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(w - 30, 0)
	vb.add_child(t)
	_center_full.call_deferred(box)
	return vb


func _center_full(box: Control) -> void:
	if not is_instance_valid(box):
		return
	box.reset_size()
	box.position = Vector2(960, 520) - box.size / 2.0


func _curtain(s: int, then: Callable) -> void:
	_clear_modal()
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.12, 0.07, 0.03, 0.97)
	shade.size = Vector2(1920, 1080)
	modal.add_child(shade)
	var vb := VBoxContainer.new()
	vb.position = Vector2(700, 340)
	vb.add_theme_constant_override("separation", 20)
	modal.add_child(vb)
	vb.add_child(UI.icon_rect(UI.tex("res://assets/ui/meeple_%s.png" % D.COLORS[st.players[s]["color"]]["key"]), Vector2(120, 120)))
	vb.add_child(UI.title("Tocca a %s" % engine.pname(s), 54, UI.LIGHT))
	vb.add_child(UI.label("Gli altri non guardino: carte e obiettivi sono segreti.", 24, UI.SAND))
	var b := UI.primary(UI.button("Sono pronto", 280, 60, 26))
	b.pressed.connect(func():
		_clear_modal()
		then.call())
	vb.add_child(b)


func _on_pause(req: Dictionary) -> void:
	match str(req.get("type", "")):
		"mass_end":
			var vb := _open_modal("Fine della messa" if not req.get("final", false) else "La messa finale", 720)
			var drawn: Array = req.get("drawn", [])
			if drawn.is_empty():
				vb.add_child(UI.label("Dal sacchetto nero sono usciti solo frati.", 22, UI.INK2))
			else:
				var parts := []
				for id in drawn:
					parts.append("%s (%d)" % [st.pname(st.members[id]["owner"]), st.members[id]["gen"]])
				vb.add_child(UI.wrap("Entrano in chiesa: " + ", ".join(parts) + ".", 22, 660))
			var win: Array = req.get("win", [])
			if not win.is_empty():
				vb.add_child(UI.wrap("Maggioranza in chiesa: %s (+2 punti)." % " e ".join(win.map(func(s): return engine.pname(s))), 22, 660, UI.GREEN, UI.font_bold))
			var ok := UI.primary(UI.button("Risultati" if req.get("final", false) else "Nuovo round", 260, 56, 24))
			ok.pressed.connect(func():
				_clear_modal()
				engine.provide_decision(null))
			vb.add_child(ok)
		"end_triggered":
			var vb2 := _open_modal("Le cronache del villaggio sono quasi complete!", 760)
			vb2.add_child(UI.wrap("%s ha occupato l'ultimo posto libero. Ora ogni altra famiglia fa un'ultima azione; poi la messa finale e il punteggio." % engine.pname(int(req.get("by", 0))), 22, 700))
			var ok2 := UI.primary(UI.button("Avanti", 220, 56, 24))
			ok2.pressed.connect(func():
				_clear_modal()
				engine.provide_decision(null))
			vb2.add_child(ok2)
		_:
			engine.provide_decision(null)


func _on_game_end(results: Array) -> void:
	Audio.play("win")
	if online != null:
		online.finish()
		online_status("")
	refresh()
	var vb := _open_modal("La famiglia %s sarà ricordata per sempre!" % engine.pname(results[0]["seat"]), 1240)
	var grid := GridContainer.new()
	grid.columns = 12
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 6)
	for h in ["", "Famiglia", "Percorso", "Viaggi", "Consiglio", "Chiesa", "Cronache", "Clienti", "Monete", "Carte", "Borsaiola", "Totale"]:
		grid.add_child(UI.label(h, 19, UI.INK2, UI.font_bold))
	var place := 1
	for e in results:
		var p: Dictionary = st.players[e["seat"]]
		grid.add_child(UI.title("%d°" % place, 30, UI.BRICK))
		var nm := UI.label(p["name"] + (" (IA)" if p["ai"] else ""), 24, UI.ink_of(p["color"]), UI.font_bold)
		nm.custom_minimum_size = Vector2(190, 0)
		grid.add_child(nm)
		for k in ["track", "travel", "council", "church", "chron", "customers", "coins", "cards", "cutpurse"]:
			grid.add_child(UI.label(str(e[k]), 23, UI.INK, UI.font_bold))
		grid.add_child(UI.label(str(e["total"]), 30, UI.BRICK, UI.font_heavy))
		place += 1
	vb.add_child(grid)
	vb.add_child(UI.label("Spareggio: più clienti serviti, poi più familiari vivi.", 18, UI.INK2, UI.font_italic))
	var br := HBoxContainer.new()
	br.add_theme_constant_override("separation", 16)
	br.alignment = BoxContainer.ALIGNMENT_CENTER
	if online == null:
		var again := UI.primary(UI.button("Rigioca", 220, 60, 26))
		again.pressed.connect(func():
			var cfg := config.duplicate(true)
			cfg.erase("seed")
			main.start_game(cfg))
		br.add_child(again)
	var see := UI.button("Guarda il villaggio", 280, 60, 24)
	see.pressed.connect(func():
		_clear_modal()
		_clear_body()
		act_title.text = "Partita finita."
		var f := _flow()
		var m := UI.button("Risultati", 180, 50, 22)
		m.pressed.connect(func(): _on_game_end(results))
		f.add_child(m)
		var mm := UI.button("Menu", 140, 50, 22)
		mm.pressed.connect(func(): main.show_menu())
		f.add_child(mm)
		_place_action.call_deferred())
	br.add_child(see)
	var menu := UI.button("Menu", 180, 60, 26)
	menu.pressed.connect(func(): main.show_menu())
	br.add_child(menu)
	vb.add_child(br)


func _ask_quit() -> void:
	var layer := Control.new()
	layer.size = Vector2(1920, 1080)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(layer)
	var shade := ColorRect.new()
	shade.color = Color(0.1, 0.05, 0.02, 0.6)
	shade.size = layer.size
	layer.add_child(shade)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UI.paper(false, 30))
	box.position = Vector2(660, 400)
	layer.add_child(box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	box.add_child(vb)
	vb.add_child(UI.title("Tornare al menu?", 32))
	vb.add_child(UI.label("La partita in corso andrà persa." if online == null else "Potrai rientrare nella stanza con lo stesso codice.", 22))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	var y := UI.primary(UI.button("Sì, al menu", 240, 56, 24))
	y.pressed.connect(func(): main.show_menu())
	var no := UI.button("Continua a giocare", 300, 56, 24)
	no.pressed.connect(func(): layer.queue_free())
	hb.add_child(y)
	hb.add_child(no)
	vb.add_child(hb)


func _show_rules_popup() -> void:
	var layer := Control.new()
	layer.size = Vector2(1920, 1080)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(layer)
	var shade := ColorRect.new()
	shade.color = Color(0.1, 0.05, 0.02, 0.75)
	shade.size = layer.size
	layer.add_child(shade)
	var rv := preload("res://scripts/ui/rules_view.gd").new()
	rv.embedded = true
	rv.on_close = func(): layer.queue_free()
	layer.add_child(rv)


func _show_log() -> void:
	var layer := Control.new()
	layer.size = Vector2(1920, 1080)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(layer)
	var shade := ColorRect.new()
	shade.color = Color(0.1, 0.05, 0.02, 0.7)
	shade.size = layer.size
	layer.add_child(shade)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UI.paper(false, 30))
	box.position = Vector2(360, 70)
	box.size = Vector2(1200, 940)
	layer.add_child(box)
	var vb := VBoxContainer.new()
	box.add_child(vb)
	vb.add_child(UI.title("Diario del villaggio", 38))
	var t := RichTextLabel.new()
	t.custom_minimum_size = Vector2(1170, 800)
	t.scroll_following = true
	t.add_theme_font_size_override("normal_font_size", 20)
	t.text = "\n".join(engine.log_lines)
	vb.add_child(t)
	var c := UI.button("Chiudi", 180, 50, 22)
	c.pressed.connect(func(): layer.queue_free())
	vb.add_child(c)


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed:
		match ev.keycode:
			KEY_Q: board.rotate_view(-30)
			KEY_E: board.rotate_view(30)
			KEY_HOME: board.reset_view()
			KEY_TAB: _toggle_flat()


# =================================================================== online

func _build_online_label() -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.plank("meadow", 12))
	p.position = Vector2(LX + LW + 400, 92)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	online_lbl = UI.label("", 22, UI.LIGHT, UI.font_bold)
	p.add_child(online_lbl)
	add_child(p)
	p.visible = false
	online_lbl.set_meta("box", p)


func online_status(t: String) -> void:
	if online_lbl == null:
		return
	online_lbl.text = t
	(online_lbl.get_meta("box") as Control).visible = t != ""


func online_waiting(seat: int, is_slow: bool) -> void:
	if seat < 0:
		online_status("")
		return
	var t := "Online · stanza %s · tocca a %s" % [online.code, engine.pname(seat)]
	if is_slow:
		t += " (sta pensando da più di un minuto)"
	online_status(t)


func online_caught_up() -> void:
	online_status("")
	refresh()


## L'IA ha già giocato al posto di questo giocatore: si chiude il dialogo aperto.
func online_cancel_decision(t: String) -> void:
	pending = {}
	_clear_modal()
	_clear_body()
	board.set_targets({})
	refresh()
	online_status(t)
