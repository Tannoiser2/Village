class_name VLState
extends RefCounted
## Stato completo di una partita a Village e tutte le regole "immediate" (senza attese né decisioni):
## pagamenti, azioni, mercato, messa, morte, obiettivi e punteggio. Il motore (engine.gd) chiede le
## decisioni e chiama queste funzioni; l'IA le usa su copie dello stato per provare le mosse.

const D = preload("res://scripts/data/vl_data.gd")

var n := 0
var inn := false
var port := false
var goals_on := false
var mode := "base"
var rng := RandomNumberGenerator.new()

var players: Array = []
var members: Array = []          # {id, owner, gen, loc}
var spaces := {}                 # spazio -> [cubi]
var bag := {}                    # sacchetto verde: colore -> numero
var supply := {}                 # riserva: colore -> numero (anche "pl")
var front: Array = []            # clienti davanti alle bancarelle (indice in CUSTOMERS, -1 vuoto)
var queue: Array = []            # clienti in coda
var pile: Array = []
var front_n := 5
var chron := {}                  # sezione -> [proprietario | -1 libero | -2 coperto]
var graves: Array = []
var burials: Array = []
var big_chron := false
var first := 0
var next_owner := -1
var round_no := 0
var decks: Array = []            # Locanda: 3 mazzi di abitanti (l'ultimo elemento è in cima)
var captains: Array = []         # Porto: 3 mazzi di capitani
var stacks := {}                 # Porto: forzieri, cacao, tè sulle isole
var missions := {}               # Porto: isola -> familiare (-1 libera)
var end_by := -1                 # chi ha fatto scattare la fine
var game_over := false
var log: Array = []              # righe nuove per la cronaca (le prende il motore)


# ================================================================== preparazione

## config: {"seats":[{"color","ai","name","level"}], "seed", "opts":{"inn","port","goals"}}
func setup(config: Dictionary) -> void:
	if config.has("seed"):
		rng.seed = int(config["seed"])
	else:
		rng.randomize()
	var o: Dictionary = config.get("opts", {})
	inn = bool(o.get("inn", false))
	port = bool(o.get("port", false))
	goals_on = bool(o.get("goals", false))
	mode = ("innport" if port else "inn") if inn else ("port" if port else "base")
	n = config["seats"].size()
	big_chron = inn or n == 5
	players.clear()
	members.clear()
	for s in n:
		var st: Dictionary = config["seats"][s]
		var p := {"color": int(st["color"]), "ai": bool(st.get("ai", false)), "name": str(st["name"]), "level": int(st.get("level", 1)),
			"pp": 0, "time": 0, "coins": 1, "grain": 0, "cubes": {"pk": 0, "br": 0, "gr": 0, "or": 0},
			"goods": {}, "customers": [], "hand": [], "goals": [], "goals_done": [], "cities": [], "deaths": 0,
			"bard": 0, "chests": [], "ship": {"at": "P", "cap": -1, "helm": false, "hold": []}}
		for g in D.GOODS:
			p["goods"][g] = 0
		if inn:
			p["goods"]["beer"] = 1
		players.append(p)
		for k in D.GENS.size():
			members.append({"id": s * 11 + k, "owner": s, "gen": D.GENS[k], "loc": "farm" if D.GENS[k] == 1 else "pool"})
	for c in D.CUBES:
		supply[c] = D.CUBE_SUPPLY + (D.CUBE_SUPPLY_INN if inn else 0) + (D.CUBE_SUPPLY_PORT if port else 0)
		bag[c] = 0
	supply["pl"] = D.PLAGUE
	bag["pl"] = 0
	for sp in D.SPACES:
		spaces[sp] = []
	# mercato
	pile.clear()
	for i in D.CUSTOMERS.size():
		if inn or not D.CUSTOMERS[i].get("inn", false):
			pile.append(i)
	_shuffle(pile)
	front_n = 3 if n == 2 else (4 if n == 3 else 5)
	front = [-1, -1, -1, -1, -1]
	queue = [-1, -1, -1, -1, -1]
	for i in front_n:
		front[i] = pile.pop_back()
	for i in 5:
		queue[i] = pile.pop_back() if not pile.is_empty() else -1
	# cronache e tombe
	var ch: Dictionary = D.CHRON_BIG if big_chron else D.CHRON_SMALL
	for sec in D.SECTIONS:
		chron[sec] = []
		for lab in ch[sec]:
			chron[sec].append(-2 if lab > n else -1)
	graves = []
	for lab in (D.GRAVES_BIG if big_chron else D.GRAVES_SMALL):
		graves.append(-2 if lab > n else -1)
	burials = [-1, -1, -1] if port else []
	# Locanda
	decks = []
	if inn:
		var cards := []
		for v in D.VILLAGERS:
			if v["set"] == "inn" or (v["set"] == "innonly" and not port) or (v["set"] == "port" and port):
				cards.append(v["id"])
		_shuffle(cards)
		for d in D.DECKS:
			decks.append(cards.slice(d * D.DECK_SIZE, (d + 1) * D.DECK_SIZE))
	# Porto
	captains = []
	stacks = {}
	missions = {}
	if port:
		captains = [[0, 1, 2, 3, 4], [5, 6, 7, 8, 9], [10, 11, 12, 13, 14]]
		var ch2: Array = D.CHESTS.duplicate()
		_shuffle(ch2)
		stacks = {"chest": ch2, "cocoa": D.PORT_STACK[n], "tea": D.PORT_STACK[n]}
		for isl in D.MISSIONS:
			missions[isl] = -1
	# obiettivi di vita
	if goals_on:
		var sil := []
		for i in D.GOALS_SILVER.size():
			if not (mode in D.GOALS_SILVER[i].get("no", [])):
				sil.append(i)
		var gol := []
		for i in D.GOALS_GOLD.size():
			if not (mode in D.GOALS_GOLD[i].get("no", [])):
				gol.append(i)
		_shuffle(sil)
		_shuffle(gol)
		for s in n:
			players[s]["goals"] = [["s", sil[s]], ["g", gol[s]]]
	first = rng.randi() % n
	next_owner = -1
	round_no = 0


func clone() -> VLState:
	var c := VLState.new()
	c.n = n
	c.inn = inn
	c.port = port
	c.goals_on = goals_on
	c.mode = mode
	c.rng.seed = rng.seed
	c.rng.state = rng.state
	c.players = players.duplicate(true)
	c.members = members.duplicate(true)
	c.spaces = spaces.duplicate(true)
	c.bag = bag.duplicate()
	c.supply = supply.duplicate()
	c.front = front.duplicate()
	c.queue = queue.duplicate()
	c.pile = pile.duplicate()
	c.front_n = front_n
	c.chron = chron.duplicate(true)
	c.graves = graves.duplicate()
	c.burials = burials.duplicate()
	c.big_chron = big_chron
	c.first = first
	c.next_owner = next_owner
	c.round_no = round_no
	c.decks = decks.duplicate(true)
	c.captains = captains.duplicate(true)
	c.stacks = stacks.duplicate(true)
	c.missions = missions.duplicate()
	c.end_by = end_by
	c.game_over = game_over
	return c


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


func say(t: String) -> void:
	log.append(t)


static func tt(k: int) -> String:
	return "%d %s" % [k, "tempo" if k == 1 else "tempi"]


func pname(s: int) -> String:
	return players[s]["name"] if s >= 0 and s < n else "nessuno"


func next_seat(s: int) -> int:
	return (s + 1) % n


# ================================================================== round e cubi

func start_round() -> void:
	round_no += 1
	if next_owner >= 0:
		first = next_owner
		next_owner = -1
	var su: Dictionary = D.SETUP[mode][n]
	for i in 4:
		var c: String = D.CUBES[i]
		var k := mini(int(su["bag"][i]), int(supply[c]))
		supply[c] -= k
		bag[c] += k
	bag["pl"] += supply["pl"]
	supply["pl"] = 0
	for i in D.SPACES.size():
		var sp: String = D.SPACES[i]
		spaces[sp] = []
		for k in int(su["sp"][i]):
			var c2 := _draw_bag()
			if c2 == "":
				break
			spaces[sp].append(c2)


