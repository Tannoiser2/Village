extends Control
## Vista di gioco: il villaggio in 3D al centro, le plance delle famiglie a sinistra, mercato, cronache,
## Locanda, Porto e l'ultima azione a destra, le decisioni in basso. I cubi si prendono cliccandoli sulla
## mappa; gli altri bersagli selezionabili si illuminano.

const D = preload("res://scripts/data/vl_data.gd")
const LX := 10.0
const LW := 470.0
const RX := 1546.0
const RW := 364.0
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
var rows_box: VBoxContainer
var side_box: VBoxContainer
var last_lbl: RichTextLabel
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


func _build_left() -> void:
	var sc := ScrollContainer.new()
	sc.position = Vector2(LX, 8)
	sc.size = Vector2(LW, 1064)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(sc)
	rows_box = VBoxContainer.new()
	rows_box.add_theme_constant_override("separation", 5)
	rows_box.custom_minimum_size = Vector2(LW - 8, 0)
	sc.add_child(rows_box)


func _build_right() -> void:
	var p := _panel(Vector2(RX, 8), Vector2(RW, 1064))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	p.add_child(vb)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(sc)
	side_box = VBoxContainer.new()
	side_box.add_theme_constant_override("separation", 6)
	side_box.custom_minimum_size = Vector2(RW - 44, 0)
	sc.add_child(side_box)
	# l'ultima azione (tutto il resto è nel Diario)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UI.paper(true, 10))
	vb.add_child(box)
	last_lbl = RichTextLabel.new()
	last_lbl.bbcode_enabled = true
	last_lbl.fit_content = true
	last_lbl.scroll_active = false
	last_lbl.custom_minimum_size = Vector2(RW - 60, 58)
	last_lbl.add_theme_font_size_override("normal_font_size", 18)
	last_lbl.add_theme_font_override("normal_font", UI.font_body)
	last_lbl.add_theme_color_override("default_color", UI.INK)
	last_lbl.tooltip_text = "L'ultima azione: il racconto completo è nel Diario"
	box.add_child(last_lbl)


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
	var side := clampf(floorf((1060.0 - (st.n - 1) * 5.0) / st.n) - 26.0, 170.0, 250.0)
	for s in st.n:
		rows_box.add_child(_player_row(s, side))


## Una famiglia: la sua plancia originale (cubi, grano, familiari, segnatempo) e accanto il resto.
func _player_row(s: int, side: float) -> Control:
	var pl: Dictionary = st.players[s]
	var col: Color = UI.ink_of(pl["color"])
	var box := PanelContainer.new()
	var active: bool = engine.current == s and not engine.game_over
	var sb := UI.paper(active, 8)
	box.add_theme_stylebox_override("panel", sb)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	var see := _can_see(s)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	box.add_child(hb)
	var fp := FarmPanel.new()
	fp.setup(st, s, side)
	if active:
		var fr := Panel.new()
		fr.set_anchors_preset(Control.PRESET_FULL_RECT)
		fr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var fsb := StyleBoxFlat.new()
		fsb.bg_color = Color(0, 0, 0, 0)
		fsb.border_color = UI.GOLD
		fsb.set_border_width_all(4)
		fr.add_theme_stylebox_override("panel", fsb)
		fp.add_child(fr)
	hb.add_child(fp)
	var iw := LW - side - 40.0
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	vb.custom_minimum_size = Vector2(iw, 0)
	hb.add_child(vb)
	# nome e prestigio
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 4)
	vb.add_child(top)
	var nm := UI.title(pl["name"] + (" (IA)" if pl["ai"] else ""), 23, col)
	nm.clip_text = true
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.custom_minimum_size = Vector2(60, 0)
	top.add_child(nm)
	var ppl := UI.label("%d" % pl["pp"], 30, UI.INK, UI.font_heavy)
	ppl.tooltip_text = "Punti prestigio sul percorso (i punti finali si aggiungono alla fine)"
	ppl.mouse_filter = Control.MOUSE_FILTER_STOP
	top.add_child(ppl)
	var tags := []
	if st.first == s:
		tags.append("primo giocatore")
	if st.next_owner == s:
		tags.append("prossimo primo")
	if int(pl["deaths"]) > 0:
		tags.append("un familiare sta per morire")
	if not tags.is_empty():
		vb.add_child(UI.wrap(" · ".join(tags), 15, iw, UI.BRICK, UI.font_bold))
	# monete e merci
	var rr := HFlowContainer.new()
	rr.add_theme_constant_override("h_separation", 6)
	rr.add_theme_constant_override("v_separation", 0)
	vb.add_child(rr)
	var cc := UI.counter(UI.token("coin"), pl["coins"], 26)
	cc.tooltip_text = "Monete"
	cc.mouse_filter = Control.MOUSE_FILTER_STOP
	rr.add_child(cc)
	for g in D.GOODS:
		if int(pl["goods"][g]) > 0:
			var gc := UI.counter(UI.token(g), pl["goods"][g], 26)
			gc.tooltip_text = D.good_name(g, int(pl["goods"][g]))
			gc.mouse_filter = Control.MOUSE_FILTER_STOP
			rr.add_child(gc)
	# clienti serviti, famiglia da nascere, sacchetto, città
	var pool := 0
	var bag := 0
	for m in st.members:
		if m["owner"] != s:
			continue
		if m["loc"] == "pool":
			pool += 1
		elif m["loc"] == "bag":
			bag += 1
	var cust: Array = pl["customers"]
	var info := []
	if see:
		var cp := 0
		for ci in cust:
			cp += int(D.CUSTOMERS[ci]["pp"])
		info.append("clienti %d (%d punti)" % [cust.size(), cp])
	else:
		info.append("clienti %d" % cust.size())
	info.append("da nascere %d" % pool)
	if bag > 0:
		info.append("nel sacchetto %d" % bag)
	if not st.port:
		info.append("città %d" % pl["cities"].size())
	info.append("cronache %d" % st.chron_count(s))
	vb.add_child(UI.wrap(" · ".join(info), 15, iw, UI.INK2))
	# carte abitante e obiettivi di vita (miniature, testo nel suggerimento)
	var cf := HFlowContainer.new()
	cf.add_theme_constant_override("h_separation", 3)
	cf.add_theme_constant_override("v_separation", 3)
	if see:
		for cid in pl["hand"]:
			var t := UI.icon_rect(UI.villager(cid), Vector2(30, 48))
			t.mouse_filter = Control.MOUSE_FILTER_STOP
			t.tooltip_text = "%s (%s): %s" % [D.VILLAGERS[cid]["name"], _kind_text(D.VILLAGERS[cid]["kind"]), D.VILLAGERS[cid]["text"]]
			cf.add_child(t)
		if st.goals_on:
			for g in pl["goals"]:
				var gt := UI.icon_rect(UI.goal_tex(g), Vector2(30, 48))
				gt.mouse_filter = Control.MOUSE_FILTER_STOP
				gt.tooltip_text = "Obiettivo di vita · " + Describe.goal_text(g)
				cf.add_child(gt)
	else:
		if st.inn and pl["hand"].size() > 0:
			cf.add_child(UI.label("abitanti %d" % pl["hand"].size(), 15, UI.INK2))
		if st.goals_on and pl["goals"].size() > 0:
			cf.add_child(UI.label("obiettivi segreti %d" % pl["goals"].size(), 15, UI.INK2, UI.font_italic))
	if cf.get_child_count() > 0:
		vb.add_child(cf)
	if st.goals_on:
		for g in pl["goals_done"]:
			vb.add_child(UI.wrap("Fatto: " + st.goal_def(g)["name"], 15, iw, UI.GREEN, UI.font_bold))
	if st.port:
		var sh: Dictionary = pl["ship"]
		var hold := []
		for it in sh["hold"]:
			var kind := str(it).get_slice(":", 0)
			hold.append("familiare" if kind == "member" else ("forziere" if kind == "chest" else ("grano" if kind == "grain" else D.good_name(kind))))
		if int(sh["cap"]) >= 0:
			var ct := UI.icon_rect(UI.captain_tex(int(sh["cap"])), Vector2(30, 48))
			ct.mouse_filter = Control.MOUSE_FILTER_STOP
			ct.tooltip_text = _captain_text(int(sh["cap"]))
			cf.add_child(ct)
			if cf.get_parent() == null:
				vb.add_child(cf)
		var where: String = "in porto" if sh["at"] == "P" else D.SEA[sh["at"]].get("name", "in mare")
		var ct := "Nave %s%s%s" % [where, (" · capitano da %d" % int(D.CAPTAINS[int(sh["cap"])]["cost"])) if int(sh["cap"]) >= 0 and int(sh["cap"]) < 100 else (" · Ammiraglio" if int(sh["cap"]) == 100 else ""), (" · stiva: " + ", ".join(hold)) if not hold.is_empty() else ""]
		vb.add_child(UI.wrap(ct, 15, iw, UI.INK2, UI.font_italic))
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
	if not board.chron_on_map():
		# con la Locanda le cronache non sono sul tabellone: si vedono qui
		side_box.add_child(UI.title("Cronache del villaggio", 26))
		var cp := ChronPanel.new()
		cp.setup(st, RW - 48)
		side_box.add_child(cp)
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
		side_box.add_child(UI.title("Porto · capitani", 26))
		side_box.add_child(UI.wrap("Per salpare prendi un cubo dallo spazio Viaggio e ingaggia uno di questi capitani.", 15, RW - 50, UI.INK2, UI.font_italic))
		for k in 3:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 3)
			var lab := UI.label("%d %s" % [k + 1, "moneta" if k == 0 else "monete"], 15, UI.INK, UI.font_bold)
			lab.custom_minimum_size = Vector2(66, 0)
			row.add_child(lab)
			if st.captains[k].is_empty():
				row.add_child(UI.label("finiti", 15, UI.INK2, UI.font_italic))
			for c in st.captains[k]:
				var t := UI.icon_rect(UI.captain_tex(c), Vector2(48, 76))
				t.mouse_filter = Control.MOUSE_FILTER_STOP
				t.tooltip_text = _captain_text(c)
				row.add_child(t)
			side_box.add_child(row)
		var mi := []
		for isl in D.MISSIONS:
			if int(st.missions[isl]) >= 0:
				mi.append("%s (%s)" % [D.SEA[isl]["name"], st.pname(st.members[int(st.missions[isl])]["owner"])])
		if not mi.is_empty():
			side_box.add_child(UI.wrap("Missioni: " + ", ".join(mi), 16, RW - 50, UI.INK2))


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


