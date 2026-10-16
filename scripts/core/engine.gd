class_name VLEngine
extends Node
## Motore della partita: round, turni, giorni di mercato, messe, morti e fine partita.
## Le regole immediate stanno in VLState (st); qui si chiedono le decisioni, una alla volta:
## l'IA risponde subito, per le persone si emette `decision_requested` e si aspetta `provide_decision()`.
## Online ogni decisione passa dal registro di mosse (OnlineSession): con lo stesso seme ogni
## dispositivo ottiene la stessa partita.

signal changed
signal log_added(text: String)
signal decision_requested(req: Dictionary)
signal decision_provided(result)
signal game_ended(results: Array)
signal fx(kind: String, data: Dictionary)
signal pause_requested(req: Dictionary)

const D = preload("res://scripts/data/vl_data.gd")

var st := VLState.new()
var ai_delay := 0.0
var headless := false
var ais := {}
var log_lines: Array = []
var current := -1
var phase := ""                  # turn, market, mass, final, end
var abort := false
var pause_enabled := false
var online = null
var setup_done := false
var results: Array = []
var game_over := false
var final_queue: Array = []
var market_info := {}            # per la UI durante il giorno di mercato
var mass_info := {}              # per la UI durante la messa
var last_drawn: Array = []

var players: Array:
	get:
		return st.players
var n: int:
	get:
		return st.n


func setup(config: Dictionary) -> void:
	st.setup(config)
	ai_delay = float(config.get("ai_delay", 0.0))
	for s in st.n:
		var a := VLAI.new()
		a.level = st.players[s]["level"]
		a.rng.seed = st.rng.seed + 7919 * (s + 1)
		ais[s] = a
	setup_done = true


func pname(s: int) -> String:
	return st.pname(s)


func any_local_human() -> bool:
	if online != null:
		return true
	for p in st.players:
		if not p["ai"]:
			return true
	return false


## Riporta nella cronaca quello che lo stato ha registrato, controlla gli obiettivi di vita e avvisa la UI.
func _sync() -> void:
	st.check_goals()
	for t in st.log:
		log_lines.append(t)
		log_added.emit(t)
	st.log.clear()
	changed.emit()


func log_msg(t: String) -> void:
	st.say(t)
	_sync()


# ------------------------------------------------------------------ decisioni

func decide(seat: int, req: Dictionary):
	req["seat"] = seat
	current = seat
	if abort:
		return ais[seat].decide(self, seat, req)
	if online != null:
		var r0 = await online.decide(self, seat, req)
		return r0
	if st.players[seat]["ai"]:
		if ai_delay > 0.0 and not headless and is_inside_tree():
			await get_tree().create_timer(ai_delay).timeout
		return ais[seat].decide(self, seat, req)
	decision_requested.emit(req)
	var r = await decision_provided
	return r


func provide_decision(r) -> void:
	decision_provided.emit(r)


func _wait(sec: float) -> void:
	if headless or abort or not is_inside_tree():
		return
	if online != null and online.catchup:
		return
	if ai_delay <= 0.0 and not any_local_human():
		return
	await get_tree().create_timer(sec).timeout


## Pausa per far leggere qualcosa (fine della messa): solo se c'è qualcuno davanti allo schermo.
func pause_point(req: Dictionary) -> void:
	if headless or abort or not pause_enabled:
		return
	if online != null and online.catchup:
		return
	if not any_local_human():
		return
	pause_requested.emit(req)
	await decision_provided


# ------------------------------------------------------------------ partita

func run() -> void:
	var parts := ["gioco base"]
	if st.inn:
		parts.append("Locanda")
	if st.port:
		parts.append("Porto")
	if st.goals_on:
		parts.append("Obiettivi di vita")
	log_msg("Benvenuti al villaggio! %d famiglie · %s." % [st.n, ", ".join(parts)])
	log_msg("Comincia %s." % pname(st.first))
	while not abort:
		st.start_round()
		phase = "turn"
		log_msg("— Round %d · primo giocatore: %s —" % [st.round_no, pname(st.first)])
		fx.emit("round", {})
		await _round()
		if abort:
			return
		if st.end_by >= 0:
			break
		await _mass(false)
		if abort:
			return
	await _final_phase()
	if abort:
		return
	await _mass(true)
	if abort:
		return
	_final()