func _draw_bag() -> String:
	var tot := 0
	for c in bag:
		tot += int(bag[c])
	if tot <= 0:
		return ""
	var r := rng.randi() % tot
	for c in ["pk", "br", "gr", "or", "pl"]:
		if r < int(bag[c]):
			bag[c] -= 1
			return c
		r -= int(bag[c])
	return ""


func cubes_left() -> int:
	var t := 0
	for sp in spaces:
		t += spaces[sp].size()
	return t


func space_active(sp: String) -> bool:
	return sp != "inn" or inn


# ================================================================== pagamenti

func count_cube(p: int, c: String) -> int:
	return int(players[p]["cubes"][c])


## Si possono pagare questi cubi (le monete fanno da jolly)? "any" = colore a scelta.
func can_pay_cubes(p: int, list: Array, extra_coins := 0) -> bool:
	return _missing(p, list) + extra_coins <= int(players[p]["coins"])


func _missing(p: int, list: Array) -> int:
	var need := {}
	var anyn := 0
	for c in list:
		if c == "any":
			anyn += 1
		else:
			need[c] = int(need.get(c, 0)) + 1
	var miss := 0
	var spare := 0
	for c in D.CUBES:
		var have := count_cube(p, c)
		var nd := int(need.get(c, 0))
		if have < nd:
			miss += nd - have
		else:
			spare += have - nd
	miss += maxi(0, anyn - spare)
	return miss


## Paga i cubi: prima i propri, poi le monete al posto di quelli che mancano. Per "any" sceglie i
## colori di cui se ne hanno di più. Restituisce la descrizione del pagamento.
func pay_cubes(p: int, list: Array) -> String:
	var pl: Dictionary = players[p]
	var parts := []
	var coins := 0
	var anyn := 0
	for c in list:
		if c == "any":
			anyn += 1
			continue
		if int(pl["cubes"][c]) > 0:
			pl["cubes"][c] -= 1
			supply[c] += 1
			parts.append(D.cube_name(c))
		else:
			pl["coins"] -= 1
			coins += 1
	for k in anyn:
		var best := ""
		var bv := 0
		for c in D.CUBES:
			if int(pl["cubes"][c]) > bv:
				bv = int(pl["cubes"][c])
				best = c
		if best != "":
			pl["cubes"][best] -= 1
			supply[best] += 1
			parts.append(D.cube_name(best))
		else:
			pl["coins"] -= 1
			coins += 1
	if coins > 0:
		parts.append("%d %s" % [coins, "moneta" if coins == 1 else "monete"])
	return ", ".join(parts)


func gain_cube(p: int, c: String) -> bool:
	if int(supply.get(c, 0)) <= 0:
		return false
	supply[c] -= 1
	players[p]["cubes"][c] += 1
	return true


func gain_grain(p: int, k: int) -> int:
	var pl: Dictionary = players[p]
	var g := mini(k, D.GRAIN_MAX - int(pl["grain"]))
	pl["grain"] += maxi(0, g)
	return maxi(0, g)


func gain_good(p: int, g: String, k := 1) -> void:
	players[p]["goods"][g] += k


## Paga del tempo: il segnatempo avanza; ogni volta che passa il ponte muore un familiare (dopo).
func pay_time(p: int, t: int) -> void:
	if t <= 0:
		return
	var pl: Dictionary = players[p]
	var v: int = int(pl["time"]) + t
	while v >= D.TIME_STEPS:
		v -= D.TIME_STEPS
		pl["deaths"] += 1
	pl["time"] = v


func gain_pp(p: int, k: int) -> void:
	players[p]["pp"] += k


# ================================================================== familiari

func m_of(p: int, loc: String) -> Array:
	var out := []
	for m in members:
		if m["owner"] == p and m["loc"] == loc:
			out.append(m)
	return out


func m_prefix(p: int, pre: String) -> Array:
	var out := []
	for m in members:
		if m["owner"] == p and str(m["loc"]).begins_with(pre):
			out.append(m)
	return out


func farm(p: int) -> Array:
	return m_of(p, "farm")


## Un familiare per ogni generazione diversa (le altre scelte sono equivalenti).
func distinct_gen(list: Array) -> Array:
	var seen := {}
	var out := []
	for m in list:
		var key := "%s/%d" % [m["loc"], m["gen"]]
		if not seen.has(key):
			seen[key] = true
			out.append(m)
	return out


func next_unborn(p: int) -> Dictionary:
	var best := {}
	for m in members:
		if m["owner"] == p and m["loc"] == "pool":
			if best.is_empty() or int(m["gen"]) < int(best["gen"]):
				best = m
	return best


## Familiari vivi e visibili (quelli che possono morire): fattoria e tabellone, non il sacchetto nero.
const ALIVE_LOCS := ["farm", "craft:", "council:", "city:", "church:", "inn", "ship", "mission:"]


func is_visible_alive(m: Dictionary) -> bool:
	var l: String = m["loc"]
	for pre in ALIVE_LOCS:
		if l == pre or (pre.ends_with(":") and l.begins_with(pre)):
			return true
	return false


func is_living(m: Dictionary) -> bool:
	return is_visible_alive(m) or m["loc"] == "bag"


func on_board_returnable(p: int) -> Array:
	var out := []
	for m in members:
		if m["owner"] != p:
			continue
		var l: String = m["loc"]
		if l.begins_with("craft:") or l.begins_with("council:") or l.begins_with("city:") or l.begins_with("church:") or l == "inn":
			out.append(m)
	return out


func loc_name(loc: String) -> String:
	if loc == "farm":
		return "fattoria"
	if loc == "pool":
		return "riserva"
	if loc == "bag":
		return "sacchetto nero"
	if loc == "inn":
		return "Locanda"
	if loc == "ship":
		return "nave"
	if loc.begins_with("craft:"):
		return D.CRAFT[loc.substr(6)]["name"]
	if loc.begins_with("council:"):
		return "Consiglio, livello %s" % loc.substr(8)
	if loc.begins_with("city:"):
		return D.CITY[loc.substr(5)]["name"]
	if loc.begins_with("church:"):
		return "chiesa, vetrata da %d" % D.WINDOW_PTS[int(loc.substr(7))]
	if loc.begins_with("mission:"):
		return "chiesa missionaria (%s)" % D.SEA[loc.substr(8)]["name"]
	return loc


func mdesc(m: Dictionary) -> String:
	return "familiare %d (%s)" % [m["gen"], loc_name(m["loc"])]


# ================================================================== azioni: elenco delle mosse

## Mosse del turno: ogni mossa è {"k":"move", "src":{...}, "a":{...}}.
## src: {"t":"space","sp","c"} prendi un cubo · {"t":"well","c"} paga 3 cubi uguali · {"t":"oldman"} Vecchio saggio ·
## {"t":"free"} azione finale gratuita quando il tabellone è vuoto.
func turn_moves(p: int, final := false) -> Array:
	var out := []
	var left := cubes_left()
	if final and left == 0:
		for a in all_actions(p):
			out.append({"k": "move", "src": {"t": "free"}, "a": a})
		return out
	for sp in D.SPACES:
		if not space_active(sp):
			continue
		var colors := {}
		for c in spaces[sp]:
			colors[c] = true
		if colors.is_empty():
			continue
		var acts := action_options(p, sp)
		for c in colors:
			out.append({"k": "move", "src": {"t": "space", "sp": sp, "c": c}, "a": {"a": "none"}})
			for a in acts:
				out.append({"k": "move", "src": {"t": "space", "sp": sp, "c": c}, "a": a})
	if left > 0:
		for c in D.CUBES:
			if count_cube(p, c) >= 3:
				for a in all_actions(p, c):
					out.append({"k": "move", "src": {"t": "well", "c": c}, "a": a})
	return out


func all_actions(p: int, well_color := "") -> Array:
	var out := []
	for sp in D.SPACES:
		if not space_active(sp):
			continue
		for a in action_options(p, sp, well_color):
			out.append(a)
	return out


