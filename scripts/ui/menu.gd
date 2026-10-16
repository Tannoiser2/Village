extends Control
## Menu principale: il villaggio del tabellone sullo sfondo, le famiglie su una pergamena
## (Umano / IA / Assente), livello e velocità dell'IA, espansioni, gioco online.

const MODES := ["Umano", "IA", "Assente"]
const D = preload("res://scripts/data/vl_data.gd")

var main
var seat_mode := [0, 1, 1, 1, 2]      # 0 umano, 1 IA, 2 assente
var tiles := {}
var level := 1
var speed := 1
var mods := {}
var msg: Label
var mods_lbl: Label

const MOD_LIST := [
	["inn", "Village Inn · la Locanda", "Il Birrificio produce birra, alla Locanda si conoscono gli abitanti del villaggio: 30 carte con un favore unico ciascuna. Nuove cronache e nuovi clienti."],
	["port", "Village Port · il Porto", "Il viaggio diventa per mare: capitani, isole, merci da vendere, cacao, tè, forzieri e chiese missionarie. Sepolture in mare."],
	["goals", "Obiettivi di vita", "Ogni famiglia riceve un obiettivo d'argento (5 punti) e uno d'oro (8 punti) segreti: si incassano appena raggiunti."],
	["nohints", "Niente consigli dell'IA", "Non evidenzia la mossa che l'IA consiglia."],
]

const NICK := ["Famiglia Rossi", "Famiglia Gialli", "Famiglia Azzurri", "Famiglia Bianchi", "Famiglia Grigi"]


func _ready() -> void:
	size = Vector2(1920, 1080)
	if main.menu_state.has("seat_mode"):
		seat_mode = main.menu_state["seat_mode"].duplicate()
		level = main.menu_state["level"]
		speed = main.menu_state["speed"]
		mods = main.menu_state.get("mods", {}).duplicate()
	# il villaggio del tabellone dietro
	var art := TextureRect.new()
	var at := AtlasTexture.new()
	at.atlas = UI.tex("res://assets/board/board_base.jpg")
	at.region = Rect2(560, 600, 1400, 1100)
	art.texture = at
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.position = Vector2(560, 0)
	art.size = Vector2(1360, 1080)
	add_child(art)
	var fade := TextureRect.new()
	var fg := GradientTexture2D.new()
	var g2 := Gradient.new()
	g2.set_color(0, Color(0.14, 0.08, 0.03, 1.0))
	g2.set_color(1, Color(0.14, 0.08, 0.03, 0.0))
	fg.gradient = g2
	fg.fill_from = Vector2(0, 0)
	fg.fill_to = Vector2(1, 0)
	fade.texture = fg
	fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fade.stretch_mode = TextureRect.STRETCH_SCALE
	fade.position = Vector2(560, 0)
	fade.size = Vector2(520, 1080)
	add_child(fade)

	var logo := UI.icon_rect(UI.tex("res://assets/ui/logo.png"), Vector2(620, 164))
	logo.position = Vector2(60, 10)
	add_child(logo)
	var tag := UI.label("Generazioni di una famiglia, tra campi, botteghe, chiesa e cronache", 25, UI.SAND, UI.font_italic)
	tag.position = Vector2(80, 172)
	add_child(tag)

	# pergamena delle famiglie
	var scroll := PanelContainer.new()
	scroll.add_theme_stylebox_override("panel", UI.paper(false, 28))
	scroll.position = Vector2(40, 214)
	scroll.custom_minimum_size = Vector2(840, 0)
	add_child(scroll)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 5)
	scroll.add_child(vb)
	var hh := HBoxContainer.new()
	hh.add_child(UI.title("Le famiglie", 42))
	var sub := UI.label("   da 2 a 5 (il quinto colore viene con la Locanda)", 20, UI.INK2, UI.font_italic)
	sub.size_flags_vertical = Control.SIZE_SHRINK_END
	hh.add_child(sub)
	vb.add_child(hh)
	for c in D.COLORS:
		vb.add_child(_family_row(c))
	vb.add_child(HSeparator.new())
	vb.add_child(_segmented("Astuzia dell'IA", ["Facile", "Normale", "Difficile"], level, func(k): level = k))
	vb.add_child(_segmented("Velocità dell'IA", ["Lenta", "Normale", "Veloce", "Subito"], speed, func(k): speed = k))
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 12)
	var ml := UI.label("Espansioni", 24, UI.INK, UI.font_bold)
	ml.custom_minimum_size = Vector2(190, 0)
	mrow.add_child(ml)
	var mb := UI.button("Scegli…", 150, 46, 21)
	mb.pressed.connect(_mods_panel)
	mrow.add_child(mb)
	mods_lbl = UI.label("", 20, UI.INK2, UI.font_italic)
	mods_lbl.custom_minimum_size = Vector2(440, 0)
	mods_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mrow.add_child(mods_lbl)
	vb.add_child(mrow)
	_mods_text()
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 12)
	var sl := UI.label("Suoni", 24, UI.INK, UI.font_bold)
	sl.custom_minimum_size = Vector2(190, 0)
	srow.add_child(sl)
	srow.add_child(Audio.toggle_button("music", 170, 46))
	srow.add_child(Audio.toggle_button("sfx", 170, 46))
	vb.add_child(srow)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 18)
	btns.position = Vector2(50, 950)
	add_child(btns)
	var b_start := _big_button("Al villaggio!", 380, true)
	b_start.pressed.connect(_on_start)
	btns.add_child(b_start)
	var b_rules := _big_button("Regole", 220)
	b_rules.pressed.connect(func():
		_store()
		main.show_rules())
	btns.add_child(b_rules)
	if not OS.has_feature("web"):
		var b_quit := _big_button("Esci", 170)
		b_quit.pressed.connect(func(): get_tree().quit())
		btns.add_child(b_quit)

	msg = UI.label("", 24, Color("#ffc9a0"), UI.font_bold)
	msg.position = Vector2(56, 1036)
	add_child(msg)

	# gioco online: cartello sul dipinto
	var on_box := PanelContainer.new()
	on_box.add_theme_stylebox_override("panel", UI.paper(true, 24))
	on_box.position = Vector2(1430, 790)
	on_box.custom_minimum_size = Vector2(440, 0)
	add_child(on_box)
	var ovb := VBoxContainer.new()
	ovb.add_theme_constant_override("separation", 8)
	on_box.add_child(ovb)
	ovb.add_child(UI.title("Con gli amici", 34))
	ovb.add_child(UI.wrap("Ognuno dal suo dispositivo: crea una stanza e condividi il codice.", 21, 390, UI.INK2))
	var b_online := UI.meadow(_big_button("Gioca online", 390))
	b_online.pressed.connect(_online_panel)
	ovb.add_child(b_online)
	if not main.lobby.is_empty():
		_online_panel.call_deferred()

	var strip := ColorRect.new()
	strip.color = Color(0.12, 0.07, 0.03, 0.85)
	strip.position = Vector2(560, 1046)
	strip.size = Vector2(1360, 34)
	add_child(strip)
	var credits := UI.label("Adattamento digitale non ufficiale per uso personale · Village di Inka e Markus Brand · illustrazioni di Dennis Lohausen · © eggertspiele, Pegasus Spiele, uplay.it · F11 schermo intero", 16, Color("#f0dfc0"))
	credits.position = Vector2(600, 1052)
	add_child(credits)
	_refresh_tiles()