## L'ultima riga del racconto (con la precedente, se è corta).
func _show_last() -> void:
	var lines: Array = engine.log_lines
	var out := []
	var i := lines.size() - 1
	while i >= 0 and out.size() < 2:
		var l := str(lines[i])
		if l.strip_edges() != "":
			if l.begins_with("—"):
				out.push_front("[b][color=#8a2a14]%s[/color][/b]" % l)
				break
			out.push_front(l)
		i -= 1
	if out.size() == 2:
		out[0] = "[color=#6b4a2b]%s[/color]" % out[0]
	last_lbl.text = "\n".join(out)


func _on_log(_t: String) -> void:
	_show_last()
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
		"family": _family_ui()
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
	_leave_sea()
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
		_leave_sea()
		wiz = {}
		sel = {}
		_show_decision())
	f.add_child(b)


## Fine della pianificazione per mare: via l'anteprima della rotta, la telecamera torna al villaggio.
func _leave_sea() -> void:
	if wiz.get("step", "") == "sail":
		board.set_path(-1, [])
		board.reset_view()


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
	# scelta del cubo: si clicca il mucchietto del colore voluto sulla mappa
	var targets := {}
	var spaces := {}
	for m in moves:
		var src: Dictionary = m["src"]
		if src["t"] == "space":
			if not spaces.has(src["sp"]):
				spaces[src["sp"]] = {}
			spaces[src["sp"]][src["c"]] = true
	var hkey := ""
	for sp in spaces:
		var groups := board.cube_groups(sp)
		for c in spaces[sp]:
			var key: String = "cube:%s:%s" % [sp, c]
			var n: int = groups[c]["n"] if groups.has(c) else 1
			targets[key] = [board.cube_pos(sp, c), 0.24 if n <= 2 else 0.3]
			var src2 := {"t": "space", "sp": sp, "c": c}
			target_map[key] = func(): _pick_src(src2)
			target_info[key] = "%s: prendi un cubo %s%s" % [D.SPACE[sp]["name"], D.cube_name(c), " (peste: perdi 2 tempi)" if c == "pl" else ""]
			if not hm.is_empty() and hm["src"].get("t", "") == "space" and hm["src"]["sp"] == sp and hm["src"]["c"] == c:
				hkey = key
	board.set_targets(targets, hkey)
	if not spaces.is_empty():
		act_title.text = _who() + ("Ultima azione: clicca un cubo sulla mappa" if req.get("final", false) else "Il tuo turno: clicca sulla mappa il cubo che vuoi prendere")
		if hkey != "":
			act_body.add_child(UI.label("Consiglio dell'IA: %s (anello verde)." % target_info[hkey], 17, UI.GREEN, UI.font_italic))
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
		var wb := _rich_btn(["Pozzo: paga", {"cube": c}, {"cube": c}, {"cube": c}, "» azione a scelta"], not hm.is_empty() and hm["src"]["t"] == "well" and hm["src"]["c"] == c)
		wb.pressed.connect(func(): _pick_src(src2))
		f.add_child(wb)
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
	# le azioni raggruppate per riga (un edificio, un tipo di azione), ogni scelta un pulsante breve con icone
	var groups := {}
	var order := []
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
		if a.get("a", "") == "craft":
			continue      # gli Artigiani hanno il loro pannello a interruttori
		var ch := _chip(s, a)
		var g: String = ch["group"]
		if not groups.has(g):
			groups[g] = {"icon": ch.get("gicon", null), "items": []}
			order.append(g)
		var idx := i
		var hl: bool = not hm.is_empty() and _same(hm, m)
		groups[g]["items"].append({"parts": ch["parts"], "idx": idx, "hl": hl, "tip": Describe.action(st, s, a)})
		# bersagli sul tabellone per scegliere la città
		var key := _target_key(a)
		if key != "" and not targets.has(key):
			targets[key] = _target_pos(a)
			target_map[key] = func(): _provide(idx)
			target_info[key] = Describe.action(st, s, a)
	board.set_targets(targets)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	act_body.add_child(box)
	if sp == "crafts":
		_crafts_panel(box, src, s)
	for g in order:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		box.add_child(row)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 4)
		head.custom_minimum_size = Vector2(150, 0)
		if groups[g]["icon"] != null:
			head.add_child(UI.icon_rect(groups[g]["icon"], Vector2(30, 30)))
		var hl2 := UI.label(g, 19, UI.INK, UI.font_bold)
		hl2.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(hl2)
		row.add_child(head)
		var fl := HFlowContainer.new()
		fl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fl.add_theme_constant_override("h_separation", 5)
		fl.add_theme_constant_override("v_separation", 4)
		row.add_child(fl)
		for it in groups[g]["items"]:
			var idx2: int = it["idx"]
			var b := _rich_btn(it["parts"], it["hl"])
			b.tooltip_text = str(it["tip"]) + ("\n(consiglio dell'IA)" if it["hl"] else "")
			b.pressed.connect(func(): _provide(idx2))
			fl.add_child(b)
		box.add_child(HSeparator.new())
	var f := _flow()
	if has_sail or (sp == "travel" and st.port):
		var at_port: bool = st.players[s]["ship"]["at"] == "P"
		f.add_child(_btn("Salpa: capitano, carico e rotta sulla mappa…" if at_port else "Muovi la nave sulla mappa…", func():
			wiz["step"] = "sail"
			sel = {}
			_show_decision()))
	_back_btn(f)