## Azioni possibili per uno spazio. well_color: cubi già impegnati per il pozzo (3 di quel colore).
func action_options(p: int, sp: String, well_color := "") -> Array:
	var pl: Dictionary = players[p]
	var out := []
	var fm := farm(p)
	var dg := distinct_gen(fm)
	match sp:
		"harvest":
			if fm.size() > 0 and int(pl["grain"]) < D.GRAIN_MAX:
				out.append({"a": "harvest"})
		"family":
			if not next_unborn(p).is_empty():
				out.append({"a": "family", "m": -1})
			for m in distinct_gen(on_board_returnable(p)):
				out.append({"a": "family", "m": m["id"]})
		"crafts":
			for b in D.CRAFTS:
				if b == "brewery" and not inn:
					continue
				if b == "mill":
					if int(pl["grain"]) >= 2:
						out.append({"a": "craft", "b": "mill"})
						if has_card(p, "miller"):
							out.append({"a": "craft", "b": "mill", "miller": true})
					continue
				var cr: Dictionary = D.CRAFT[b]
				var goods_opts: Array = ["horse", "ox"] if b == "stable" else [cr["good"]]
				var here := m_of(p, "craft:" + b).size() > 0
				for g in goods_opts:
					if here:
						out.append({"a": "craft", "b": b, "how": "make", "g": g})
					else:
						for m in dg:
							out.append({"a": "craft", "b": b, "how": "trainmake", "g": g, "m": m["id"]})
					if cr.has("grain"):
						if int(pl["grain"]) >= int(cr["grain"]):
							out.append({"a": "craft", "b": b, "how": "buy", "g": g})
					elif _can_pay_well(p, cr["buy"], well_color):
						out.append({"a": "craft", "b": b, "how": "buy", "g": g})
				if not here:
					for m in dg:
						out.append({"a": "craft", "b": b, "how": "train", "m": m["id"]})
		"market":
			out.append({"a": "market"})
		"travel":
			if port:
				for mv in sail_options(p, well_color):
					out.append(mv)
			else:
				var toll := has_card(p, "toll")
				var at_city := distinct_gen(m_prefix(p, "city:"))
				if int(pl["goods"]["wagon"]) >= 1 or toll:
					for m in dg:
						for c in ["A", "F"]:
							_travel_opt(p, out, m["id"], c, D.road("G", c), toll, well_color)
					for m in at_city:
						var from: String = str(m["loc"]).substr(5)
						for c in D.city_neighbors(from):
							if c == "G":
								continue
							_travel_opt(p, out, m["id"], c, D.road(from, c), toll, well_color)
		"council":
			var cm := m_prefix(p, "council:")
			var pays := []
			if _can_pay_well(p, ["gr", "gr"], well_color):
				pays.append("green")
			if int(pl["goods"]["scroll"]) >= 1:
				pays.append("scroll")
			for pay in pays:
				for m in dg:
					out.append({"a": "council", "how": "enter", "m": m["id"], "pay": pay})
				for m in distinct_gen(cm):
					if int(str(m["loc"]).substr(8)) < 4:
						out.append({"a": "council", "how": "up", "m": m["id"], "pay": pay})
			if cm.size() > 0:
				out.append({"a": "council", "how": "priv"})
		"church":
			for m in dg:
				if _can_pay_well(p, ["br"], well_color):
					out.append({"a": "church", "m": m["id"], "pay": "brown"})
				out.append({"a": "church", "m": m["id"], "pay": "time"})
		"inn":
			var here2 := m_of(p, "inn").size() > 0
			var cands := [-1] if here2 else []
			if not here2:
				for m in dg:
					cands.append(m["id"])
			for mid in cands:
				for d in decks.size():
					if decks[d].size() > 0:
						out.append({"a": "inn", "m": mid, "rot": d})
	return out


func _travel_opt(p: int, out: Array, mid: int, to: String, cost: Array, toll: bool, well_color: String) -> void:
	if int(players[p]["goods"]["wagon"]) >= 1 and _can_pay_well(p, cost, well_color):
		out.append({"a": "travel", "m": mid, "to": to})
	if toll:
		out.append({"a": "travel", "m": mid, "to": to, "toll": true})


## Si può pagare tenendo conto dei 3 cubi già dati al pozzo.
func _can_pay_well(p: int, list: Array, well_color: String) -> bool:
	if well_color == "":
		return can_pay_cubes(p, list)
	var pl: Dictionary = players[p]
	pl["cubes"][well_color] -= 3
	var ok := can_pay_cubes(p, list)
	pl["cubes"][well_color] += 3
	return ok


# ================================================================== azioni: esecuzione

## Prende il cubo (o paga il pozzo) ed esegue l'azione. Restituisce le richieste che restano al motore:
## {"market":true} giorno di mercato · {"priv":lv} scelta del privilegio · {"cubes2":k} cubi a scelta ·
## {"good":true} merce a scelta · {"inn_buy":true} · {"island":isola}.
func apply_move(p: int, mv: Dictionary) -> Dictionary:
	var src: Dictionary = mv["src"]
	var pl: Dictionary = players[p]
	match str(src["t"]):
		"space":
			var arr: Array = spaces[src["sp"]]
			var i := arr.find(src["c"])
			if i >= 0:
				arr.remove_at(i)
			if src["c"] == "pl":
				supply["pl"] += 1
				pay_time(p, 2)
				say("%s prende un cubo peste da %s e perde 2 tempi." % [pname(p), D.SPACE[src["sp"]]["name"]])
			else:
				pl["cubes"][src["c"]] += 1
				say("%s prende un cubo %s da %s." % [pname(p), D.cube_name(src["c"]), D.SPACE[src["sp"]]["name"]])
		"well":
			pl["cubes"][src["c"]] -= 3
			supply[src["c"]] += 3
			say("%s usa il pozzo: restituisce 3 cubi %s." % [pname(p), D.cube_name(src["c"])])
		"oldman":
			discard_card(p, "oldman")
			gain_pp(p, 3)
			say("%s gioca il Vecchio saggio: 3 punti e un'azione gratuita." % pname(p))
		"free":
			say("%s fa la sua ultima azione (il tabellone è vuoto)." % pname(p))
	return apply_action(p, mv["a"])


func apply_action(p: int, a: Dictionary) -> Dictionary:
	var pl: Dictionary = players[p]
	var res := {}
	match str(a.get("a", "none")):
		"none":
			pass
		"harvest":
			var k := 2
			if int(pl["goods"]["plow"]) > 0 and int(pl["goods"]["ox"]) > 0:
				k = 4
			elif int(pl["goods"]["plow"]) > 0 and int(pl["goods"]["horse"]) > 0:
				k = 3
			var got := gain_grain(p, k)
			say("%s miete: +%d grano." % [pname(p), got])
		"family":
			_family(p, int(a["m"]))
		"craft":
			_craft(p, a)
		"market":
			res["market"] = true
		"travel":
			if a.has("sail") or a.has("ret"):
				res = _sail(p, a)
			else:
				res = _travel(p, a)
		"sail":
			res = _sail(p, a)
		"council":
			res = _council(p, a)
		"church":
			var m: Dictionary = members[int(a["m"])]
			if a["pay"] == "brown":
				var how := pay_cubes(p, ["br"])
				say("%s manda un familiare %d nel sacchetto nero della chiesa (paga %s)." % [pname(p), m["gen"], how])
			else:
				pay_time(p, 3)
				say("%s manda un familiare %d nel sacchetto nero della chiesa (3 tempi)." % [pname(p), m["gen"]])
			m["loc"] = "bag"
		"inn":
			if int(a["m"]) >= 0:
				members[int(a["m"])]["loc"] = "inn"
				pay_time(p, 1)
				say("%s manda un familiare %d alla Locanda (1 tempo)." % [pname(p), members[int(a["m"])]["gen"]])
			pay_time(p, 1)
			var d: int = int(a["rot"])
			if decks[d].size() > 0:
				var top: int = decks[d].pop_back()
				decks[d].insert(0, top)
				say("%s passa un'ora alla Locanda (1 tempo) e manda in fondo al mazzo %d %s." % [pname(p), d + 1, D.VILLAGERS[top]["name"]])
			res["inn_buy"] = true
	return res


func _family(p: int, mid: int) -> void:
	if mid < 0:
		var m := next_unborn(p)
		if m.is_empty():
			return
		m["loc"] = "farm"
		say("%s: nasce un familiare della generazione %d." % [pname(p), m["gen"]])
	else:
		var m2: Dictionary = members[mid]
		say("%s riporta a casa il %s." % [pname(p), mdesc(m2)])
		m2["loc"] = "farm"