func _store() -> void:
	main.menu_state = {"seat_mode": seat_mode.duplicate(), "level": level, "speed": speed, "mods": mods.duplicate()}


func _mods_text() -> void:
	var names := []
	for m in MOD_LIST:
		if mods.get(m[0], false) and m[0] != "nohints":
			names.append(m[1].get_slice(" · ", 1) if " · " in m[1] else m[1])
	mods_lbl.text = "Solo il gioco base." if names.is_empty() else "Con: " + ", ".join(names) + "."


func _mods_panel() -> void:
	var layer := Control.new()
	layer.size = Vector2(1920, 1080)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(layer)
	var shade := ColorRect.new()
	shade.color = Color(0.1, 0.05, 0.02, 0.78)
	shade.size = layer.size
	layer.add_child(shade)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UI.paper(false, 34))
	box.position = Vector2(380, 200)
	box.custom_minimum_size = Vector2(1160, 0)
	layer.add_child(box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	box.add_child(vb)
	vb.add_child(UI.title("Espansioni e opzioni", 46))
	vb.add_child(UI.label("Si possono combinare in qualsiasi modo, anche in 5 giocatori.", 22, UI.INK2, UI.font_italic))
	var checks := {}
	for m in MOD_LIST:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var c := CheckBox.new()
		c.text = m[1]
		c.button_pressed = mods.get(m[0], false)
		c.custom_minimum_size = Vector2(400, 0)
		c.add_theme_font_size_override("font_size", 23)
		row.add_child(c)
		row.add_child(UI.wrap(m[2], 20, 680, UI.INK2))
		vb.add_child(row)
		checks[m[0]] = c
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	var all := UI.button("Tutte", 150, 54, 23)
	all.pressed.connect(func():
		for k in ["inn", "port", "goals"]:
			checks[k].button_pressed = true)
	hb.add_child(all)
	var none := UI.button("Solo base", 180, 54, 23)
	none.pressed.connect(func():
		for k in ["inn", "port", "goals"]:
			checks[k].button_pressed = false)
	hb.add_child(none)
	var ok := UI.primary(UI.button("Fatto", 190, 54, 23))
	ok.pressed.connect(func():
		mods = {}
		for k in checks:
			if checks[k].button_pressed:
				mods[k] = true
		_mods_text()
		_store()
		layer.queue_free())
	hb.add_child(ok)
	vb.add_child(hb)


func _family_row(c: Dictionary) -> Control:
	var i: int = c["id"]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var pw := UI.icon_rect(UI.tex("res://assets/ui/meeple_%s.png" % c["key"]), Vector2(54, 54))
	pw.mouse_filter = Control.MOUSE_FILTER_STOP
	pw.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			seat_mode[i] = (seat_mode[i] + 1) % 3
			_refresh_tiles())
	row.add_child(pw)
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", -6)
	nv.custom_minimum_size = Vector2(270, 0)
	var nm := UI.title(c["name"], 30, UI.ink_of(i))
	nv.add_child(nm)
	nv.add_child(UI.label(NICK[i], 19, UI.INK2, UI.font_italic))
	row.add_child(nv)
	var buttons := []
	for k in range(3):
		var b := UI.button(MODES[k], 150, 48, 21)
		b.pressed.connect(func():
			seat_mode[i] = k
			msg.text = ""
			_refresh_tiles())
		row.add_child(b)
		buttons.append(b)
	tiles[i] = {"pawn": pw, "buttons": buttons, "name": nm}
	return row