func _round() -> void:
	var cur := st.first
	while not abort:
		await _turn(cur, false)
		if abort:
			return
		if st.end_by >= 0:
			final_queue = []
			if st.end_by == cur:
				for k in range(1, st.n):
					final_queue.append((cur + k) % st.n)
			else:
				for k in range(1, st.n + 1):
					final_queue.append((cur + k) % st.n)
			return
		if st.cubes_left() == 0:
			log_msg("Gli spazi azione sono vuoti: fine del round.")
			return
		cur = st.next_seat(cur)


func _final_phase() -> void:
	phase = "final"
	log_msg("— Ultime azioni: %s —" % ", ".join(final_queue.map(func(s): return pname(s))))
	await pause_point({"type": "end_triggered", "by": st.end_by})
	for q in final_queue:
		if abort:
			return
		await _turn(q, true)


# ------------------------------------------------------------------ turno

func turn_moves(p: int, final: bool) -> Array:
	var moves := st.turn_moves(p, final)
	if st.has_card(p, "oldman") and (st.cubes_left() > 0 or not final):
		for a in st.all_actions(p):
			moves.append({"k": "move", "src": {"t": "oldman"}, "a": a})
	return moves


func _turn(p: int, final: bool) -> void:
	current = p
	phase = "final" if final else "turn"
	changed.emit()
	var mv = null
	while not abort:
		var moves := turn_moves(p, final)
		var cards := st.playable_cards(p)
		if moves.is_empty() and cards.is_empty():
			log_msg("%s non può fare nulla e passa." % pname(p))
			break
		var r = await decide(p, {"type": "turn", "moves": moves, "cards": cards, "final": final,
			"title": "Ultima azione: scegli" if final else "Il tuo turno: prendi un cubo da uno spazio azione"})
		if abort:
			return
		if r is Dictionary and r.get("k", "") == "card" and int(r.get("id", -1)) in cards:
			await _card(p, int(r["id"]))
			continue
		mv = _valid_move(r, moves)
		break
	if mv != null:
		await _do_move(p, mv)
	var juggled := false
	while not abort:
		var cards2 := st.playable_cards(p)
		var jug: bool = st.has_card(p, "juggler") and not juggled
		if cards2.is_empty() and not jug:
			break
		var r2 = await decide(p, {"type": "after", "cards": cards2, "juggler": jug, "title": "Fine del turno: vuoi giocare una carta?"})
		if not (r2 is Dictionary):
			break
		match str(r2.get("k", "end")):
			"card":
				if int(r2.get("id", -1)) in cards2:
					await _card(p, int(r2["id"]))
					continue
				break
			"juggler":
				if not jug:
					break
				juggled = true
				st.discard_card(p, "juggler")
				st.gain_pp(p, 2)
				st.say("%s gioca il Giocoliere: 2 punti e un'altra azione." % pname(p))
				_sync()
				await _deaths(p)
				var moves2 := turn_moves(p, final)
				if moves2.is_empty():
					continue
				var r3 = await decide(p, {"type": "turn", "moves": moves2, "cards": [], "final": final, "title": "Giocoliere: scegli l'azione in più"})
				var mv2 = _valid_move(r3, moves2)
				if mv2 != null:
					await _do_move(p, mv2)
			_:
				break
	await _deaths(p)


## Accetta la mossa solo se è fra quelle possibili (online arriva dal database).
func _valid_move(r, moves: Array):
	if r is int and r >= 0 and r < moves.size():
		return moves[r]
	if r is Dictionary:
		for m in moves:
			if _same_move(m, r):
				return m
		# mosse per mare costruite a mano: si controllano a parte
		if r.get("k", "") == "move" and r.get("a", {}).get("a", "") == "sail":
			for m in moves:
				if m["src"] == r.get("src", {}) and m["a"].get("a", "") == "sail":
					return r
	return moves[0] if not moves.is_empty() else null


static func _same_move(a: Dictionary, b: Dictionary) -> bool:
	return var_to_str(a.get("src", {})) == var_to_str(b.get("src", {})) and var_to_str(a.get("a", {})) == var_to_str(b.get("a", {}))