func _craft(p: int, a: Dictionary) -> void:
	var pl: Dictionary = players[p]
	var b: String = a["b"]
	if b == "mill":
		pl["grain"] -= 2
		pay_time(p, 2)
		var k := 2
		if a.get("miller", false):
			discard_card(p, "miller")
			k = 5
		pl["coins"] += k
		say("%s macina al mulino: 2 grano e 2 tempi per %d monete%s." % [pname(p), k, " (Mugnaio)" if k == 5 else ""])
		return
	var cr: Dictionary = D.CRAFT[b]
	var how: String = a["how"]
	var g: String = a.get("g", cr.get("good", ""))
	var qty: int = int(cr.get("qty", 1))
	if how == "train" or how == "trainmake":
		var m: Dictionary = members[int(a["m"])]
		m["loc"] = "craft:" + b
		pay_time(p, int(cr["train"]))
		say("%s mette un familiare %d a bottega: %s (%s)." % [pname(p), m["gen"], cr["name"], tt(int(cr["train"]))])
	if how == "make" or how == "trainmake":
		pay_time(p, int(cr["make"]))
		gain_good(p, g, qty)
		say("%s produce %d %s (%s)." % [pname(p), qty, D.good_name(g, qty), tt(int(cr["make"]))])
	elif how == "buy":
		var paid := ""
		if cr.has("grain"):
			pl["grain"] -= int(cr["grain"])
			paid = "%d grano" % int(cr["grain"])
		else:
			paid = pay_cubes(p, cr["buy"])
		gain_good(p, g, qty)
		say("%s ottiene %d %s da %s pagando %s." % [pname(p), qty, D.good_name(g, qty), cr["name"], paid])


func _travel(p: int, a: Dictionary) -> Dictionary:
	var pl: Dictionary = players[p]
	var m: Dictionary = members[int(a["m"])]
	var from := "G" if m["loc"] == "farm" else str(m["loc"]).substr(5)
	var to: String = a["to"]
	if a.get("toll", false):
		discard_card(p, "toll")
		say("%s viaggia gratis grazie al Gabelliere." % pname(p))
	else:
		pay_time(p, 2)
		pl["goods"]["wagon"] -= 1
		var how := pay_cubes(p, D.road(from, to))
		say("%s viaggia verso %s (2 tempi, 1 carro, %s)." % [pname(p), D.CITY[to]["name"], how])
	m["loc"] = "city:" + to
	return visit_city(p, to)


## Segnalino sulla città e premio (una volta per partita per città).
func visit_city(p: int, to: String) -> Dictionary:
	var pl: Dictionary = players[p]
	if to in pl["cities"]:
		say("%s ha già un segnalino a %s: nessun premio." % [pname(p), D.CITY[to]["name"]])
		return {}
	pl["cities"].append(to)
	match str(D.CITY[to]["reward"]):
		"pp3":
			gain_pp(p, 3)
			say("%s: premio di %s, 3 punti prestigio." % [pname(p), D.CITY[to]["name"]])
		"coin":
			pl["coins"] += 1
			say("%s: premio di %s, 1 moneta." % [pname(p), D.CITY[to]["name"]])
		"cubes2":
			return {"cubes2": 2}
	return {}


func _council(p: int, a: Dictionary) -> Dictionary:
	var pl: Dictionary = players[p]
	var how: String = a["how"]
	if how == "priv":
		say("%s usa un privilegio della Camera di Consiglio." % pname(p))
		return {"priv": max_council(p)}
	var m: Dictionary = members[int(a["m"])]
	var lv := 1 if how == "enter" else int(str(m["loc"]).substr(8)) + 1
	var paid := ""
	if a["pay"] == "scroll":
		pl["goods"]["scroll"] -= 1
		paid = "1 pergamena"
	else:
		paid = pay_cubes(p, ["gr", "gr"])
	pay_time(p, D.COUNCIL_TIME[lv - 1])
	m["loc"] = "council:%d" % lv
	say("%s %s un familiare %d al livello %d del Consiglio (%s, %s)." % [pname(p), "porta" if how == "enter" else "promuove", m["gen"], lv, paid, tt(D.COUNCIL_TIME[lv - 1])])
	return {"priv": lv}


func max_council(p: int) -> int:
	var lv := 0
	for m in m_prefix(p, "council:"):
		lv = maxi(lv, int(str(m["loc"]).substr(8)))
	return lv


## Privilegi disponibili fino al livello lv.
func priv_options(p: int, lv: int) -> Array:
	var out := []
	for l in range(1, lv + 1):
		if l == 1 and next_owner >= 0:
			continue
		if l == 4 and int(players[p]["coins"]) < 1:
			continue
		out.append(l)
	return out


## Applica un privilegio. Restituisce le scelte ancora da fare (cubi o merce).
func apply_priv(p: int, l: int) -> Dictionary:
	match l:
		1:
			if next_owner < 0:
				next_owner = p
				say("%s prende il segnalino del prossimo primo giocatore." % pname(p))
		2:
			return {"cubes2": 2}
		3:
			return {"good": true}
		4:
			if int(players[p]["coins"]) >= 1:
				players[p]["coins"] -= 1
				gain_pp(p, 3)
				say("%s paga 1 moneta al Consiglio: 3 punti prestigio." % pname(p))
	return {}


func good_choices() -> Array:
	var out := ["horse", "ox", "plow", "wagon", "scroll"]
	if inn:
		out.append("beer")
	return out


func apply_cubes(p: int, list: Array) -> void:
	var got := []
	for c in list:
		if gain_cube(p, str(c)):
			got.append(D.cube_name(str(c)))
	if not got.is_empty():
		say("%s prende %s." % [pname(p), " e ".join(got)])


func apply_good(p: int, g: String) -> void:
	gain_good(p, g)
	say("%s prende 1 %s." % [pname(p), D.good_name(g)])


# ================================================================== Locanda

func inn_buy_options(p: int) -> Array:
	var out := []
	for d in decks.size():
		if decks[d].is_empty():
			continue
		var top: int = decks[d][-1]
		if can_afford_card(p, top):
			out.append(d)
	return out


func can_afford_card(p: int, cid: int) -> bool:
	var pl: Dictionary = players[p]
	match str(D.VILLAGERS[cid]["cost"]):
		"coin": return int(pl["coins"]) >= 1
		"beer": return int(pl["goods"]["beer"]) >= 1
		"beer2": return int(pl["goods"]["beer"]) >= 2
	return false


func buy_card(p: int, d: int) -> void:
	var pl: Dictionary = players[p]
	var cid: int = decks[d].pop_back()
	match str(D.VILLAGERS[cid]["cost"]):
		"coin": pl["coins"] -= 1
		"beer": pl["goods"]["beer"] -= 1
		"beer2": pl["goods"]["beer"] -= 2
	pl["hand"].append(cid)
	say("%s accoglie %s (paga %s)." % [pname(p), D.VILLAGERS[cid]["name"], D.cost_text(D.VILLAGERS[cid]["cost"])])


func has_card(p: int, key: String) -> bool:
	for cid in players[p]["hand"]:
		if D.VILLAGERS[cid]["key"] == key:
			return true
	return false


func card_id(key: String) -> int:
	for v in D.VILLAGERS:
		if v["key"] == key:
			return v["id"]
	return -1


func discard_card(p: int, key: String) -> void:
	var h: Array = players[p]["hand"]
	for i in h.size():
		if D.VILLAGERS[h[i]]["key"] == key:
			h.remove_at(i)
			return


## Carte "quando vuoi" giocabili adesso.
func playable_cards(p: int) -> Array:
	var out := []
	for cid in players[p]["hand"]:
		var v: Dictionary = D.VILLAGERS[cid]
		if v["kind"] != "any":
			continue
		match str(v["key"]):
			"abbot":
				if m_prefix(p, "church:").is_empty():
					continue
			"councilman":
				if m_prefix(p, "council:").is_empty():
					continue
			"noble":
				if decks.all(func(dk): return dk.is_empty()):
					continue
		if not (cid in out):
			out.append(cid)
	return out