## Artigiani: si sceglie la bottega, poi si accendono o spengono Addestra / Produci / Compra; il costo si
## ricalcola a ogni clic e Conferma esegue la combinazione scelta.
func _crafts_panel(box: VBoxContainer, src: Dictionary, s: int) -> void:
	var moves: Array = pending["moves"]
	var avail := {}          # bottega -> mosse (indice, azione)
	var border := []
	for i in moves.size():
		var m: Dictionary = moves[i]
		if m["src"] != src or m["a"].get("a", "") != "craft":
			continue
		var b: String = m["a"]["b"]
		if not avail.has(b):
			avail[b] = []
			border.append(b)
		avail[b].append({"i": i, "a": m["a"]})
	if avail.is_empty():
		return
	var hm := _hint_move()
	# stato iniziale: la bottega e le scelte consigliate dall'IA, altrimenti la prima
	if not sel.has("cb") or not avail.has(sel["cb"]):
		var start: String = border[0]
		var ha: Dictionary = hm.get("a", {}) if not hm.is_empty() and hm["src"] == src else {}
		if ha.get("a", "") == "craft":
			start = ha["b"]
		_craft_pick(start, avail, ha if ha.get("b", "") == start else {})
	var b0: String = sel["cb"]
	# 1. le botteghe
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var head := UI.label("Bottega", 19, UI.INK, UI.font_bold)
	head.custom_minimum_size = Vector2(150, 0)
	row.add_child(head)
	var fl := HFlowContainer.new()
	fl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fl.add_theme_constant_override("h_separation", 5)
	row.add_child(fl)
	for b in border:
		var b2: String = b
		var gt: String = "coin" if b == "mill" else str(D.CRAFT[b]["good"])
		var bb := _rich_btn([{"tok": gt}, D.CRAFT[b]["name"]], b == b0)
		bb.pressed.connect(func():
			_craft_pick(b2, avail, {})
			_show_decision())
		fl.add_child(bb)
	box.add_child(HSeparator.new())
	var cr: Dictionary = D.CRAFT[b0]
	var opts: Array = avail[b0]
	var has := func(how: String) -> bool:
		for o in opts:
			if str(o["a"].get("how", "")) == how:
				return true
		return false
	# 2. gli interruttori
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	box.add_child(row2)
	var head2 := UI.label(cr["name"], 19, UI.INK, UI.font_bold)
	head2.custom_minimum_size = Vector2(150, 0)
	row2.add_child(head2)
	var fl2 := HFlowContainer.new()
	fl2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fl2.add_theme_constant_override("h_separation", 5)
	row2.add_child(fl2)
	if b0 == "mill":
		var mil_ok := false
		for o in opts:
			if o["a"].get("miller", false):
				mil_ok = true
		var mb := _rich_btn(["Macina: 2", {"tok": "grain"}, "» %d" % (5 if sel["miller"] else 2), {"tok": "coin"}], true)
		mb.disabled = true
		fl2.add_child(mb)
		if mil_ok:
			var tb := _rich_btn([("[x] " if sel["miller"] else "[ ] ") + "Usa il Mugnaio (5 monete)"], sel["miller"])
			tb.pressed.connect(func():
				sel["miller"] = not sel["miller"]
				_show_decision())
			fl2.add_child(tb)
	else:
		var can_train: bool = has.call("train") or has.call("trainmake")
		var can_make: bool = has.call("make") or has.call("trainmake")
		var here: bool = has.call("make")
		if can_train:
			var t := _rich_btn([("[x] " if sel["train"] else "[ ] ") + "Addestra un familiare", {"time": cr["train"]}], sel["train"])
			t.tooltip_text = "Un familiare dalla fattoria va a lavorare in bottega"
			t.pressed.connect(func():
				sel["train"] = not sel["train"]
				if sel["train"]:
					sel["buy"] = false
				_show_decision())
			fl2.add_child(t)
		if can_make:
			var mk := _rich_btn([("[x] " if sel["make"] else "[ ] ") + "Produci"] + _good_parts(b0, sel["g"]) + [{"time": cr["make"]}], sel["make"])
			mk.tooltip_text = "Produci la merce" + ("" if here else " (serve un familiare in bottega: accendi anche Addestra)")
			mk.pressed.connect(func():
				sel["make"] = not sel["make"]
				if sel["make"]:
					sel["buy"] = false
				_show_decision())
			fl2.add_child(mk)
		if has.call("buy"):
			var cost := []
			if cr.has("grain"):
				cost = ["%d" % int(cr["grain"]), {"tok": "grain"}]
			else:
				for c in cr["buy"]:
					cost.append({"cube": c})
			var bu := _rich_btn([("[x] " if sel["buy"] else "[ ] ") + "Compra invece"] + _good_parts(b0, sel["g"]) + ["con"] + cost, sel["buy"])
			bu.tooltip_text = "Compri la merce senza familiari, pagando cubi (o grano)"
			bu.pressed.connect(func():
				sel["buy"] = not sel["buy"]
				if sel["buy"]:
					sel["train"] = false
					sel["make"] = false
				_show_decision())
			fl2.add_child(bu)
		# Stalle: cavallo o bue
		if b0 == "stable" and (sel["make"] or sel["buy"]):
			for g in ["horse", "ox"]:
				var g2: String = g
				var gb := _rich_btn([{"tok": g}], sel["g"] == g)
				gb.tooltip_text = D.good_name(g)
				gb.pressed.connect(func():
					sel["g"] = g2
					_show_decision())
				fl2.add_child(gb)
		# quale familiare addestrare (solo se ce n'è più di una generazione)
		if sel["train"]:
			var mids := []
			for o in opts:
				if o["a"].has("m") and not (int(o["a"]["m"]) in mids):
					mids.append(int(o["a"]["m"]))
			if mids.size() > 1:
				for mid in mids:
					var mid2: int = mid
					var meb := _rich_btn([{"meeple": int(st.members[mid]["gen"])}], int(sel["m"]) == mid)
					meb.tooltip_text = "Addestra il familiare %d" % st.members[mid]["gen"]
					meb.pressed.connect(func():
						sel["m"] = mid2
						_show_decision())
					fl2.add_child(meb)
	# 3. riepilogo e conferma
	var mv := _craft_match(b0, opts)
	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 8)
	box.add_child(row3)
	var sp3 := Control.new()
	sp3.custom_minimum_size = Vector2(150, 0)
	row3.add_child(sp3)
	if mv.is_empty():
		row3.add_child(UI.label("Questa combinazione non è possibile: accendi Produci o Addestra (o Compra).", 18, UI.RED, UI.font_italic))
	else:
		var a: Dictionary = mv["a"]
		var parts: Array = ["Conferma:"]
		var tm := 0
		match str(a.get("how", "")):
			"trainmake":
				parts.append_array(["addestra", {"meeple": int(st.members[int(a["m"])]["gen"])}, "e produci"] + _good_parts(b0, a.get("g", "")))
				tm = int(cr["train"]) + int(cr["make"])
			"train":
				parts.append_array(["addestra", {"meeple": int(st.members[int(a["m"])]["gen"])}])
				tm = int(cr["train"])
			"make":
				parts.append_array(["produci"] + _good_parts(b0, a.get("g", "")))
				tm = int(cr["make"])
			"buy":
				parts.append_array(["compra"] + _good_parts(b0, a.get("g", "")) + ["con"])
				if cr.has("grain"):
					parts.append_array(["%d" % int(cr["grain"]), {"tok": "grain"}])
				else:
					for c in cr["buy"]:
						parts.append({"cube": c})
		if b0 == "mill":
			parts.append_array(["macina 2", {"tok": "grain"}, "» %d" % (5 if a.get("miller", false) else 2), {"tok": "coin"}])
			tm = 2
		if tm > 0:
			parts.append_array(["=", {"time": tm}])
		var ok := _rich_btn(parts)
		UI.primary(ok)
		ok.tooltip_text = Describe.action(st, s, a)
		var idx: int = mv["i"]
		ok.pressed.connect(func(): _provide(idx))
		row3.add_child(ok)
	box.add_child(HSeparator.new())