func _refresh_tiles() -> void:
	for i in range(5):
		var t: Dictionary = tiles[i]
		var m: int = seat_mode[i]
		t["pawn"].modulate = Color.WHITE if m != 2 else Color(1, 1, 1, 0.3)
		t["name"].modulate = Color.WHITE if m != 2 else Color(1, 1, 1, 0.45)
		for k in range(3):
			var b: Button = t["buttons"][k]
			if k == m:
				UI.selected(b, "brick" if k == 0 else ("meadow" if k == 1 else "wood_dark"))
			else:
				UI.plain(b)


func _segmented(label_text: String, items: Array, cur: int, cb: Callable) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	var l := UI.label(label_text, 24, UI.INK, UI.font_bold)
	l.custom_minimum_size = Vector2(190, 0)
	hb.add_child(l)
	var btns := []
	for k in range(items.size()):
		var b := UI.button(items[k], 136, 46, 21)
		hb.add_child(b)
		btns.append(b)
	var paint := func(sel: int):
		for k in range(btns.size()):
			if k == sel:
				UI.selected(btns[k], "meadow")
			else:
				UI.plain(btns[k])
	for k in range(btns.size()):
		btns[k].pressed.connect(func():
			cb.call(k)
			paint.call(k))
	paint.call(cur)
	return hb


func _big_button(text: String, w: float, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 76)
	b.add_theme_font_override("font", UI.font_title)
	b.add_theme_font_size_override("font_size", 36)
	if primary:
		UI.primary(b)
	return b


## Configurazione scelta nel menu (anche quella che, online, viaggia agli altri).
func _config() -> Dictionary:
	var seats := []
	for c in D.COLORS:
		var m: int = seat_mode[c["id"]]
		if m == 2:
			continue
		seats.append({"color": c["id"], "ai": m == 1, "name": c["name"], "level": level})
	var speeds := [1.2, 0.6, 0.2, 0.0]
	var o := {}
	for k in ["inn", "port", "goals"]:
		if mods.get(k, false):
			o[k] = true
	return {"seats": seats, "ai_level": level, "ai_delay": speeds[speed], "opts": o, "hints": not mods.get("nohints", false)}


func _on_start() -> void:
	var cfg := _config()
	if cfg["seats"].size() < 2:
		msg.text = "Village si gioca da 2 a 5: metti in gioco almeno 2 famiglie."
		return
	_store()
	main.start_game(cfg)


# =================================================================== online

var on_panel: Control
var on_name: LineEdit
var on_code: LineEdit
var on_lbl: Label
var on_start: Button