# ================================================================== viaggio per mare (Porto)

func captain_spec(p: int) -> Dictionary:
	var c: int = int(players[p]["ship"]["cap"])
	if c == 100:
		return D.ADMIRAL
	if c < 0:
		return {}
	return D.CAPTAINS[c]


## Capitani ingaggiabili: uno per tipo diverso (costo e pagamento).
func hireable(p: int) -> Array:
	var out := []
	var seen := {}
	for d in captains:
		for c in d:
			var cs: Dictionary = D.CAPTAINS[c]
			var key := "%d/%s" % [cs["cost"], ",".join(cs["pay"])]
			if seen.has(key):
				continue
			if int(players[p]["coins"]) >= int(cs["cost"]):
				seen[key] = true
				out.append(c)
	if has_card(p, "admiral"):
		out.append(100)
	return out


## Cubi da pagare per fare `steps` passi con il capitano dato (il primo passo è gratis, il timoniere ne aggiunge uno).
func step_cost(spec: Dictionary, steps: int, helm: bool) -> Array:
	var free := 1 + (1 if helm else 0)
	var paid := maxi(0, steps - free)
	if paid == 0 or spec.is_empty():
		return []
	var units := int(ceil(float(paid) / float(spec["steps"])))
	var out := []
	for k in units:
		out.append_array(spec["pay"])
	return out


## Distanze in passi dal nodo dato (ricerca in ampiezza).
static func sea_dist(from: String) -> Dictionary:
	var dist := {from: 0}
	var q := [from]
	while not q.is_empty():
		var a: String = q.pop_front()
		for b in D.sea_neighbors(a):
			if not dist.has(b):
				dist[b] = dist[a] + 1
				q.append(b)
	return dist


static func sea_path(from: String, to: String) -> Array:
	var prev := {from: ""}
	var q := [from]
	while not q.is_empty():
		var a: String = q.pop_front()
		if a == to:
			break
		for b in D.sea_neighbors(a):
			if not prev.has(b):
				prev[b] = a
				q.append(b)
	if not prev.has(to):
		return []
	var path := []
	var cur := to
	while cur != from:
		path.push_front(cur)
		cur = prev[cur]
	return path


## Mosse per mare suggerite (una per isola raggiungibile, più il ritorno in porto). Le usa l'IA;
## la persona costruisce la sua mossa sulla mappa.
func sail_options(p: int, well_color := "") -> Array:
	var out := []
	var sh: Dictionary = players[p]["ship"]
	if sh["at"] != "P":
		out.append({"a": "sail", "ret": true})
	var caps := []
	if sh["at"] == "P":
		caps = hireable(p)
	else:
		caps = [int(sh["cap"])]
	for cap in caps:
		var spec: Dictionary = D.ADMIRAL if cap == 100 else D.CAPTAINS[cap]
		var coins_left := int(players[p]["coins"]) - (int(spec["cost"]) if sh["at"] == "P" else 0)
		for isl in D.ISLANDS:
			if isl == sh["at"]:
				continue
			var path := sea_path(sh["at"], isl)
			if path.is_empty():
				continue
			var cost := step_cost(spec, path.size(), sh["helm"])
			if _missing_well(p, cost, well_color) > coins_left:
				continue
			var mv := {"a": "sail", "cap": cap if sh["at"] == "P" else -1, "path": path, "land": true}
			if sh["at"] == "P":
				mv["load"] = auto_load(p, isl)
			out.append(mv)
		if has_card(p, "cartographer"):
			for isl in D.ISLANDS:
				if isl != sh["at"]:
					var mv2 := {"a": "sail", "cap": cap if sh["at"] == "P" else -1, "carto": isl, "land": true, "path": []}
					if sh["at"] == "P":
						mv2["load"] = auto_load(p, isl)
					out.append(mv2)
	return out


func _missing_well(p: int, list: Array, well_color: String) -> int:
	if well_color == "":
		return _missing(p, list)
	players[p]["cubes"][well_color] -= 3
	var m := _missing(p, list)
	players[p]["cubes"][well_color] += 3
	return m


## Carico sensato per andare a un'isola: le merci da vendere lì, un familiare (e un carro) per la missione.
func auto_load(p: int, isl: String) -> Array:
	var pl: Dictionary = players[p]
	var load := []
	var info: Dictionary = D.SEA[isl]
	if info.has("mission") and int(missions.get(isl, -1)) < 0 and not farm(p).is_empty():
		var hi := {}
		for m in farm(p):
			if hi.is_empty() or int(m["gen"]) > int(hi["gen"]):
				hi = m
		load.append("member:%d" % hi["id"])
		if info["mission"].has("wagon") and int(pl["goods"]["wagon"]) > 0:
			load.append("wagon")
	if info.has("sell"):
		var sells := []
		for g in info["sell"]:
			var have := int(pl["grain"]) if g == "grain" else int(pl["goods"][g])
			if have > 0:
				sells.append([int(info["sell"][g]), g])
		sells.sort_custom(func(x, y): return x[0] > y[0])
		for s in sells:
			if load.size() < 3:
				load.append(s[1])
	if info.has("stack") and load.size() >= 3:
		load.resize(2)
	return load


func hold_has(p: int, kind: String) -> bool:
	for it in players[p]["ship"]["hold"]:
		if str(it).get_slice(":", 0) == kind:
			return true
	return false


## Mossa per mare: ingaggio, carico, percorso, approdo. Il pagamento dei passi è automatico.
func _sail(p: int, a: Dictionary) -> Dictionary:
	var pl: Dictionary = players[p]
	var sh: Dictionary = pl["ship"]
	if a.get("ret", false):
		pay_time(p, 1)
		var unl := []
		for it in sh["hold"]:
			var kind := str(it).get_slice(":", 0)
			match kind:
				"member":
					members[int(str(it).get_slice(":", 1))]["loc"] = "farm"
					unl.append("un familiare")
				"grain":
					gain_grain(p, 1)
					unl.append("grano")
				"chest":
					var v := int(str(it).get_slice(":", 1))
					pl["coins"] += v
					unl.append("un forziere (%d monete)" % v)
				_:
					pl["goods"][kind] += 1
					unl.append(D.good_name(kind))
		sh["hold"] = []
		sh["at"] = "P"
		if int(sh["cap"]) == 100:
			say("%s rientra in porto (1 tempo); l'Ammiraglio scende a terra." % pname(p))
		else:
			say("%s rientra in porto (1 tempo) e congeda il capitano." % pname(p))
		sh["cap"] = -1
		sh["helm"] = false
		if not unl.is_empty():
			say("%s scarica: %s." % [pname(p), ", ".join(unl)])
		return {}
	if sh["at"] == "P":
		var cap := int(a.get("cap", -1))
		if cap == 100:
			discard_card(p, "admiral")
			sh["cap"] = 100
			say("%s prende il mare con l'Ammiraglio." % pname(p))
		elif cap >= 0:
			for d in captains:
				var i: int = d.find(cap)
				if i >= 0:
					d.remove_at(i)
					break
			pl["coins"] -= int(D.CAPTAINS[cap]["cost"])
			sh["cap"] = cap
			say("%s ingaggia un capitano per %d %s." % [pname(p), D.CAPTAINS[cap]["cost"], "moneta" if int(D.CAPTAINS[cap]["cost"]) == 1 else "monete"])
		if a.get("helm", false) and has_card(p, "helmsman"):
			discard_card(p, "helmsman")
			sh["helm"] = true
			say("%s imbarca il Timoniere." % pname(p))
		var load: Array = a.get("load", [])
		var loaded := []
		var types := {}
		var qm_used := false
		for it in load:
			if sh["hold"].size() >= 3:
				break
			var kind := str(it).get_slice(":", 0)
			if types.has(kind):
				if qm_used or not has_card(p, "quartermaster"):
					continue
				qm_used = true
				discard_card(p, "quartermaster")
			types[kind] = true
			if kind == "member":
				var m: Dictionary = members[int(str(it).get_slice(":", 1))]
				if m["loc"] != "farm":
					continue
				m["loc"] = "ship"
				loaded.append("un familiare %d" % m["gen"])
			elif kind == "grain":
				if int(pl["grain"]) < 1:
					continue
				pl["grain"] -= 1
				loaded.append("grano")
			else:
				if int(pl["goods"][kind]) < 1:
					continue
				pl["goods"][kind] -= 1
				loaded.append(D.good_name(kind))
			sh["hold"].append(str(it))
		if not loaded.is_empty():
			say("%s carica sulla nave: %s." % [pname(p), ", ".join(loaded)])
	if sh["cap"] == -1:
		return {}
	var path: Array = a.get("path", [])
	if a.get("carto", "") != "":
		discard_card(p, "cartographer")
		sh["at"] = a["carto"]
		say("%s segue la mappa del Cartografo e approda a %s." % [pname(p), D.SEA[a["carto"]]["name"]])
		return {"island": a["carto"]}
	if path.is_empty():
		return {}
	var cost := step_cost(captain_spec(p), path.size(), sh["helm"])
	var how := pay_cubes(p, cost) if not cost.is_empty() else ""
	var tlost := 0
	for node in path:
		if D.SEA[node]["kind"] == "time":
			tlost += 1
	pay_time(p, tlost)
	sh["at"] = path[-1]
	var dest: Dictionary = D.SEA[sh["at"]]
	say("%s naviga per %d %s%s%s." % [pname(p), path.size(), "tratto" if path.size() == 1 else "tratti",
		(" pagando " + how) if how != "" else "", (" e perde %s" % tt(tlost)) if tlost > 0 else ""])
	if a.get("land", false) and dest["kind"] == "island":
		say("%s approda a %s." % [pname(p), dest["name"]])
		return {"island": sh["at"]}
	return {}


