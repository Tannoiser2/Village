class_name VLAI
extends RefCounted
## Intelligenza artificiale di Village. Prova ogni mossa su una copia dello stato (VLState.clone),
## risolve in modo "goloso" le scelte che restano (privilegi, premi, prima vendita al mercato…) e
## valuta la posizione con una stima dei punti finali più il valore delle risorse, che cala man mano
## che le cronache e le tombe si riempiono. Livelli: 0 facile, 1 normale, 2 difficile.

const D = preload("res://scripts/data/vl_data.gd")

var level := 1
var rng := RandomNumberGenerator.new()

## Pesi della valutazione (tarati con partite IA contro IA: tests/sim.gd).
var W := {
	"grain": 0.55, "horse": 1.55, "ox": 1.7, "plow": 1.55, "wagon": 1.6, "scroll": 1.55, "beer": 1.0,
	"cocoa": 6.2, "tea": 5.4, "cube": 0.42, "green": 0.12, "coin": 1.0,
	"farm_m": 1.1, "farm_extra": 0.35, "pool_m": 0.55, "craft_m": 1.4, "bag_m": 2.4, "inn_m": 0.8,
	"time": 0.08, "next": 1.1, "harvest_syn": 1.4, "city_m": 1.4, "council_m": 0.6, "ship_item": 0.9,
	"death_free": 2.2, "late": 0.6, "rival": 0.3,
}


# ================================================================== valutazione

## Avanzamento della partita: 0 all'inizio, 1 quando cronache e tombe sono piene.
static func progress(st: VLState) -> float:
	var tot := 0
	var used := 0
	for sec in st.chron:
		for v in st.chron[sec]:
			if int(v) != -2:
				tot += 1
				if int(v) >= 0:
					used += 1
	for v in st.graves:
		if int(v) != -2:
			tot += 1
			if int(v) >= 0:
				used += 1
	return clampf(float(used) / maxf(1.0, float(tot) * 0.62), 0.0, 1.0)


func value(st: VLState, p: int) -> float:
	var pl: Dictionary = st.players[p]
	var f := progress(st)
	var g: float = 1.0 - W["late"] * f        # le risorse valgono meno verso la fine
	var b := st.score_breakdown(p)
	var v := float(b["total"]) - float(b["coins"])  # le monete si contano qui sotto
	# cronache: anche i primi familiari ricordati valgono (preparano i 4-7-12 punti)
	var cc := st.chron_count(p)
	if not st.has_card(p, "artist"):
		v += [0.0, 1.6, 3.2, 0.6, 0.4, 0.0, 0.0][mini(6, cc)] * (1.0 - 0.7 * f)
	# fine partita già decisa: conta il distacco dagli altri
	if st.end_by >= 0:
		var best_o := -999
		for o in st.n:
			if o != p:
				best_o = maxi(best_o, int(st.score_breakdown(o)["total"]))
		v += 0.35 * float(int(b["total"]) - best_o)
	v += float(pl["coins"]) * W["coin"]
	# risorse
	v += float(pl["grain"]) * W["grain"] * g
	for k in ["horse", "ox", "plow", "wagon", "scroll", "beer"]:
		var c := int(pl["goods"][k])
		if c > 0:
			v += (W[k] + W[k] * 0.55 * (c - 1)) * g
	v += float(pl["goods"]["cocoa"]) * W["cocoa"] * (1.0 - 0.3 * f)
	v += float(pl["goods"]["tea"]) * W["tea"] * (1.0 - 0.3 * f)
	if int(pl["goods"]["plow"]) > 0 and (int(pl["goods"]["ox"]) > 0 or int(pl["goods"]["horse"]) > 0):
		v += W["harvest_syn"] * g
	var cubes := 0
	for c in D.CUBES:
		cubes += int(pl["cubes"][c])
	v += float(cubes) * W["cube"] * g + float(pl["cubes"]["gr"]) * W["green"] * g
	# clienti serviti ora possibili: un piccolo premio per avere le merci giuste
	var best_c := 0.0
	for i in st.front_n:
		var ci: int = st.front[i]
		if ci >= 0 and st.can_serve(p, ci):
			best_c = maxf(best_c, float(D.CUSTOMERS[ci]["pp"]))
	v += best_c * 0.25 * g
	# familiari
	var fm := 0
	var pool := 0
	var crafts := {}
	for m in st.members:
		if m["owner"] != p:
			continue
		var l: String = m["loc"]
		if l == "farm":
			fm += 1
		elif l == "pool":
			pool += 1
		elif l.begins_with("craft:"):
			crafts[l] = true
		elif l == "bag":
			v += W["bag_m"] * (1.0 - 0.45 * f)
		elif l == "inn":
			# alla Locanda chi muore finisce in una tomba anonima: meglio un familiare giovane
			v += W["inn_m"] * g - (1.2 if int(m["gen"]) == 1 else 0.0)
		elif l.begins_with("city:"):
			v += W["city_m"] * g
		elif l.begins_with("council:"):
			v += W["council_m"] * g * float(4 - int(l.substr(8)))
		elif l == "ship":
			v += W["ship_item"] * g
	v += float(mini(fm, 3)) * W["farm_m"] * g + float(maxi(0, fm - 3)) * W["farm_extra"] * g
	if fm == 0:
		v -= 2.0 * g
	v += float(pool) * W["pool_m"] * g
	v += float(crafts.size()) * W["craft_m"] * g
	# carico della nave
	v += float(pl["ship"]["hold"].size()) * W["ship_item"] * g * 0.6
	if int(pl["ship"]["cap"]) >= 0:
		v += 0.8 * g
	# carte in mano non ancora giocate (quelle da fine partita sono già nel punteggio)
	for cid in pl["hand"]:
		v += card_hold_value(st, p, cid) * g
	if st.next_owner == p:
		v += W["next"]
	# obiettivi ancora da fare: un po' di valore se sono vicini (qui solo un piccolo incentivo)
	for gl in pl["goals"]:
		v += 0.6 * g
	# tempo: avvicinarsi al ponte
	var morti := int(pl["deaths"])
	v -= float(morti) * 0.5
	return v