func _good_parts(b: String, g: String) -> Array:
	var cr: Dictionary = D.CRAFT[b]
	var good: String = g if g != "" else str(cr.get("good", ""))
	if int(cr.get("qty", 1)) > 1:
		return ["%d" % int(cr["qty"]), {"tok": good}]
	return [{"tok": good}]


## Scelte iniziali per una bottega (dall'eventuale consiglio dell'IA).
func _craft_pick(b: String, avail: Dictionary, ha: Dictionary) -> void:
	var opts: Array = avail[b]
	var hows := {}
	var mid := -1
	for o in opts:
		hows[str(o["a"].get("how", ""))] = true
		if o["a"].has("m") and mid < 0:
			mid = int(o["a"]["m"])
	sel["cb"] = b
	sel["g"] = "horse" if b == "stable" else str(D.CRAFT[b].get("good", ""))
	sel["m"] = mid
	sel["miller"] = false
	sel["buy"] = false
	if hows.has("make"):
		sel["train"] = false
		sel["make"] = true
	elif hows.has("trainmake"):
		sel["train"] = true
		sel["make"] = true
	elif hows.has("train"):
		sel["train"] = true
		sel["make"] = false
	else:
		sel["train"] = false
		sel["make"] = false
		sel["buy"] = hows.has("buy")
	if not ha.is_empty():
		var how := str(ha.get("how", ""))
		sel["train"] = how in ["train", "trainmake"]
		sel["make"] = how in ["make", "trainmake"]
		sel["buy"] = how == "buy"
		if ha.has("g"):
			sel["g"] = ha["g"]
		if ha.has("m"):
			sel["m"] = int(ha["m"])
		sel["miller"] = ha.get("miller", false)


## La mossa che corrisponde agli interruttori accesi.
func _craft_match(b: String, opts: Array) -> Dictionary:
	var want := ""
	if b == "mill":
		for o in opts:
			if bool(o["a"].get("miller", false)) == bool(sel["miller"]):
				return o
		return {}
	if sel["buy"]:
		want = "buy"
	elif sel["train"] and sel["make"]:
		want = "trainmake"
	elif sel["train"]:
		want = "train"
	elif sel["make"]:
		want = "make"
	if want == "":
		return {}
	for o in opts:
		var a: Dictionary = o["a"]
		if str(a.get("how", "")) != want:
			continue
		if want in ["make", "trainmake", "buy"] and a.has("g") and str(a["g"]) != str(sel["g"]):
			continue
		if want in ["train", "trainmake"] and int(a["m"]) != int(sel["m"]):
			continue
		return o
	return {}


## Pulsante composto da testo e icone. parts: stringhe, {"tok": merce}, {"cube": colore},
## {"meeple": generazione}, {"time": n}.
func _rich_btn(parts: Array, hinted := false) -> Button:
	var b := UI.button("", 0, 40, 17)
	if hinted:
		UI.selected(b, "meadow")
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 3)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.position = Vector2(10, 4)
	for p in parts:
		if p is String:
			var l := UI.label(p, 17, UI.LIGHT, UI.font_bold)
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			hb.add_child(l)
		elif p.has("tok"):
			hb.add_child(UI.icon_rect(UI.token(p["tok"]), Vector2(30, 30)))
		elif p.has("cube"):
			var c := UI.cube_icon(p["cube"], 18)
			c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			hb.add_child(c)
		elif p.has("time"):
			var tb := HBoxContainer.new()
			tb.add_theme_constant_override("separation", 1)
			tb.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tb.add_child(UI.icon_rect(UI.token("time"), Vector2(20, 27)))
			var tl := UI.label(str(p["time"]), 18, UI.LIGHT, UI.font_bold)
			tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			tb.add_child(tl)
			tb.tooltip_text = Describe.tempi(int(p["time"]))
			hb.add_child(tb)
		elif p.has("img"):
			hb.add_child(UI.icon_rect(p["img"], p.get("size", Vector2(30, 30))))
		elif p.has("meeple"):
			var mc := Control.new()
			mc.custom_minimum_size = Vector2(28, 30)
			mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var key: String = D.COLORS[st.players[int(p.get("owner", pending.get("seat", 0)))]["color"]]["key"]
			var mi := UI.icon_rect(UI.tex("res://assets/ui/meeple_%s.png" % key), Vector2(28, 30))
			mc.add_child(mi)
			var nl := UI.label(str(p["meeple"]), 15, Color.WHITE, UI.font_bold)
			nl.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.02))
			nl.add_theme_constant_override("outline_size", 4)
			nl.position = Vector2(9, 6)
			mc.add_child(nl)
			hb.add_child(mc)
	b.add_child(hb)
	var fit := func():
		b.custom_minimum_size = hb.get_combined_minimum_size() + Vector2(20, 8)
	hb.minimum_size_changed.connect(fit)
	fit.call()
	return b