## Cosa si può fare all'isola: vendite possibili, carico dalla pila, missione.
func island_options(p: int, isl: String) -> Dictionary:
	var pl: Dictionary = players[p]
	var sh: Dictionary = pl["ship"]
	var info: Dictionary = D.SEA[isl]
	var out := {"sell": [], "take": false, "take2": false, "mission": []}
	if info.has("sell"):
		for it in sh["hold"]:
			var kind := str(it).get_slice(":", 0)
			if info["sell"].has(kind):
				out["sell"].append(kind)
	if info.has("stack"):
		var left := stack_left(info["stack"])
		var kind2: String = info["stack"]
		if left > 0 and sh["hold"].size() < 3 and not hold_has(p, kind2):
			out["take"] = true
			if left > 1 and sh["hold"].size() < 2 and has_card(p, "quartermaster"):
				out["take2"] = true
	if info.has("mission") and int(missions[isl]) < 0:
		var mis: Dictionary = info["mission"]
		var wag_ok: bool = not mis.has("wagon") or hold_has(p, "wagon")
		if wag_ok and can_pay_cubes(p, mis["cubes"]):
			for it in sh["hold"]:
				if str(it).begins_with("member:"):
					out["mission"].append(int(str(it).get_slice(":", 1)))
	return out


func stack_left(kind: String) -> int:
	if kind == "chest":
		return stacks["chest"].size()
	return int(stacks.get(kind, 0))


## r = {"sell":[merci], "take":bool, "take2":bool, "mission":id o -1}
func apply_island(p: int, isl: String, r: Dictionary) -> void:
	var pl: Dictionary = players[p]
	var sh: Dictionary = pl["ship"]
	var info: Dictionary = D.SEA[isl]
	var opts := island_options(p, isl)
	var sold := []
	var tot := 0
	for kind in r.get("sell", []):
		if not (kind in opts["sell"]):
			continue
		for i in sh["hold"].size():
			if str(sh["hold"][i]).get_slice(":", 0) == kind:
				sh["hold"].remove_at(i)
				var v: int = int(info["sell"][kind])
				tot += v
				sold.append("%s (%d)" % [D.good_name(kind), v])
				break
	if tot > 0:
		gain_pp(p, tot)
		say("%s vende a %s: %s, %d punti." % [pname(p), info["name"], ", ".join(sold), tot])
	var mid := int(r.get("mission", -1))
	if mid >= 0 and int(missions.get(isl, -1)) < 0:
		var mis: Dictionary = info["mission"]
		var okm := false
		for i in sh["hold"].size():
			if str(sh["hold"][i]) == "member:%d" % mid:
				okm = true
		if okm and (not mis.has("wagon") or hold_has(p, "wagon")) and can_pay_cubes(p, mis["cubes"]):
			sh["hold"].erase("member:%d" % mid)
			if mis.has("wagon"):
				for i in sh["hold"].size():
					if str(sh["hold"][i]) == "wagon":
						sh["hold"].remove_at(i)
						break
			var how := pay_cubes(p, mis["cubes"])
			members[mid]["loc"] = "mission:" + isl
			missions[isl] = mid
			gain_pp(p, int(info["mpp"]))
			say("%s fonda la missione di %s (%s%s): %d punti." % [pname(p), info["name"], "carro, " if mis.has("wagon") else "", how, info["mpp"]])
	if r.get("take", false) and info.has("stack"):
		var kind2: String = info["stack"]
		var k := 2 if r.get("take2", false) and has_card(p, "quartermaster") else 1
		if k == 2:
			discard_card(p, "quartermaster")
		for j in k:
			if sh["hold"].size() >= 3 or stack_left(kind2) <= 0:
				break
			if j == 0 and hold_has(p, kind2):
				break
			if kind2 == "chest":
				var v2: int = stacks["chest"].pop_back()
				sh["hold"].append("chest:%d" % v2)
				say("%s carica un forziere." % pname(p))
			else:
				stacks[kind2] -= 1
				sh["hold"].append(kind2)
				say("%s carica %s." % [pname(p), D.good_name(kind2)])


# ================================================================== mercato

## Vendite possibili in un giorno di mercato. free = prima vendita gratuita di chi l'ha aperto.
## barker = l'Imbonitore permette di servire anche la coda.
func market_options(p: int, free: bool, barker: bool) -> Array:
	var pl: Dictionary = players[p]
	var out := []
	var extra_ok: bool = free or can_pay_cubes(p, ["gr"])
	if extra_ok:
		for i in front_n:
			if front[i] >= 0 and can_serve(p, front[i]):
				out.append({"k": "cust", "where": "f", "i": i})
		if barker:
			for i in 5:
				if queue[i] >= 0 and can_serve(p, queue[i]):
					out.append({"k": "cust", "where": "q", "i": i})
		if port:
			if int(pl["goods"]["cocoa"]) > 0:
				out.append({"k": "cocoa"})
			if int(pl["goods"]["tea"]) > 0:
				out.append({"k": "tea"})
	out.append({"k": "pass"})
	return out


func can_serve(p: int, ci: int) -> bool:
	var pl: Dictionary = players[p]
	var need: Dictionary = D.CUSTOMERS[ci]["need"]
	for g in need:
		var have := int(pl["grain"]) if g == "grain" else int(pl["goods"][g])
		if have < int(need[g]):
			return false
	return true


func apply_sale(p: int, sale: Dictionary, free: bool) -> void:
	var pl: Dictionary = players[p]
	if sale["k"] == "pass":
		say("%s passa." % pname(p))
		return
	var extra := ""
	if not free:
		extra = " (paga %s e 1 tempo)" % pay_cubes(p, ["gr"])
		pay_time(p, 1)
	match str(sale["k"]):
		"cust":
			var arr: Array = front if sale["where"] == "f" else queue
			var ci: int = arr[int(sale["i"])]
			var need: Dictionary = D.CUSTOMERS[ci]["need"]
			var parts := []
			for g in need:
				if g == "grain":
					pl["grain"] -= int(need[g])
				else:
					pl["goods"][g] -= int(need[g])
				parts.append("%d %s" % [need[g], D.good_name(g, int(need[g]))])
			arr[int(sale["i"])] = -1
			pl["customers"].append(ci)
			say("%s serve un cliente con %s%s." % [pname(p), ", ".join(parts), extra])
		"cocoa":
			pl["goods"]["cocoa"] -= 1
			gain_pp(p, D.COCOA_PP)
			say("%s vende un cesto di cacao: %d punti%s." % [pname(p), D.COCOA_PP, extra])
		"tea":
			pl["goods"]["tea"] -= 1
			gain_pp(p, D.TEA_PP)
			pl["coins"] += 1
			say("%s vende una balla di tè: %d punti e 1 moneta%s." % [pname(p), D.TEA_PP, extra])