func _do_move(p: int, mv: Dictionary) -> void:
	var res := st.apply_move(p, mv)
	_sync()
	var a: String = str(mv["a"].get("a", "none"))
	fx.emit("move", {"seat": p, "a": a, "src": mv["src"]})
	await _resolve(p, res)


## Le scelte che un'azione lascia aperte (privilegi, premi, carte, isole…).
func _resolve(p: int, res: Dictionary) -> void:
	if abort or res.is_empty():
		return
	if res.has("market"):
		await _market(p)
	if res.has("priv"):
		await _priv(p, int(res["priv"]))
	if res.has("priv2"):
		for k in 2:
			await _priv(p, int(res["priv2"]), k == 0)
	if res.has("cubes2"):
		var r = await decide(p, {"type": "cubes2", "k": int(res["cubes2"]), "supply": st.supply.duplicate(), "title": "Scegli %d cubi influenza" % int(res["cubes2"])})
		var list := []
		if r is Array:
			for c in r:
				if str(c) in D.CUBES and list.size() < int(res["cubes2"]):
					list.append(str(c))
		st.apply_cubes(p, list)
		_sync()
	if res.has("good"):
		var opts: Array = res["good"] if res["good"] is Array else st.good_choices()
		var g = await decide(p, {"type": "good", "options": opts, "title": "Scegli una merce"})
		if not (str(g) in opts):
			g = opts[0]
		st.apply_good(p, str(g))
		_sync()
	if res.has("inn_buy"):
		var opts2 := st.inn_buy_options(p)
		if not opts2.is_empty():
			var d = await decide(p, {"type": "inn_buy", "options": opts2, "title": "Locanda: quale abitante vuoi accogliere?"})
			if d is int and d in opts2:
				st.buy_card(p, d)
				_sync()
				fx.emit("card", {"seat": p})
		else:
			log_msg("%s non può permettersi nessuno degli abitanti in cima ai mazzi." % pname(p))
	if res.has("island"):
		var isl: String = res["island"]
		var io := st.island_options(p, isl)
		if not io["sell"].is_empty() or io["take"] or not io["mission"].is_empty():
			var r2 = await decide(p, {"type": "island", "isl": isl, "opts": io, "title": "%s: cosa fai sull'isola?" % D.SEA[isl]["name"]})
			if r2 is Dictionary:
				st.apply_island(p, isl, r2)
				_sync()
	if res.has("family"):
		var fo := st.action_options(p, "family")
		if not fo.is_empty():
			var r3 = await decide(p, {"type": "family", "options": fo, "title": "Figliol prodigo: azione Famiglia in più"})
			if r3 is int and r3 >= 0 and r3 < fo.size():
				st.apply_action(p, fo[r3])
				_sync()
	if res.has("herb"):
		var w = await decide(p, {"type": "herb", "title": "Erborista: vuoi spostare il segnatempo?"})
		st.herb_move(p, str(w))
		_sync()
	if res.has("noble"):
		var r4 = await decide(p, {"type": "noble", "decks": st.decks.duplicate(true), "title": "Nobildonna: scegli un abitante da un mazzo"})
		if r4 is Dictionary:
			st.noble_take(p, int(r4.get("d", -1)), int(r4.get("c", -1)))
			_sync()
	if res.has("city"):
		var cs := st.messenger_cities(p)
		if not cs.is_empty():
			var c = await decide(p, {"type": "city", "options": cs, "title": "Messaggero: su quale città metti un segnalino?"})
			if not (str(c) in cs):
				c = cs[0]
			var r5 := st.visit_city(p, str(c))
			_sync()
			await _resolve(p, r5)
	if res.has("abbot"):
		var cm := st.church_members(p)
		if not cm.is_empty():
			var ids := cm.map(func(m): return m["id"])
			var mid = await decide(p, {"type": "abbot", "options": ids, "title": "Abate: quale familiare porti alla vetrata più a sinistra?"})
			if not (mid in ids):
				mid = ids[0]
			st.abbot_move(p, int(mid))
			_sync()


func _priv(p: int, lv: int, may_skip := true) -> void:
	var opts := st.priv_options(p, lv)
	if opts.is_empty():
		return
	var l = await decide(p, {"type": "priv", "options": opts, "lv": lv, "title": "Camera di Consiglio: scegli il privilegio"})
	if not (l in opts):
		return
	var r := st.apply_priv(p, int(l))
	_sync()
	await _resolve(p, r)