## Valore di una carta tenuta in mano (per le carte "quando vuoi" e situazionali).
func card_hold_value(st: VLState, p: int, cid: int) -> float:
	match str(D.VILLAGERS[cid]["key"]):
		"scribe": return 3.0
		"wagonmaker": return 1.6
		"blacksmith": return 3.0
		"cattle": return 1.7
		"lostson": return 4.2
		"herb": return 2.4
		"farmhand": return 3.6
		"councilman": return 3.0
		"noble": return 4.0
		"messenger": return 3.0
		"abbot": return 3.0
		"oldman": return 5.0
		"juggler": return 4.0
		"toll": return 2.5
		"miller": return 2.5
		"barker": return 1.5
		"priest": return 1.5
		"scrap": return 3.0
		"bard": return 3.0
		"quartermaster": return 1.5
		"admiral": return 2.5
		"cartographer": return 2.5
		"helmsman": return 1.5
	return 0.0


# ================================================================== decisioni

func decide(eng, s: int, req: Dictionary):
	var st: VLState = eng.st
	match str(req["type"]):
		"turn":
			return _turn(st, s, req)
		"after":
			if req.get("juggler", false):
				return {"k": "juggler"}
			return {"k": "end"}
		"cubes2":
			return _cubes2(st, s, int(req.get("k", 2)))
		"good":
			return _best_good(st, s, req["options"])
		"priv":
			return _best_priv(st, s, req["options"])
		"inn_buy":
			return _inn_buy(st, s, req["options"])
		"island":
			return _island(st, s, req["isl"], req["opts"])
		"family":
			return _family(st, s, req["options"])
		"herb":
			return "stay"
		"noble":
			return _noble(st, s)
		"city":
			return _city(st, s, req["options"])
		"abbot":
			return _abbot(st, s, req["options"])
		"use_card":
			return _use_card(st, s, str(req["key"]))
		"market":
			return _market(st, s, req["options"], bool(req.get("free", false)))
		"scrap":
			return _scrap(st, s, req["options"])
		"priest":
			return _priest(st, s, req["pieces"])
		"mass_buy":
			return _mass_buy(st, s, req["options"], int(req["max"]))
		"mass_up":
			return _mass_up(st, s, req["members"])
		"death":
			return _death(st, s, req["options"], bool(req.get("bard", false)))
	return null


func _noise() -> float:
	match level:
		0: return rng.randf_range(-3.0, 3.0)
		1: return rng.randf_range(-0.8, 0.8)
	return rng.randf_range(-0.1, 0.1)


# ------------------------------------------------------------------ turno