## Un'azione come pulsante breve: gruppo (la riga) e parti (testo e icone).
func _chip(s: int, a: Dictionary) -> Dictionary:
	var pl: Dictionary = st.players[s]
	match str(a.get("a", "none")):
		"none":
			return {"group": "Solo il cubo", "parts": ["Prendi solo il cubo, nessuna azione"]}
		"harvest":
			var k := 2
			if int(pl["goods"]["plow"]) > 0 and int(pl["goods"]["ox"]) > 0:
				k = 4
			elif int(pl["goods"]["plow"]) > 0 and int(pl["goods"]["horse"]) > 0:
				k = 3
			k = mini(k, D.GRAIN_MAX - int(pl["grain"]))
			return {"group": "Mietitura", "gicon": UI.token("grain"), "parts": ["Prendi +%d" % k, {"tok": "grain"}]}
		"family":
			if int(a["m"]) < 0:
				var nb := st.next_unborn(s)
				return {"group": "Famiglia", "gicon": _meeple_tex(s), "parts": ["Nasce", {"meeple": int(nb["gen"]) if not nb.is_empty() else 0}]}
			var m: Dictionary = st.members[int(a["m"])]
			return {"group": "Famiglia", "gicon": _meeple_tex(s), "parts": ["Riporta a casa", {"meeple": int(m["gen"])}, "(" + st.loc_name(m["loc"]) + ")"]}
		"craft":
			var b: String = a["b"]
			if b == "mill":
				var mil: bool = a.get("miller", false)
				return {"group": "Mulino", "gicon": UI.token("coin"), "parts": ["2", {"tok": "grain"}, {"time": 2}, "»", "%d" % (5 if mil else 2), {"tok": "coin"}] + (["(Mugnaio)"] if mil else [])}
			var cr: Dictionary = D.CRAFT[b]
			var g: String = a.get("g", cr.get("good", ""))
			var qty: int = int(cr.get("qty", 1))
			var good := [{"tok": g}] if qty == 1 else ["%d" % qty, {"tok": g}]
			var gi: Texture2D = UI.token(cr["good"]) if b != "stable" else UI.token("horse")
			match str(a["how"]):
				"make":
					return {"group": cr["name"], "gicon": gi, "parts": ["Produci"] + good + [{"time": cr["make"]}]}
				"trainmake":
					return {"group": cr["name"], "gicon": gi, "parts": ["Addestra", {"meeple": int(st.members[int(a["m"])]["gen"])}, "e produci"] + good + [{"time": int(cr["train"]) + int(cr["make"])}]}
				"train":
					return {"group": cr["name"], "gicon": gi, "parts": ["Solo addestra", {"meeple": int(st.members[int(a["m"])]["gen"])}, {"time": cr["train"]}]}
				"buy":
					var cost := []
					if cr.has("grain"):
						cost = ["%d" % int(cr["grain"]), {"tok": "grain"}]
					else:
						for c in cr["buy"]:
							cost.append({"cube": c})
					return {"group": cr["name"], "gicon": gi, "parts": ["Compra"] + good + ["con"] + cost}
		"market":
			return {"group": "Mercato", "gicon": UI.tex("res://assets/cards/c_back.jpg"), "parts": ["Apri il giorno di mercato (prima vendita gratis)"]}
		"travel":
			var m2: Dictionary = st.members[int(a["m"])]
			var fk := "G" if m2["loc"] == "farm" else str(m2["loc"]).substr(5)
			var parts := [{"meeple": int(m2["gen"])}, "» %s" % D.CITY[a["to"]]["name"]]
			if a.get("toll", false):
				parts.append("(Gabelliere, gratis)")
			else:
				parts.append({"time": 2})
				parts.append({"tok": "wagon"})
				for c in D.road(fk, a["to"]):
					parts.append({"cube": c})
			if not (a["to"] in pl["cities"]):
				match str(D.CITY[a["to"]]["reward"]):
					"pp3": parts.append("» 3 punti")
					"coin": parts.append_array(["»", {"tok": "coin"}])
					"cubes2": parts.append("» 2 cubi")
			return {"group": "Viaggio", "gicon": UI.token("wagon"), "parts": parts}
		"council":
			match str(a["how"]):
				"priv":
					return {"group": "Consiglio", "gicon": UI.token("scroll"), "parts": ["Solo un privilegio (fino al livello %d)" % st.max_council(s)]}
				"enter", "up":
					var m3: Dictionary = st.members[int(a["m"])]
					var lv := 1 if a["how"] == "enter" else int(str(m3["loc"]).substr(8)) + 1
					var pay: Array = [{"tok": "scroll"}] if a["pay"] == "scroll" else [{"cube": "gr"}, {"cube": "gr"}]
					return {"group": "Consiglio", "gicon": UI.token("scroll"), "parts": [{"meeple": int(m3["gen"])}, "» livello %d con" % lv] + pay + [{"time": D.COUNCIL_TIME[lv - 1]}]}
		"church":
			var m4: Dictionary = st.members[int(a["m"])]
			var pay2: Array = [{"cube": "br"}] if a["pay"] == "brown" else [{"time": 3}]
			return {"group": "Chiesa", "gicon": _meeple_tex(s), "parts": [{"meeple": int(m4["gen"])}, "nel sacchetto nero con"] + pay2}
		"inn":
			var d: int = int(a["rot"])
			var top := "mazzo vuoto"
			if st.decks[d].size() > 0:
				top = D.VILLAGERS[st.decks[d][-1]]["name"]
			var parts2 := []
			if int(a["m"]) >= 0:
				parts2 = ["Manda", {"meeple": int(st.members[int(a["m"])]["gen"])}, {"time": 1}, "poi"]
			parts2.append_array([{"time": 1}, "in fondo al mazzo %d: %s" % [d + 1, top]])
			return {"group": "Locanda", "gicon": UI.token("beer"), "parts": parts2}
		"sail":
			return {"group": "Mare", "gicon": UI.token("cocoa"), "parts": [Describe.sail_text(st, s, a).replace("Mare: ", "").replace("Porto: ", "")]}
	return {"group": "Altro", "parts": [Describe.action(st, s, a)]}