func _card(p: int, cid: int) -> void:
	var r := st.play_card(p, cid)
	_sync()
	fx.emit("card", {"seat": p})
	await _resolve(p, r)


# ------------------------------------------------------------------ morte

func _deaths(p: int) -> void:
	while not abort and int(st.players[p]["deaths"]) > 0:
		var opts := st.death_options(p)
		if opts.is_empty():
			st.players[p]["deaths"] = 0
			break
		var bard := st.has_card(p, "bard")
		var r = {"m": opts[0], "bard": false}
		if opts.size() > 1 or bard:
			r = await decide(p, {"type": "death", "options": opts, "bard": bard, "title": "Il tempo è passato: quale familiare ci lascia?"})
		var mid: int = int(r.get("m", opts[0])) if r is Dictionary else opts[0]
		if not (mid in opts):
			mid = opts[0]
		var trig := st.apply_death(p, mid, r is Dictionary and bool(r.get("bard", false)) and bard)
		fx.emit("death", {"seat": p})
		if trig and st.end_by < 0 and phase != "final":
			st.end_by = p
			st.say("%s ha occupato l'ultimo posto: la fine della partita è vicina!" % pname(p))
		_sync()


# ------------------------------------------------------------------ mercato

func _market(opener: int) -> void:
	var prev_phase := phase
	phase = "market"
	log_msg("%s apre un giorno di mercato." % pname(opener))
	fx.emit("market", {})
	var order := []
	for k in st.n:
		order.append((opener + k) % st.n)
	var barker := {}
	for q in order:
		if st.has_card(q, "barker"):
			var u = await decide(q, {"type": "use_card", "key": "barker", "title": "Vuoi giocare l'Imbonitore? Potrai servire anche i clienti in coda."})
			if u == true:
				st.discard_card(q, "barker")
				barker[q] = true
				log_msg("%s gioca l'Imbonitore." % pname(q))
	var passed := {}
	var free_left := true
	var served := false
	var idx := 0
	market_info = {"opener": opener, "passed": passed}
	while passed.size() < st.n and not abort:
		var q: int = order[idx % st.n]
		idx += 1
		if passed.has(q):
			continue
		var free: bool = q == opener and free_left
		var opts := st.market_options(q, free, barker.has(q))
		if opts.size() == 1:
			passed[q] = true
			continue
		var r = await decide(q, {"type": "market", "options": opts, "free": free,
			"title": "Giorno di mercato: servi un cliente" + (" (la prima vendita è gratis)" if free else " (costa 1 cubo verde e 1 tempo)")})
		var i: int = int(r) if (r is int or r is float) else opts.size() - 1
		i = clampi(i, 0, opts.size() - 1)
		var sale: Dictionary = opts[i]
		if sale["k"] == "pass":
			passed[q] = true
			log_msg("%s passa." % pname(q))
			continue
		st.apply_sale(q, sale, free)
		if sale["k"] == "cust":
			served = true
		if q == opener:
			free_left = false
		_sync()
		fx.emit("sale", {"seat": q})
		await _deaths(q)
	for q in order:
		if barker.has(q):
			continue
		if st.has_card(q, "scrap") and not st.scrap_options().is_empty():
			var so := st.scrap_options()
			var c = await decide(q, {"type": "scrap", "options": so, "title": "Rigattiere: vuoi prendere gratis un cliente rimasto?"})
			if c is int and c in so:
				st.take_customer_free(q, c)
				served = true
				_sync()
	if served:
		st.refill_market()
		log_msg("Il mercato chiude: i clienti in coda avanzano.")
	else:
		log_msg("Il mercato chiude senza vendite.")
	market_info = {}
	phase = prev_phase
	changed.emit()


# ------------------------------------------------------------------ messa