func _turn(st: VLState, p: int, req: Dictionary):
	var moves: Array = req["moves"]
	var base := value(st, p)
	# carte da giocare subito (effetto immediato)
	var best_card := -1
	var best_cv := 1.2
	for cid in req.get("cards", []):
		var c := st.clone()
		var r := c.play_card(p, cid)
		_greedy(c, p, r)
		var dv := value(c, p) - base
		if dv > best_cv:
			best_cv = dv
			best_card = cid
	if best_card >= 0 and level > 0:
		return {"k": "card", "id": best_card}
	if moves.is_empty():
		return 0
	var cand := _candidates(st, p, moves)
	var best := 0
	var bv := -INF
	for i in cand:
		var v := eval_move(st, p, moves[i]) + _noise()
		if v > bv:
			bv = v
			best = i
	if level == 0 and rng.randf() < 0.15:
		best = cand[rng.randi() % cand.size()]
	return best


## Per ogni spazio basta valutare il cubo migliore; per il pozzo solo il colore più abbondante.
func _candidates(st: VLState, p: int, moves: Array) -> Array:
	var best_cube := {}
	for sp in st.spaces:
		var bc := ""
		var bv := -99.0
		for c in st.spaces[sp]:
			var v := _cube_value(st, p, c)
			if v > bv:
				bv = v
				bc = c
		best_cube[sp] = bc
	var well_c := ""
	var wv := 0
	for c in D.CUBES:
		if st.count_cube(p, c) >= 3 and st.count_cube(p, c) > wv:
			wv = st.count_cube(p, c)
			well_c = c
	var out := []
	for i in moves.size():
		var src: Dictionary = moves[i]["src"]
		match str(src["t"]):
			"space":
				if src["c"] == best_cube.get(src["sp"], ""):
					out.append(i)
			"well":
				if src["c"] == well_c:
					out.append(i)
			_:
				out.append(i)
	if out.is_empty():
		for i in moves.size():
			out.append(i)
	return out


func _cube_value(st: VLState, p: int, c: String) -> float:
	if c == "pl":
		return -2.0 * W["time"] - 0.3
	var v: float = W["cube"]
	if c == "gr":
		v += W["green"]
	# servono di più i colori che mancano per completare un tris (pozzo) o un pagamento
	var have := st.count_cube(p, c)
	if have == 2:
		v += 0.25
	return v


## Valore di una mossa: la si gioca su una copia e si valuta il risultato.
func eval_move(st: VLState, p: int, mv: Dictionary) -> float:
	var c := st.clone()
	var t0 := int(c.players[p]["time"]) + 10 * int(c.players[p]["deaths"])
	var r := c.apply_move(p, mv)
	_greedy(c, p, r)
	var spent := int(c.players[p]["time"]) + 10 * int(c.players[p]["deaths"]) - t0
	var v: float = value(c, p) - float(spent) * W["time"] * (1.0 - 0.6 * progress(c))
	# morti in sospeso: si risolvono col familiare migliore
	var k := 0
	while int(c.players[p]["deaths"]) > 0 and k < 4:
		var opts := c.death_options(p)
		if opts.is_empty():
			break
		var mid := _best_death(c, p, opts)
		if c.apply_death(p, mid, false) and c.end_by < 0:
			c.end_by = p
		k += 1
	if k > 0:
		v = value(c, p) - float(spent) * W["time"] * (1.0 - 0.6 * progress(c))
	# il segnalino del prossimo primo giocatore tolto agli altri
	if c.next_owner == p and st.next_owner != p:
		v += 0.4
	# Difficile: guarda anche quanto la mossa toglie (o lascia) agli avversari
	if level >= 2 and W["rival"] > 0.0:
		var best_o := -INF
		for o in c.n:
			if o != p:
				best_o = maxf(best_o, value(c, o))
		v -= W["rival"] * best_o
	return v