func _meeple_tex(s: int) -> Texture2D:
	return UI.tex("res://assets/ui/meeple_%s.png" % D.COLORS[st.players[s]["color"]]["key"])


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
		board.sea_view()
	var f := _flow()
	# 1. capitano: le carte dei tre mazzi, si clicca quella da ingaggiare
	if sh["at"] == "P" and int(sel["cap"]) == -2:
		act_title.text = _who() + "1 · Ingaggia un capitano (senza capitano la nave non parte). Il primo passo è sempre gratis, gli altri si pagano con i cubi indicati sulla carta."
		var ok_caps: Array = st.hireable(s)
		var shown := {}
		var all_caps := []
		for d in st.captains:
			for c in d:
				var cs: Dictionary = D.CAPTAINS[c]
				var key := "%d/%s" % [cs["cost"], ",".join(cs["pay"])]
				if not shown.has(key):
					shown[key] = true
					all_caps.append(c)
		if 100 in ok_caps:
			all_caps.append(100)
		for c in all_caps:
			var c2: int = c
			var can: bool = c in ok_caps
			var vb := VBoxContainer.new()
			vb.add_theme_constant_override("separation", 2)
			var b := _card_button(UI.captain_tex(c), Vector2(76, 120))
			b.disabled = not can
			b.tooltip_text = _captain_text(c) + ("" if can else "\n(non hai abbastanza monete)")
			b.pressed.connect(func():
				sel["cap"] = c2
				_show_decision())
			vb.add_child(b)
			var spec: Dictionary = D.ADMIRAL if c == 100 else D.CAPTAINS[c]
			var cl := UI.label("Ammiraglio" if c == 100 else "%d %s" % [spec["cost"], "moneta" if int(spec["cost"]) == 1 else "monete"], 15, UI.INK if can else UI.INK2, UI.font_bold)
			cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			vb.add_child(cl)
			f.add_child(vb)
		var f0 := _flow()
		_back_btn(f0)
		return
	# 2. carico (in porto)
	if sh["at"] == "P" and not sel.get("loaded", false):
		act_title.text = _who() + "2 · Carica la nave: fino a 3 pezzi, tutti di tipo diverso (clicca per mettere o togliere), poi «Scegli la rotta»."
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
			b2.icon = UI.tex("res://assets/ui/meeple_%s.png" % D.COLORS[pl["color"]]["key"]) if kind == "member" else UI.token(kind)
			b2.expand_icon = true
			b2.custom_minimum_size = Vector2(0, 52)
			f.add_child(b2)
		if items.is_empty():
			f.add_child(UI.label("Non hai niente da caricare.", 18, UI.INK2, UI.font_italic))
		if st.has_card(s, "helmsman"):
			var hb := _btn(("» " if sel["helm"] else "") + "Timoniere (1 passo gratis in più)", func():
				sel["helm"] = not sel["helm"]
				_show_decision(), sel["helm"])
			f.add_child(hb)
		var f2 := _flow()
		var ok := UI.primary(UI.button("Scegli la rotta", 240, 46, 20))
		ok.pressed.connect(func():
			sel["loaded"] = true
			_show_decision())
		f2.add_child(ok)
		_back_btn(f2)
		return
	# 3. rotta: un clic per ogni passo sulla mappa
	var path: Array = sel["path"]
	var cur: String = path[-1] if not path.is_empty() else str(sh["at"])
	var spec2: Dictionary = (D.ADMIRAL if int(sel["cap"]) == 100 else D.CAPTAINS[int(sel["cap"])]) if int(sel["cap"]) >= 0 else {}
	var helm: bool = sel["helm"] or bool(sh["helm"])
	var cost := st.step_cost(spec2, path.size(), helm)
	var tt := 0
	for nd in path:
		if D.SEA[nd]["kind"] == "time":
			tt += 1
	var cap_cost: int = int(spec2.get("cost", 0)) if sh["at"] == "P" else 0
	var afford: bool = st._missing(s, cost) <= int(pl["coins"]) - cap_cost
	if afford and not path.is_empty():
		# prova la rotta su una copia dello stato (conta anche i cubi dati al pozzo)
		var probe := {"a": "sail", "path": path.duplicate(), "land": false}
		if sh["at"] == "P":
			probe["cap"] = sel["cap"]
			probe["load"] = sel["load"].duplicate()
			probe["helm"] = sel["helm"]
		afford = st.sail_valid(s, {"k": "move", "src": src, "a": probe})
	act_title.text = _who() + ("3 · Muovi la nave: clicca sulla mappa l'acqua vicina dove andare (un clic per passo), poi «Termina il movimento»." if path.is_empty() else "3 · Rotta: continua a cliccare le acque vicine oppure termina il movimento.")
	# riepilogo: carta del capitano, rotta, costi
	var info := HBoxContainer.new()
	info.add_theme_constant_override("separation", 10)
	act_body.add_child(info)
	if int(sel["cap"]) >= 0:
		var ct := UI.icon_rect(UI.captain_tex(int(sel["cap"])), Vector2(58, 92))
		ct.mouse_filter = Control.MOUSE_FILTER_STOP
		ct.tooltip_text = _captain_text(int(sel["cap"]))
		info.add_child(ct)
	var iv := VBoxContainer.new()
	iv.add_theme_constant_override("separation", 0)
	info.add_child(iv)
	var names := ["Porto" if str(sh["at"]) == "P" else _sea_name(str(sh["at"]))]
	for nd in path:
		names.append(_sea_name(nd))
	iv.add_child(UI.wrap("Rotta: " + " » ".join(names), 19, MW - 160, UI.INK, UI.font_bold))
	var per := "ogni passo in più costa " + (Describe.cubes_text(spec2["pay"]) if spec2.has("pay") else "—")
	if spec2.get("steps", 1) == 2:
		per = "ogni %s fa fare fino a 2 passi in più" % Describe.cubes_text(spec2["pay"])
	iv.add_child(UI.wrap("Passi %d (il primo%s gratis; %s)" % [path.size(), " e il secondo, con il Timoniere," if helm else "", per], 17, MW - 160, UI.INK2))
	var costs := "Tempo perso: %d" % tt + (" · cubi da pagare: " + Describe.cubes_text(cost) if not cost.is_empty() else " · nessun cubo da pagare")
	if not afford and not path.is_empty():
		costs += "  —  non puoi pagarlo: togli un passo"
	iv.add_child(UI.wrap(costs, 17, MW - 160, UI.RED if (not afford and not path.is_empty()) else UI.INK2, UI.font_bold if (not afford and not path.is_empty()) else UI.font_body))
	# acque vicine: anelli con lettera sulla mappa e pulsanti con la stessa lettera
	var targets := {}
	var letter := 0
	var mv := _flow()
	for nb in D.sea_neighbors(cur):
		if nb == "P":
			continue
		var nb2: String = nb
		var tag: String = D.SEA[nb].get("name", "")
		if tag == "":
			tag = "Acque del tempo %s" % "ABCDEF"[letter]
			letter += 1
		var short: String = tag.replace("Acque del tempo ", "") if D.SEA[nb]["kind"] == "time" else tag.replace("Isola del ", "").replace("Isola ", "").capitalize()
		targets["sea:" + nb] = [board.sea_pos(nb), 0.5, short]
		target_map["sea:" + nb] = func():
			sel["path"].append(nb2)
			_show_decision()
		target_info["sea:" + nb] = tag + (" (perdi 1 tempo)" if D.SEA[nb]["kind"] == "time" else "")
		mv.add_child(_btn("Vai a: " + tag + (" (−1 tempo)" if D.SEA[nb]["kind"] == "time" else ""), func():
			sel["path"].append(nb2)
			_show_decision()))
	board.set_targets(targets)
	board.set_path(s, path)
	var f3 := _flow()
	var at_island: bool = not path.is_empty() and D.SEA[cur]["kind"] == "island"
	var mk := func(land: bool) -> Dictionary:
		var a := {"a": "sail", "path": sel["path"].duplicate(), "land": land}
		if sh["at"] == "P":
			a["cap"] = sel["cap"]
			a["load"] = sel["load"].duplicate()
			a["helm"] = sel["helm"]
		return {"k": "move", "src": src, "a": a}
	if not path.is_empty():
		if at_island:
			var b3 := UI.primary(UI.button("Termina il movimento e approda a %s" % D.SEA[cur]["name"], 0, 48, 20))
			b3.disabled = not afford
			b3.pressed.connect(func(): _provide(mk.call(true)))
			f3.add_child(b3)
		var b4 := UI.button("Termina il movimento qui" + (" (senza approdare)" if at_island else ""), 0, 48, 20)
		if not at_island:
			UI.primary(b4)
		b4.disabled = not afford
		b4.pressed.connect(func(): _provide(mk.call(false)))
		f3.add_child(b4)
		var undo := _btn("Annulla l'ultimo passo", func():
			sel["path"].pop_back()
			_show_decision())
		f3.add_child(undo)
	if st.has_card(s, "cartographer") and path.is_empty():
		for isl in D.ISLANDS:
			if isl == sh["at"]:
				continue
			var isl2: String = isl
			f3.add_child(_btn("Cartografo: vai a %s" % D.SEA[isl]["name"], func():
				var a2 := {"a": "sail", "carto": isl2, "land": true, "path": []}
				if sh["at"] == "P":
					a2["cap"] = sel["cap"]
					a2["load"] = sel["load"].duplicate()
					a2["helm"] = sel["helm"]
				_provide({"k": "move", "src": src, "a": a2})))
	_back_btn(f3)