func any_customer_left(barker := false) -> bool:
	for i in front_n:
		if front[i] >= 0:
			return true
	if barker:
		for i in 5:
			if queue[i] >= 0:
				return true
	return false


## Fine del giorno di mercato: i clienti in coda avanzano, la coda si riempie dalla pila.
func refill_market() -> void:
	var waiting := []
	for i in 5:
		if queue[i] >= 0:
			waiting.append(queue[i])
	for i in front_n:
		if front[i] < 0 and not waiting.is_empty():
			front[i] = waiting.pop_front()
	for i in 5:
		if waiting.is_empty() and not pile.is_empty():
			waiting.append(pile.pop_back())
		queue[i] = waiting.pop_front() if not waiting.is_empty() else -1


func scrap_options() -> Array:
	var out := []
	for i in front_n:
		if front[i] >= 0:
			out.append(i)
	return out


func take_customer_free(p: int, i: int) -> void:
	var ci: int = front[i]
	if ci < 0:
		return
	front[i] = -1
	players[p]["customers"].append(ci)
	discard_card(p, "scrap")
	say("%s prende gratis un cliente grazie al Rigattiere." % pname(p))


# ================================================================== messa

func bag_members() -> Array:
	var out := []
	for m in members:
		if m["loc"] == "bag":
			out.append(m)
	return out


func church_members(p := -1) -> Array:
	var out := []
	for m in members:
		if str(m["loc"]).begins_with("church:") and (p < 0 or m["owner"] == p):
			out.append(m)
	return out


func put_in_church(m: Dictionary) -> void:
	m["loc"] = "church:0"


## Estrazione casuale dal sacchetto nero (familiari e frati) fino ad arrivare a k personaggi.
func draw_mass(k: int) -> Array:
	var pieces := []
	for m in bag_members():
		pieces.append(m["id"])
	for i in D.MONKS:
		pieces.append(-1)
	var drawn := []
	for i in k:
		if pieces.is_empty():
			break
		var j := rng.randi() % pieces.size()
		drawn.append(pieces[j])
		pieces.remove_at(j)
	return drawn


## Costo in grano per portare un familiare dalla vetrata a alla vetrata b (b > a).
static func climb_cost(a: int, b: int) -> int:
	var c := 0
	for w in range(a, b):
		c += D.WINDOW_COST[w]
	return c


## moves = {id: vetrata di arrivo}. Restituisce false se non si può pagare.
func apply_climb(p: int, moves: Dictionary) -> bool:
	var tot := 0
	for id in moves:
		var m: Dictionary = members[int(id)]
		if m["owner"] != p or not str(m["loc"]).begins_with("church:"):
			return false
		var a := int(str(m["loc"]).substr(7))
		var b := int(moves[id])
		if b <= a or b > 3:
			return false
		tot += climb_cost(a, b)
	if tot > int(players[p]["grain"]):
		return false
	players[p]["grain"] -= tot
	for id in moves:
		members[int(id)]["loc"] = "church:%d" % int(moves[id])
	if tot > 0:
		say("%s paga %d grano e fa salire %d %s verso l'altare." % [pname(p), tot, moves.size(), "familiare" if moves.size() == 1 else "familiari"])
	return true


## Maggioranza in chiesa: 2 punti (a parità vince chi è più a sinistra; se resta pari, a tutti).
func church_majority() -> Array:
	var cnt := []
	var best_w := []
	for s in n:
		cnt.append(0)
		best_w.append(-1)
	for m in church_members():
		var s: int = m["owner"]
		cnt[s] += 1
		best_w[s] = maxi(best_w[s], int(str(m["loc"]).substr(7)))
	var top := 0
	for s in n:
		top = maxi(top, cnt[s])
	if top == 0:
		return []
	var tied := []
	for s in n:
		if cnt[s] == top:
			tied.append(s)
	if tied.size() > 1:
		var bw := -1
		for s in tied:
			bw = maxi(bw, best_w[s])
		var t2 := []
		for s in tied:
			if best_w[s] == bw:
				t2.append(s)
		tied = t2
	for s in tied:
		gain_pp(s, 2)
	return tied


# ================================================================== morte e cronache

## Chi può morire adesso: i familiari visibili con il numero più basso (uno per luogo e generazione).
func death_options(p: int) -> Array:
	var vis := []
	var lo := 99
	for m in members:
		if m["owner"] == p and is_visible_alive(m):
			vis.append(m)
			lo = mini(lo, int(m["gen"]))
	var out := []
	var seen := {}
	for m in vis:
		if int(m["gen"]) == lo:
			var key := str(m["loc"])
			if not seen.has(key):
				seen[key] = true
				out.append(m["id"])
	return out


func section_of(loc: String) -> String:
	if loc == "farm":
		return "farm"
	if loc.begins_with("craft:"):
		return "crafts"
	if loc.begins_with("council:"):
		return "council"
	if loc.begins_with("city:") or loc == "ship" or loc.begins_with("mission:"):
		return "travel"
	if loc.begins_with("church:"):
		return "church"
	return ""


func chron_free() -> int:
	var k := 0
	for sec in chron:
		for v in chron[sec]:
			if int(v) == -1:
				k += 1
	return k


func graves_free() -> int:
	var k := 0
	for v in graves:
		if int(v) == -1:
			k += 1
	return k


## Muore il familiare mid. bard = il Bardo lo mette comunque nelle cronache (in più).
## Restituisce true se ha occupato l'ultimo spazio (cronache, tombe o sepolture in mare): fine partita.
func apply_death(p: int, mid: int, bard := false) -> bool:
	var m: Dictionary = members[mid]
	var loc: String = m["loc"]
	var at_sea: bool = loc == "ship" or loc.begins_with("mission:")
	if loc == "ship":
		players[p]["ship"]["hold"].erase("member:%d" % mid)
	if loc.begins_with("mission:"):
		missions[loc.substr(8)] = -1
	players[p]["deaths"] = maxi(0, int(players[p]["deaths"]) - 1)
	var who := "%s: muore il familiare %d (%s)" % [pname(p), m["gen"], loc_name(loc)]
	if bard:
		discard_card(p, "bard")
		m["loc"] = "bard"
		players[p]["bard"] += 1
		say(who + ", il Bardo ne canta le gesta nelle cronache.")
		return false
	var sec := section_of(loc)
	if sec != "":
		var arr: Array = chron[sec]
		for i in arr.size():
			if int(arr[i]) == -1:
				arr[i] = p
				m["loc"] = "chron:%s:%d" % [sec, i]
				say(who + ": entra nelle cronache del villaggio (%s)." % D.SECTION[sec]["name"])
				return chron_free() == 0 and end_by < 0
	if at_sea and port:
		for i in burials.size():
			if int(burials[i]) == -1:
				burials[i] = p
				m["loc"] = "sea:%d" % i
				gain_pp(p, D.BURIAL_PTS[i])
				say(who + ": sepolto in mare%s." % ((" (%d punti)" % D.BURIAL_PTS[i]) if D.BURIAL_PTS[i] > 0 else ""))
				var full := true
				for v in burials:
					if int(v) == -1:
						full = false
				return full and end_by < 0
	for i in graves.size():
		if int(graves[i]) == -1:
			graves[i] = p
			m["loc"] = "grave:%d" % i
			say(who + ": riposa in una tomba anonima.")
			return graves_free() == 0 and end_by < 0
	m["loc"] = "gone"
	say(who + ": non c'è più posto, esce dal gioco.")
	return false


func chron_count(p: int) -> int:
	var k := int(players[p]["bard"])
	for sec in chron:
		for v in chron[sec]:
			if int(v) == p:
				k += 1
	return k


func chron_sections(p: int) -> int:
	var k := 0
	for sec in chron:
		if p in chron[sec]:
			k += 1
	return k


# ================================================================== obiettivi di vita

func goal_def(g: Array) -> Dictionary:
	return D.GOALS_SILVER[int(g[1])] if g[0] == "s" else D.GOALS_GOLD[int(g[1])]