## Risolve sulla copia le scelte lasciate aperte da un'azione, nel modo migliore per p.
func _greedy(c: VLState, p: int, r: Dictionary) -> void:
	if r.is_empty():
		return
	if r.has("market"):
		var opts := c.market_options(p, true, false)
		var i: int = _market(c, p, opts, true)
		if opts[i]["k"] != "pass":
			c.apply_sale(p, opts[i], true)
	if r.has("priv"):
		var po := c.priv_options(p, int(r["priv"]))
		if not po.is_empty():
			var l: int = _best_priv(c, p, po)
			_greedy(c, p, c.apply_priv(p, l))
	if r.has("priv2"):
		for k in 2:
			var po2 := c.priv_options(p, int(r["priv2"]))
			if not po2.is_empty():
				var l2: int = _best_priv(c, p, po2)
				_greedy(c, p, c.apply_priv(p, l2))
	if r.has("cubes2"):
		c.apply_cubes(p, _cubes2(c, p, int(r["cubes2"])))
	if r.has("good"):
		var go: Array = r["good"] if r["good"] is Array else c.good_choices()
		c.apply_good(p, _best_good(c, p, go))
	if r.has("inn_buy"):
		var io := c.inn_buy_options(p)
		if not io.is_empty():
			var d: int = _inn_buy(c, p, io)
			if d >= 0:
				c.buy_card(p, d)
	if r.has("island"):
		var isl: String = r["island"]
		c.apply_island(p, isl, _island(c, p, isl, c.island_options(p, isl)))
	if r.has("family"):
		var fo := c.action_options(p, "family")
		if not fo.is_empty():
			c.apply_action(p, fo[_family(c, p, fo)])
	if r.has("noble"):
		var nb: Dictionary = _noble(c, p)
		c.noble_take(p, int(nb["d"]), int(nb["c"]))
	if r.has("city"):
		var cs := c.messenger_cities(p)
		if not cs.is_empty():
			_greedy(c, p, c.visit_city(p, _city(c, p, cs)))
	if r.has("abbot"):
		var cm := c.church_members(p)
		if not cm.is_empty():
			c.abbot_move(p, _abbot(c, p, cm.map(func(m): return m["id"])))


# ------------------------------------------------------------------ scelte

func _cubes2(st: VLState, p: int, k: int) -> Array:
	var out := []
	var tmp := {}
	for c in D.CUBES:
		tmp[c] = st.count_cube(p, c)
	for i in k:
		var best := ""
		var bv := -99.0
		for c in D.CUBES:
			if int(st.supply[c]) - out.count(c) <= 0:
				continue
			var v := 0.4 + (0.25 if c == "gr" else 0.0)
			if int(tmp[c]) == 2:
				v += 0.35
			if int(tmp[c]) >= 4:
				v -= 0.2
			v += rng.randf_range(0.0, 0.05)
			if v > bv:
				bv = v
				best = c
		if best != "":
			out.append(best)
			tmp[best] += 1
	return out


func _best_good(st: VLState, p: int, opts: Array) -> String:
	var best: String = opts[0]
	var bv := -INF
	for g in opts:
		var c := st.clone()
		c.apply_good(p, str(g))
		var v := value(c, p)
		if v > bv:
			bv = v
			best = str(g)
	return best


func _best_priv(st: VLState, p: int, opts: Array) -> int:
	var best: int = opts[0]
	var bv := -INF
	for l in opts:
		var c := st.clone()
		var r := c.apply_priv(p, int(l))
		if r.has("cubes2"):
			c.apply_cubes(p, _cubes2(c, p, 2))
		if r.has("good"):
			c.apply_good(p, _best_good(c, p, c.good_choices()))
		var v := value(c, p)
		if int(l) == 1:
			v += 0.5
		if v > bv:
			bv = v
			best = int(l)
	return best


func _inn_buy(st: VLState, p: int, opts: Array) -> int:
	var best := -1
	var bv := 0.3
	for d in opts:
		var c := st.clone()
		c.buy_card(p, d)
		var v := value(c, p) - value(st, p)
		if v > bv:
			bv = v
			best = d
	return best


func _island(st: VLState, p: int, isl: String, opts: Dictionary) -> Dictionary:
	var r := {"sell": opts.get("sell", []).duplicate(), "take": opts.get("take", false), "take2": opts.get("take2", false), "mission": -1}
	var mis: Array = opts.get("mission", [])
	if not mis.is_empty():
		r["mission"] = mis[0]
	return r


func _family(st: VLState, p: int, opts: Array) -> int:
	var best := 0
	var bv := -INF
	for i in opts.size():
		var c := st.clone()
		c.apply_action(p, opts[i])
		var v := value(c, p)
		if v > bv:
			bv = v
			best = i
	return best


func _noble(st: VLState, p: int) -> Dictionary:
	var best := {"d": -1, "c": -1}
	var bv := -INF
	for d in st.decks.size():
		for cid in st.decks[d]:
			var c := st.clone()
			c.noble_take(p, d, cid)
			var v := value(c, p)
			if v > bv:
				bv = v
				best = {"d": d, "c": cid}
	return best


func _city(st: VLState, p: int, opts: Array) -> String:
	var best: String = opts[0]
	var bv := -INF
	for cty in opts:
		var c := st.clone()
		var r := c.visit_city(p, cty)
		if r.has("cubes2"):
			c.apply_cubes(p, _cubes2(c, p, 2))
		var v := value(c, p)
		if v > bv:
			bv = v
			best = cty
	return best