## Pulsante che mostra una carta intera (bordo dorato al passaggio, scuro se non disponibile).
func _card_button(t: Texture2D, sz: Vector2) -> Button:
	var b := Button.new()
	b.custom_minimum_size = sz
	b.icon = t
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	for k in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0)
		sb.set_content_margin_all(2)
		sb.set_border_width_all(3 if k == "hover" else 0)
		sb.border_color = UI.GOLD
		b.add_theme_stylebox_override(k, sb)
	b.add_theme_color_override("icon_disabled_color", Color(1, 1, 1, 0.35))
	b.add_theme_color_override("icon_hover_color", Color(1.1, 1.1, 1.1))
	return b


func _sea_name(nd: String) -> String:
	if nd == "P":
		return "Porto"
	return str(D.SEA[nd].get("name", "acque del tempo"))


func _captain_text(c: int) -> String:
	if c == 100:
		return "Ammiraglio: non costa monete; il primo passo è gratis, ogni passo in più costa 1 cubo a scelta."
	var cs: Dictionary = D.CAPTAINS[c]
	var t := "Capitano da %d %s: il primo passo è gratis; " % [cs["cost"], "moneta" if int(cs["cost"]) == 1 else "monete"]
	if int(cs["steps"]) == 2:
		t += "ogni %s ti fa fare fino a 2 passi in più." % Describe.cubes_text(cs["pay"])
	else:
		t += "ogni passo in più costa %s." % Describe.cubes_text(cs["pay"])
	return t


# ------------------------------------------------------------------ altre decisioni

func _after_ui() -> void:
	var f := _flow()
	var r = hint.get("r", null)
	for cid in pending.get("cards", []):
		var c2: int = cid
		var b := _rich_btn([{"img": UI.villager(cid), "size": Vector2(26, 41)}, "Gioca %s" % D.VILLAGERS[cid]["name"]], r is Dictionary and r.get("k", "") == "card" and int(r.get("id", -1)) == cid)
		b.tooltip_text = D.VILLAGERS[cid]["text"]
		b.pressed.connect(func(): _provide({"k": "card", "id": c2}))
		f.add_child(b)
	if pending.get("juggler", false):
		var j := _rich_btn([{"img": UI.villager(st.card_id("juggler")), "size": Vector2(26, 41)}, "Giocoliere: +2 punti e un'altra azione"], r is Dictionary and r.get("k", "") == "juggler")
		j.pressed.connect(func(): _provide({"k": "juggler"}))
		f.add_child(j)
	var e := UI.primary(UI.button("Fine del turno", 220, 48, 20))
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
		var parts: Array = ["%d° livello:" % l]
		match int(l):
			1: parts.append_array([{"tok": "next"}, "primo giocatore al prossimo round"])
			2: parts.append_array(["2 cubi a scelta", {"cube": "pk"}, {"cube": "br"}, {"cube": "gr"}, {"cube": "or"}])
			3: parts.append_array(["1 merce a scelta", {"tok": "horse"}, {"tok": "ox"}, {"tok": "plow"}, {"tok": "wagon"}, {"tok": "scroll"}])
			4: parts.append_array(["paga", {"tok": "coin"}, "» 3 punti"])
		var b := _rich_btn(parts, hint.get("r", -1) == l)
		b.tooltip_text = D.PRIV[l]
		b.pressed.connect(func(): _provide(l2))
		f.add_child(b)
	var no := _rich_btn(["Nessun privilegio"])
	no.pressed.connect(func(): _provide(0))
	f.add_child(no)



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
	act_body.add_child(UI.label("Clicca per scegliere (» = scelto), poi Conferma.", 17, UI.INK2, UI.font_italic))
	var f := _flow()
	for g in opts["sell"]:
		var g2: String = g
		var on: bool = g in sel["sell"]
		var b := _rich_btn([("» " if on else "") + "Vendi", {"tok": g}, "» %d punti" % D.SEA[isl]["sell"][g]], on)
		b.tooltip_text = "Vendi %s per %d punti" % [D.good_name(g), D.SEA[isl]["sell"][g]]
		b.pressed.connect(func():
			if g2 in sel["sell"]:
				sel["sell"].erase(g2)
			else:
				sel["sell"].append(g2)
			_show_decision())
		f.add_child(b)
	if opts["take"]:
		var kind: String = D.SEA[isl]["stack"]
		var b2 := _rich_btn([("» " if sel["take"] else "") + "Carica", {"tok": kind}], sel["take"])
		b2.pressed.connect(func():
			sel["take"] = not sel["take"]
			_show_decision())
		f.add_child(b2)
		if opts["take2"]:
			var b3 := _rich_btn([("» " if sel["take2"] else "") + "Quartiermastro: caricane 2", {"tok": kind}, {"tok": kind}], sel["take2"])
			b3.pressed.connect(func():
				sel["take2"] = not sel["take2"]
				_show_decision())
			f.add_child(b3)
	for mid in opts["mission"]:
		var m2: int = mid
		var on2: bool = int(sel["mission"]) == mid
		var b4 := _rich_btn([("» " if on2 else "") + "Missione con", {"meeple": int(st.members[mid]["gen"])}, "» %d punti" % D.SEA[isl]["mpp"]], on2)
		b4.pressed.connect(func():
			sel["mission"] = -1 if int(sel["mission"]) == m2 else m2
			_show_decision())
		f.add_child(b4)
	var f2 := _flow()
	var ok := UI.primary(UI.button("Conferma", 180, 46, 20))
	ok.pressed.connect(func(): _provide(sel.duplicate(true)))
	f2.add_child(ok)



func _list_ui(labels: Array, allow_none: bool) -> void:
	var col := VBoxContainer.new()
	act_body.add_child(col)
	for i in labels.size():
		var i2 := i
		col.add_child(_btn(labels[i], func(): _provide(i2), hint.get("r", -1) == i))
	if allow_none:
		col.add_child(_btn("Niente", func(): _provide(-1)))


func _family_ui() -> void:
	var f := _flow()
	var seat: int = pending["seat"]
	for i in pending["options"].size():
		var i2: int = i
		var b := _rich_btn(_chip(seat, pending["options"][i])["parts"], hint.get("r", -1) == i)
		b.tooltip_text = Describe.action(st, seat, pending["options"][i])
		b.pressed.connect(func(): _provide(i2))
		f.add_child(b)
	var no := _rich_btn(["Niente"])
	no.pressed.connect(func(): _provide(-1))
	f.add_child(no)


func _herb_ui() -> void:
	var f := _flow()
	for spec in [["stay", ["Lascia il segnatempo", {"tok": "time"}, "dov'è"]], ["before", ["Subito prima del ponte", "(la prossima morte arriva presto)"]], ["after", ["Subito dopo il ponte", "(la prossima morte si allontana)"]]]:
		var k: String = spec[0]
		var b := _rich_btn(spec[1], hint.get("r", "stay") == k)
		b.pressed.connect(func(): _provide(k))
		f.add_child(b)



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
		var parts: Array = [D.CITY[c]["name"], "»"]
		match str(D.CITY[c]["reward"]):
			"pp3": parts.append("3 punti")
			"coin": parts.append({"tok": "coin"})
			"cubes2": parts.append_array(["2 cubi", {"cube": "pk"}, {"cube": "or"}])
		var b := _rich_btn(parts, hint.get("r", "") == c)
		b.pressed.connect(func(): _provide(c2))
		f.add_child(b)
		targets["c:" + c] = Board3D.px(D.CITY[c]["pos"])
		target_map["c:" + c] = func(): _provide(c2)
		target_info["c:" + c] = "%s: %s" % [D.CITY[c]["name"], rw]
	board.set_targets(targets)