func goal_met(p: int, g: Array) -> bool:
	var pl: Dictionary = players[p]
	var gd := goal_def(g)
	if g[0] == "s":
		if gd["key"] == "explorer":
			return hold_has(p, "horse") and hold_has(p, "member") and hold_has(p, "chest")
		for k in gd["need"]:
			var need: int = int(gd["need"][k])
			var have := 0
			match k:
				"coin": have = int(pl["coins"])
				"grain": have = int(pl["grain"])
				"next": have = 1 if next_owner == p else 0
				"pk", "br", "gr", "or": have = count_cube(p, k)
				_: have = int(pl["goods"][k])
			if have < need:
				return false
		return true
	match str(gd["key"]):
		"salesman":
			return m_of(p, "city:C").size() > 0 and pl["customers"].size() >= 2
		"master":
			var k2 := m_prefix(p, "craft:").size()
			for v in chron["crafts"]:
				if int(v) == p:
					k2 += 1
			return k2 >= 4
		"innkeeper":
			return pl["hand"].size() >= 4
		"secretary":
			return m_of(p, "council:4").size() > 0 and next_owner == p
		"acolyte":
			for m in church_members(p):
				if int(m["gen"]) == 4:
					return true
			return false
		"merchant":
			return pl["customers"].size() >= 6
		"saint":
			var w := [false, false, false]
			for m in church_members(p):
				var wi := int(str(m["loc"]).substr(7))
				if wi < 3:
					w[wi] = true
			return w[0] and w[1] and w[2]
		"missionary":
			var k3 := 0
			for isl in missions:
				if int(missions[isl]) >= 0 and members[int(missions[isl])]["owner"] == p:
					k3 += 1
			return k3 >= 2
		"historian":
			return chron_sections(p) >= 4
	return false


## Rivela e incassa gli obiettivi raggiunti (succede da sé: non c'è motivo di aspettare).
func check_goals() -> void:
	if not goals_on:
		return
	for p in n:
		var pl: Dictionary = players[p]
		var keep := []
		for g in pl["goals"]:
			if goal_met(p, g):
				var pts := D.SILVER_PP if g[0] == "s" else D.GOLD_PP
				gain_pp(p, pts)
				pl["goals_done"].append(g)
				say("%s realizza l'obiettivo di vita «%s»: %d punti!" % [pname(p), goal_def(g)["name"], pts])
			else:
				keep.append(g)
		pl["goals"] = keep


# ================================================================== punteggio

func score_breakdown(p: int) -> Dictionary:
	var pl: Dictionary = players[p]
	var r := {"track": int(pl["pp"])}
	var cities: int = pl["cities"].size()
	var trav := 0
	if not port:
		trav = D.TRAVELLER_PTS[mini(6, cities)] if has_card(p, "traveller") else D.TRAVEL_PTS[mini(6, cities)]
		if has_card(p, "count"):
			for c in ["B", "C", "E"]:
				if c in pl["cities"]:
					trav += 2
	r["travel"] = trav
	var co := 0
	for m in m_prefix(p, "council:"):
		co += D.COUNCIL_PTS[int(str(m["loc"]).substr(8)) - 1]
	r["council"] = co
	var chp := 0
	for m in church_members(p):
		chp += D.WINDOW_PTS[int(str(m["loc"]).substr(7))]
	r["church"] = chp
	var cc := chron_count(p)
	r["chron"] = D.ARTIST_PTS[mini(6, cc)] if has_card(p, "artist") else D.CHRON_PTS[mini(5, cc)]
	var cu := 0
	for ci in pl["customers"]:
		cu += int(D.CUSTOMERS[ci]["pp"])
	r["customers"] = cu
	r["coins"] = int(pl["coins"])
	var cards := 0
	for cid in pl["hand"]:
		match str(D.VILLAGERS[cid]["key"]):
			"mayor": cards += _cube_card(count_cube(p, "gr"))
			"nun": cards += _cube_card(count_cube(p, "br"))
			"guild": cards += _cube_card(count_cube(p, "or"))
			"scholar": cards += _cube_card(count_cube(p, "pk"))
			"medico":
				for m in members:
					if m["owner"] == p and is_living(m):
						cards += 1
			"peasant": cards += int(pl["grain"])
			"manciple":
				for g in D.GOODS:
					if int(pl["goods"][g]) > 0:
						cards += 2
	r["cards"] = cards
	var tot := 0
	for k in r:
		tot += int(r[k])
	r["total"] = tot
	return r


static func _cube_card(k: int) -> int:
	return 2 * k if k <= 3 else 0


## Risultati finali ordinati (con la Borsaiola valutata per ultima e gli spareggi del regolamento).
func final_results() -> Array:
	var res := []
	for p in n:
		var b := score_breakdown(p)
		b["seat"] = p
		res.append(b)
	var lowest := 9999
	for b in res:
		lowest = mini(lowest, int(b["total"]))
	for b in res:
		var p: int = b["seat"]
		b["cutpurse"] = 0
		if has_card(p, "cutpurse"):
			b["cutpurse"] = 6 if int(b["total"]) <= lowest else 3
			b["total"] += b["cutpurse"]
		b["custn"] = players[p]["customers"].size()
		var alive := 0
		for m in members:
			if m["owner"] == p and is_living(m):
				alive += 1
		b["alive"] = alive
	res.sort_custom(func(a, b):
		if a["total"] != b["total"]:
			return a["total"] > b["total"]
		if a["custn"] != b["custn"]:
			return a["custn"] > b["custn"]
		return a["alive"] > b["alive"])
	return res


## Impronta della partita (per confrontare le partite online fra dispositivi).
func fingerprint() -> String:
	var parts := [str(round_no)]
	for p in players:
		parts.append("%d/%d/%d/%d" % [p["pp"], p["time"], p["coins"], p["grain"]])
	return "|".join(parts)


# ================================================================== carte "quando vuoi"

## Gioca una carta abitante "quando vuoi". Restituisce le scelte che restano al motore:
## {"good":[opzioni]} · {"family":true} · {"herb":true} · {"priv2":lv} · {"noble":true} · {"city":true} · {"abbot":true}
func play_card(p: int, cid: int) -> Dictionary:
	var pl: Dictionary = players[p]
	var v: Dictionary = D.VILLAGERS[cid]
	var key: String = v["key"]
	pl["hand"].erase(cid)
	say("%s gioca %s." % [pname(p), v["name"]])
	match key:
		"scribe":
			gain_good(p, "scroll", 2)
		"wagonmaker":
			gain_good(p, "wagon", 1)
		"blacksmith":
			gain_good(p, "plow", 2)
		"cattle":
			return {"good": ["horse", "ox"]}
		"lostson":
			gain_pp(p, 3)
			return {"family": true}
		"herb":
			gain_pp(p, 2)
			return {"herb": true}
		"farmhand":
			gain_pp(p, 2)
			pl["grain"] = D.GRAIN_MAX
		"councilman":
			return {"priv2": max_council(p)}
		"noble":
			gain_pp(p, 2)
			return {"noble": true}
		"messenger":
			return {"city": true}
		"abbot":
			return {"abbot": true}
	return {}


func herb_move(p: int, where: String) -> void:
	if where == "before":
		players[p]["time"] = D.TIME_STEPS - 1
		say("%s sposta il segnatempo subito prima del ponte." % pname(p))
	elif where == "after":
		players[p]["time"] = 0
		say("%s riporta il segnatempo subito dopo il ponte." % pname(p))


func messenger_cities(p: int) -> Array:
	var out := []
	for c in D.CITIES:
		if not (c in players[p]["cities"]):
			out.append(c)
	return out


func abbot_move(p: int, mid: int) -> void:
	var m: Dictionary = members[mid]
	if m["owner"] == p and str(m["loc"]).begins_with("church:"):
		m["loc"] = "church:3"
		say("%s: l'Abate porta il familiare %d alla vetrata più a sinistra." % [pname(p), m["gen"]])


func noble_take(p: int, d: int, cid: int) -> void:
	if d < 0 or d >= decks.size():
		return
	var i: int = decks[d].find(cid)
	if i < 0:
		return
	decks[d].remove_at(i)
	players[p]["hand"].append(cid)
	say("%s prende %s dal mazzo %d." % [pname(p), D.VILLAGERS[cid]["name"], d + 1])