func _abbot(st: VLState, p: int, ids: Array) -> int:
	var best: int = ids[0]
	var lo := 99
	for id in ids:
		var w := int(str(st.members[id]["loc"]).substr(7))
		if w < lo:
			lo = w
			best = id
	return best


func _use_card(st: VLState, p: int, key: String) -> bool:
	match key:
		"barker":
			for i in 5:
				if st.queue[i] >= 0 and st.can_serve(p, st.queue[i]) and int(D.CUSTOMERS[st.queue[i]]["pp"]) >= 4:
					return true
			return false
		"priest":
			var own := 0
			for m in st.bag_members():
				if m["owner"] == p:
					own += 1
			return own >= 2
	return false


func _market(st: VLState, p: int, opts: Array, free: bool) -> int:
	var base := value(st, p)
	var best := opts.size() - 1
	var bv := 0.15 if free else 0.6
	for i in opts.size():
		if opts[i]["k"] == "pass":
			continue
		var c := st.clone()
		c.apply_sale(p, opts[i], free)
		var v := value(c, p) - base
		if not free:
			v -= W["time"] * 0.6
		if v > bv:
			bv = v
			best = i
	return best


func _scrap(st: VLState, p: int, opts: Array) -> int:
	var best := -1
	var bp := 0
	for i in opts:
		var pp := int(D.CUSTOMERS[st.front[i]]["pp"])
		if pp > bp:
			bp = pp
			best = i
	return best


func _priest(st: VLState, p: int, pieces: Array) -> Array:
	var out := []
	for id in pieces:
		if st.members[id]["owner"] == p and out.size() < 4:
			out.append(id)
	return out


func _mass_buy(st: VLState, p: int, opts: Array, mx: int) -> Array:
	var f := progress(st)
	var out := []
	# conviene se la chiesa vale più della moneta: sempre verso la fine, all'inizio solo i più giovani
	var sorted := opts.duplicate()
	sorted.sort_custom(func(a, b): return int(st.members[a]["gen"]) > int(st.members[b]["gen"]))
	for id in sorted:
		if out.size() >= mx:
			break
		if f > 0.25 or int(st.players[p]["coins"]) - out.size() >= 3 or level == 0:
			out.append(id)
	return out


func _mass_up(st: VLState, p: int, ids: Array) -> Dictionary:
	var f := progress(st)
	var grain: int = st.players[p]["grain"]
	var best := {}
	var bv := 0.0
	# combinazioni: per ogni familiare la vetrata d'arrivo (al massimo 4 familiari provati)
	var cand := ids.slice(0, 4)
	var choices := []
	for id in cand:
		var w := int(str(st.members[id]["loc"]).substr(7))
		var opts := [w]
		for t in range(w + 1, 4):
			opts.append(t)
		choices.append(opts)
	var combos := [{}]
	for i in cand.size():
		var nxt := []
		for cmb in combos:
			for t in choices[i]:
				var c2: Dictionary = cmb.duplicate()
				var w0 := int(str(st.members[cand[i]]["loc"]).substr(7))
				if t > w0:
					c2[cand[i]] = t
				nxt.append(c2)
		combos = nxt
	for cmb in combos:
		if cmb.is_empty():
			continue
		var cost := 0
		var gain := 0.0
		for id in cmb:
			var w0 := int(str(st.members[id]["loc"]).substr(7))
			cost += VLState.climb_cost(w0, int(cmb[id]))
			gain += float(D.WINDOW_PTS[int(cmb[id])] - D.WINDOW_PTS[w0])
		if cost > grain:
			continue
		var v: float = gain - float(cost) * W["grain"] * (1.0 - W["late"] * f) * 1.15
		if v > bv:
			bv = v
			best = cmb
	return best


func _death(st: VLState, p: int, opts: Array, bard: bool) -> Dictionary:
	var mid := _best_death(st, p, opts)
	var use_bard := false
	if bard:
		var c := st.clone()
		var sec := c.section_of(str(c.members[mid]["loc"]))
		var free := false
		if sec != "":
			for v in c.chron[sec]:
				if int(v) == -1:
					free = true
		use_bard = not free
	return {"m": mid, "bard": use_bard}


func _best_death(st: VLState, p: int, opts: Array) -> int:
	var best: int = opts[0]
	var bv := -INF
	for mid in opts:
		var c := st.clone()
		if c.apply_death(p, mid, false) and c.end_by < 0:
			c.end_by = p
		var v := value(c, p)
		if v > bv:
			bv = v
			best = mid
	return best