func _online_panel() -> void:
	if is_instance_valid(on_panel):
		on_panel.queue_free()
	on_panel = Control.new()
	on_panel.size = Vector2(1920, 1080)
	on_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(on_panel)
	var shade := ColorRect.new()
	shade.color = Color(0.1, 0.05, 0.02, 0.8)
	shade.size = on_panel.size
	on_panel.add_child(shade)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UI.paper(false, 34))
	box.position = Vector2(560, 130)
	box.custom_minimum_size = Vector2(800, 0)
	on_panel.add_child(box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	box.add_child(vb)
	vb.add_child(UI.title("Gioca online", 50))
	vb.add_child(UI.wrap("Chi crea la stanza sceglie prima nel menu famiglie, espansioni e livello dell'IA: i colori su Umano diventano i posti per gli amici (il primo è il suo). Gli amici entrano con il codice. I posti rimasti liberi li gioca l'IA.", 21, 760, UI.INK2))
	var ses: Dictionary = main.get_net().load_session()
	on_name = _line("Il tuo nome", 20)
	on_name.text = str(ses.get("name", ""))
	vb.add_child(on_name)
	var b_create := Button.new()
	b_create.text = "Crea una stanza"
	UI.meadow(b_create)
	b_create.custom_minimum_size = Vector2(0, 60)
	b_create.add_theme_font_size_override("font_size", 28)
	b_create.pressed.connect(_online_create)
	vb.add_child(b_create)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	on_code = _line("Codice", 4)
	on_code.custom_minimum_size.x = 220
	on_code.text_changed.connect(func(t):
		on_code.text = t.to_upper()
		on_code.caret_column = t.length())
	row.add_child(on_code)
	var b_join := Button.new()
	b_join.text = "Entra"
	UI.meadow(b_join)
	b_join.custom_minimum_size = Vector2(200, 60)
	b_join.add_theme_font_size_override("font_size", 28)
	b_join.pressed.connect(_online_join)
	row.add_child(b_join)
	vb.add_child(row)
	on_lbl = UI.wrap("", 23, 760)
	on_lbl.custom_minimum_size.y = 120
	vb.add_child(on_lbl)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 12)
	on_start = _big_button("Si comincia!", 360, true)
	on_start.pressed.connect(_online_start)
	on_start.visible = main.lobby.get("role", "") == "host"
	row2.add_child(on_start)
	var b_close := _big_button("Indietro", 260)
	b_close.pressed.connect(func():
		on_panel.queue_free())
	row2.add_child(b_close)
	vb.add_child(row2)
	if not main.lobby.is_empty():
		on_code.text = main.lobby["code"]
		on_lbl.text = "Stanza %s…" % main.lobby["code"]
	elif str(ses.get("room", "")) != "":
		on_code.text = str(ses["room"])
		on_lbl.text = "Eri nella stanza %s: premi Entra per rientrare." % ses["room"]


func _line(ph: String, maxlen: int) -> LineEdit:
	var le := LineEdit.new()
	le.placeholder_text = ph
	le.max_length = maxlen
	le.custom_minimum_size = Vector2(0, 60)
	le.add_theme_font_size_override("font_size", 28)
	return le


func _say(t: String) -> void:
	if is_instance_valid(on_lbl):
		on_lbl.text = t


func _seat_list() -> Array:
	return _config()["seats"]


func _seats_text(room: Dictionary) -> String:
	var seats := Net._as_dict(room.get("seats", {}))
	var list := _seat_list()
	var parts := []
	for idx in room.get("open", []):
		var k := str(int(idx))
		var who := str(seats[k].get("name", "?")) if seats.has(k) and seats[k] is Dictionary else "libero"
		var cname: String = list[int(idx)]["name"] if int(idx) < list.size() else "posto %d" % (int(idx) + 1)
		parts.append("%s: %s" % [cname, who])
	return ", ".join(parts)


func _online_create() -> void:
	var nm := on_name.text.strip_edges()
	if nm == "":
		_say("Scrivi il tuo nome.")
		return
	var seats := []
	var list := _seat_list()
	for i in list.size():
		if not list[i]["ai"]:
			seats.append(i)
	if list.size() < 2 or seats.size() < 2:
		_say("Servono almeno 2 famiglie in gioco, di cui almeno due su Umano: il primo è il tuo, gli altri sono i posti per gli amici.")
		return
	_store()
	_say("Creo la stanza…")
	var net: Net = main.get_net()
	var code := await net.create_room(nm, seats)
	if code == "":
		_say("Non riesco a creare la stanza.\n%s" % net.last_error)
		return
	main.lobby = {"role": "host", "code": code, "seat": seats[0]}
	net.remember_room(code, seats[0])
	net._save({"name": nm})
	if is_instance_valid(on_code):
		on_code.text = code
	if is_instance_valid(on_start):
		on_start.visible = true
	_lobby_poll(code)