func _member_ui(ids: Array, map: Callable) -> void:
	var f := _flow()
	var targets := {}
	for id in ids:
		var id2: int = id
		var m: Dictionary = st.members[id]
		var b := _rich_btn([{"meeple": int(m["gen"]), "owner": int(m["owner"])}, "(" + st.loc_name(m["loc"]) + ")"], hint.get("r", -1) == id)
		b.pressed.connect(func(): _provide(map.call(id2)))
		f.add_child(b)
		if board.member_shown(id):
			targets["m:%d" % id] = board.member_pos(id)
		target_map["m:%d" % id] = func(): _provide(map.call(id2))
		target_info["m:%d" % id] = Describe.member(st, id)
	board.set_targets(targets)



func _yesno_ui() -> void:
	var key: String = pending["key"]
	var cid := st.card_id(key)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	act_body.add_child(row)
	row.add_child(UI.icon_rect(UI.villager(cid), Vector2(76, 120)))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	row.add_child(vb)
	vb.add_child(UI.wrap(D.VILLAGERS[cid]["text"], 19, MW - 160, UI.INK2, UI.font_italic))
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 6)
	vb.add_child(f)
	f.add_child(_btn("Sì, gioca %s" % D.VILLAGERS[cid]["name"], func(): _provide(true), hint.get("r", false) == true))
	f.add_child(_btn("No, la tengo", func(): _provide(false), hint.get("r", true) == false))



func _market_ui() -> void:
	var opts: Array = pending["options"]
	var f := _flow()
	var hr = hint.get("r", -1)
	for i in opts.size():
		var o: Dictionary = opts[i]
		var i2 := i
		var b: Button
		match str(o["k"]):
			"cust":
				var ci: int = (st.front if o["where"] == "f" else st.queue)[int(o["i"])]
				var cu: Dictionary = D.CUSTOMERS[ci]
				var parts: Array = [{"img": UI.customer(ci), "size": Vector2(64, 64)}, "%d punti" % cu["pp"], "chiede"]
				for g in cu["need"]:
					for k in int(cu["need"][g]):
						parts.append({"tok": g})
				if o["where"] == "q":
					parts.append("(in coda)")
				b = _rich_btn(parts, hr == i)
				b.tooltip_text = "Cliente: %s » %d punti" % [Describe.need_text(cu["need"]), cu["pp"]]
			"cocoa":
				b = _rich_btn(["Vendi", {"tok": "cocoa"}, "» %d punti" % D.COCOA_PP], hr == i)
			"tea":
				b = _rich_btn(["Vendi", {"tok": "tea"}, "» %d punti e" % D.TEA_PP, {"tok": "coin"}], hr == i)
			"pass":
				b = _rich_btn(["Passa (oggi non vendi più)"], hr == i)
		if b == null:
			continue
		b.pressed.connect(func(): _provide(i2))
		f.add_child(b)
	if not pending.get("free", false):
		act_body.add_child(UI.label("Ogni vendita dopo la prima costa 1 cubo verde e 1 tempo.", 17, UI.INK2, UI.font_italic))



func _scrap_ui() -> void:
	var f := _flow()
	for i in pending["options"]:
		var i2: int = i
		var ci: int = st.front[i]
		var b := _rich_btn([{"img": UI.customer(ci), "size": Vector2(64, 64)}, "Prendi gratis: %d punti" % D.CUSTOMERS[ci]["pp"]], hint.get("r", -2) == i)
		b.pressed.connect(func(): _provide(i2))
		f.add_child(b)
	var no := _rich_btn(["No, tengo il Rigattiere"])
	no.pressed.connect(func(): _provide(-1))
	f.add_child(no)



func _pick_members_ui(ids: Array, mx: int, ok_text: String) -> void:
	if not sel.has("picks"):
		sel["picks"] = []
		if hint.get("r", null) is Array:
			sel["picks"] = hint["r"].duplicate()
	act_body.add_child(UI.label("Clicca i familiari (» = scelto, al massimo %d), poi conferma." % mx, 17, UI.INK2, UI.font_italic))
	var f := _flow()
	for id in ids:
		var id2: int = id
		var m: Dictionary = st.members[id]
		var on: bool = id in sel["picks"]
		var b := _rich_btn([("» " if on else "") + st.pname(m["owner"]), {"meeple": int(m["gen"]), "owner": int(m["owner"])}], on)
		b.pressed.connect(func():
			if id2 in sel["picks"]:
				sel["picks"].erase(id2)
			elif sel["picks"].size() < mx:
				sel["picks"].append(id2)
			_show_decision())
		f.add_child(b)
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
	var info := HBoxContainer.new()
	info.add_theme_constant_override("separation", 4)
	info.add_child(UI.label("Hai %d" % grain, 19, UI.INK, UI.font_bold))
	info.add_child(UI.icon_rect(UI.token("grain"), Vector2(22, 30)))
	info.add_child(UI.label("· costo scelto %d · per salire di una vetrata: 1, 2 e 4 grano" % tot, 19, UI.RED if tot > grain else UI.INK2, UI.font_italic))
	act_body.add_child(info)
	for id in pending["members"]:
		var id2: int = id
		var m: Dictionary = st.members[id]
		var w0 := int(str(m["loc"]).substr(7))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var head := HBoxContainer.new()
		head.custom_minimum_size = Vector2(150, 0)
		var mc := _rich_btn([{"meeple": int(m["gen"])}, "ora %d punti" % D.WINDOW_PTS[w0]])
		mc.disabled = true
		head.add_child(mc)
		row.add_child(head)
		for w in range(w0 + 1, 4):
			var w2 := w
			var cur: int = int(sel["moves"].get(id, w0))
			var b := _rich_btn(["» %d punti con %d" % [D.WINDOW_PTS[w], VLState.climb_cost(w0, w)], {"tok": "grain"}], cur == w)
			b.pressed.connect(func():
				if int(sel["moves"].get(id2, w0)) == w2:
					sel["moves"].erase(id2)
				else:
					sel["moves"][id2] = w2
				_show_decision())
			row.add_child(b)
		act_body.add_child(row)
	var f := _flow()
	var ok := UI.primary(UI.button("Conferma", 180, 46, 20))
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
		var db := _rich_btn([{"meeple": int(m["gen"])}, "(%s) » %s" % [st.loc_name(m["loc"]), "cronache (Bardo)" if sel["bard"] else dest]], hr is Dictionary and int(hr.get("m", -1)) == id)
		db.pressed.connect(func(): _provide({"m": id2, "bard": sel["bard"]}))
		f.add_child(db)
		if board.member_shown(id):
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
		if ev.keycode == KEY_HOME:
			board.reset_view()


# =================================================================== online

func _build_online_label() -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.plank("meadow", 12))
	p.position = Vector2(LX + LW + 20, 92)
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