func _mass(final: bool) -> void:
	phase = "mass"
	log_msg("— %s —" % ("Messa finale" if final else "Messa di fine round"))
	fx.emit("mass", {})
	var order := []
	for k in st.n:
		order.append((st.first + k) % st.n)
	mass_info = {"step": 1}
	changed.emit()
	var drawn := []
	var priest := -1
	for q in order:
		if st.has_card(q, "priest") and not st.bag_members().is_empty():
			var u = await decide(q, {"type": "use_card", "key": "priest", "title": "Vuoi giocare il Prete? Sceglierai tu i 4 personaggi estratti."})
			if u == true:
				st.discard_card(q, "priest")
				priest = q
				log_msg("%s gioca il Prete e sceglie chi esce dal sacchetto." % pname(q))
				break
	if priest >= 0:
		var pieces := []
		for m in st.bag_members():
			pieces.append(m["id"])
		var r = await decide(priest, {"type": "priest", "pieces": pieces, "title": "Prete: scegli fino a 4 familiari da estrarre (gli altri posti vanno ai frati)"})
		if r is Array:
			for id in r:
				if int(id) in pieces and not (int(id) in drawn) and drawn.size() < 4:
					drawn.append(int(id))
		for id in drawn:
			st.put_in_church(st.members[id])
	else:
		var bought := 0
		for q in order:
			if bought >= 4:
				break
			var own := []
			for m in st.bag_members():
				if m["owner"] == q:
					own.append(m["id"])
			var coins: int = st.players[q]["coins"]
			if own.is_empty() or coins <= 0:
				continue
			var mx := mini(4 - bought, mini(coins, own.size()))
			var r2 = await decide(q, {"type": "mass_buy", "options": own, "max": mx, "title": "Messa: vuoi comprare i tuoi familiari dal sacchetto nero (1 moneta ciascuno)?"})
			var picks := []
			if r2 is Array:
				for id in r2:
					if int(id) in own and not (int(id) in picks) and picks.size() < mx:
						picks.append(int(id))
			if not picks.is_empty():
				st.players[q]["coins"] -= picks.size()
				for id in picks:
					st.put_in_church(st.members[id])
				bought += picks.size()
				log_msg("%s paga %d %s e porta in chiesa %d %s." % [pname(q), picks.size(), "moneta" if picks.size() == 1 else "monete", picks.size(), "familiare" if picks.size() == 1 else "familiari"])
				drawn.append_array(picks)
		var rnd := st.draw_mass(4 - bought)
		var fam := 0
		for id in rnd:
			if int(id) >= 0:
				st.put_in_church(st.members[int(id)])
				drawn.append(int(id))
				fam += 1
		if rnd.size() > 0:
			log_msg("Dal sacchetto nero escono %d frati e %d familiari." % [rnd.size() - fam, fam])
	last_drawn = drawn
	for id in drawn:
		var m: Dictionary = st.members[id]
		st.say("%s: il familiare %d entra in chiesa." % [pname(m["owner"]), m["gen"]])
	_sync()
	mass_info = {"step": 2}
	for q in order:
		if abort:
			return
		var cm := st.church_members(q)
		if cm.is_empty() or int(st.players[q]["grain"]) <= 0:
			continue
		var can := false
		for m in cm:
			var w := int(str(m["loc"]).substr(7))
			if w < 3 and D.WINDOW_COST[w] <= int(st.players[q]["grain"]):
				can = true
		if not can:
			continue
		var ids := cm.map(func(m): return m["id"])
		var r3 = await decide(q, {"type": "mass_up", "members": ids, "title": "Messa: paga grano per far salire i tuoi familiari verso l'altare"})
		if r3 is Dictionary and not r3.is_empty():
			if not st.apply_climb(q, r3):
				log_msg("%s: salita non valida, nessun movimento." % pname(q))
		_sync()
	var win := st.church_majority()
	if win.size() > 0:
		log_msg("Maggioranza in chiesa: %s %s 2 punti." % [" e ".join(win.map(func(s): return pname(s))), "prende" if win.size() == 1 else "prendono"])
	mass_info = {}
	_sync()
	await pause_point({"type": "mass_end", "final": final, "drawn": drawn, "win": win})


# ------------------------------------------------------------------ fine

func _final() -> void:
	phase = "end"
	game_over = true
	st.game_over = true
	results = st.final_results()
	var parts := []
	for r in results:
		parts.append("%s %d" % [pname(r["seat"]), r["total"]])
	log_msg("Fine della partita! Punti: " + ", ".join(parts) + ".")
	log_msg("La famiglia %s sarà ricordata per sempre nelle cronache del villaggio!" % pname(results[0]["seat"]))
	game_ended.emit(results)


func fingerprint() -> String:
	return st.fingerprint()