func _online_join() -> void:
	var code := on_code.text.strip_edges().to_upper()
	var nm := on_name.text.strip_edges()
	if nm == "" or code.length() != 4:
		_say("Scrivi il tuo nome e il codice di 4 lettere.")
		return
	_say("Entro nella stanza %s…" % code)
	var net: Net = main.get_net()
	var seat := await net.join_room(code, nm)
	if seat == -2:
		_say("Stanza %s non trovata, oppure la partita è già iniziata.%s" % [code, ("\n" + net.last_error) if net.last_error != "" else ""])
		return
	if seat == -1:
		_say("Nella stanza %s non ci sono posti liberi." % code)
		return
	var room: Dictionary = net.last_room
	main.lobby = {"role": "host" if room.get("host", "") == net.uid else "guest", "code": code, "seat": seat}
	net.remember_room(code, seat)
	net._save({"name": nm})
	if room.get("status", "") in ["playing", "over"] and room.has("game"):
		_say("Rientro nella partita della stanza %s…" % code)
		_begin(room["game"], true)
		return
	if is_instance_valid(on_start):
		on_start.visible = main.lobby["role"] == "host"
	_lobby_poll(code)


func _lobby_poll(code: String) -> void:
	var net: Net = main.get_net()
	while is_inside_tree() and main.lobby.get("code", "") == code:
		var room := await net.room(code)
		if not is_inside_tree() or main.lobby.get("code", "") != code:
			return
		if room.is_empty():
			_say("La stanza %s non esiste più." % code)
			main.lobby = {}
			return
		if main.lobby["role"] == "host":
			_say("Stanza [ %s ]: dai il codice ai tuoi amici.\nPosti: %s.\nQuando ci siete tutti premi Si comincia!: i posti liberi li gioca l'IA." % [code, _seats_text(room)])
		else:
			if room.get("status", "") == "playing" and room.has("game"):
				_begin(room["game"], false)
				return
			_say("Sei nella stanza [ %s ] (posto %d).\nPosti: %s.\nAspetta che chi l'ha creata avvii la partita." % [code, int(main.lobby["seat"]) + 1, _seats_text(room)])
		await get_tree().create_timer(2.0).timeout


## Chi ha creato la stanza avvia: famiglie, espansioni e seme valgono per tutti.
func _online_start() -> void:
	var code: String = main.lobby["code"]
	var net: Net = main.get_net()
	var room := await net.room(code)
	if room.is_empty():
		_say("La stanza %s non esiste più." % code)
		main.lobby = {}
		return
	var seats_db := Net._as_dict(room.get("seats", {}))
	var cfg := _config()
	var my_seat := int(main.lobby["seat"])
	if my_seat >= cfg["seats"].size() or not seats_db.has(str(my_seat)) or cfg["seats"][my_seat]["ai"]:
		_say("Hai cambiato le famiglie dopo aver creato la stanza: creane una nuova.")
		return
	for i in cfg["seats"].size():
		var k := str(i)
		if seats_db.has(k) and seats_db[k] is Dictionary and not cfg["seats"][i]["ai"]:
			cfg["seats"][i]["name"] = "%s" % str(seats_db[k].get("name", cfg["seats"][i]["name"]))
		else:
			cfg["seats"][i]["ai"] = true
	cfg["seed"] = 1 + randi() % 2000000000
	var g := {"cfg": var_to_str(cfg)}
	if not await net.start_room(code, g):
		_say("Non riesco ad avviare la partita (%s)." % net.last_error)
		return
	_begin(g, false)


## Avvio (o rientro) della partita online.
func _begin(g: Dictionary, rejoin: bool) -> void:
	var net: Net = main.get_net()
	var lob: Dictionary = main.lobby
	var backlog: Array = []
	if rejoin:
		backlog = await net.get_acts(lob["code"])
		net.set_away(lob["code"], int(lob["seat"]), false)
	var cfg = str_to_var(str(g.get("cfg", "")))
	if not (cfg is Dictionary):
		_say("Configurazione della partita non valida.")
		return
	var ses := OnlineSession.new()
	ses.setup(net, lob["code"], int(lob["seat"]), lob["role"], backlog)
	cfg["online"] = ses
	main.lobby = {}
	main.start_game(cfg)
