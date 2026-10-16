class_name Describe
extends RefCounted
## Testi in italiano per mosse, costi e luoghi (pulsanti, suggerimenti, riepiloghi).

const D = preload("res://scripts/data/vl_data.gd")


static func tempi(k: int) -> String:
	return "%d %s" % [k, "tempo" if k == 1 else "tempi"]


static func cubes_text(list: Array) -> String:
	var cnt := {}
	for c in list:
		cnt[c] = int(cnt.get(c, 0)) + 1
	var parts := []
	for c in cnt:
		var nm: String = "cubo a scelta" if c == "any" else D.cube_name(c)
		if c == "any" and cnt[c] > 1:
			nm = "cubi a scelta"
		elif cnt[c] > 1:
			nm = {"pk": "rosa", "br": "marroni", "gr": "verdi", "or": "arancioni"}.get(c, nm)
		parts.append("%d %s" % [cnt[c], nm])
	return " + ".join(parts)


static func member(st: VLState, id: int) -> String:
	var m: Dictionary = st.members[id]
	return "familiare %d" % m["gen"]


static func src_text(src: Dictionary) -> String:
	match str(src["t"]):
		"space":
			return "%s (%s)" % [D.SPACE[src["sp"]]["name"], "cubo peste" if src["c"] == "pl" else "cubo " + D.cube_name(src["c"])]
		"well":
			return "Pozzo (3 cubi %s)" % D.cube_name(src["c"])
		"oldman":
			return "Vecchio saggio"
		"free":
			return "Azione finale gratuita"
	return ""


## Descrizione di un'azione (senza la scelta del cubo).
static func action(st: VLState, p: int, a: Dictionary) -> String:
	match str(a.get("a", "none")):
		"none":
			return "Solo il cubo, nessuna azione"
		"harvest":
			var pl: Dictionary = st.players[p]
			var k := 2
			if int(pl["goods"]["plow"]) > 0 and int(pl["goods"]["ox"]) > 0:
				k = 4
			elif int(pl["goods"]["plow"]) > 0 and int(pl["goods"]["horse"]) > 0:
				k = 3
			k = mini(k, D.GRAIN_MAX - int(pl["grain"]))
			return "Mietitura: +%d grano" % k
		"family":
			if int(a["m"]) < 0:
				var nb := st.next_unborn(p)
				return "Famiglia: nasce un familiare %d" % (int(nb["gen"]) if not nb.is_empty() else 0)
			var m: Dictionary = st.members[int(a["m"])]
			return "Famiglia: riporta a casa il familiare %d (%s)" % [m["gen"], st.loc_name(m["loc"])]
		"craft":
			var b: String = a["b"]
			if b == "mill":
				return "Mulino: 2 grano e %s » %d monete%s" % [tempi(2), 5 if a.get("miller", false) else 2, " (Mugnaio)" if a.get("miller", false) else ""]
			var cr: Dictionary = D.CRAFT[b]
			var g: String = a.get("g", cr.get("good", ""))
			var qty: int = int(cr.get("qty", 1))
			var gn := "%d %s" % [qty, D.good_name(g, qty)]
			match str(a["how"]):
				"make":
					return "%s: produci %s (%s)" % [cr["name"], gn, tempi(cr["make"])]
				"trainmake":
					return "%s: addestra il familiare %d e produci %s (%s)" % [cr["name"], st.members[int(a["m"])]["gen"], gn, tempi(int(cr["train"]) + int(cr["make"]))]
				"train":
					return "%s: addestra solo il familiare %d (%s)" % [cr["name"], st.members[int(a["m"])]["gen"], tempi(cr["train"])]
				"buy":
					var cost := "%d grano" % int(cr["grain"]) if cr.has("grain") else cubes_text(cr["buy"])
					return "%s: compra %s con %s" % [cr["name"], gn, cost]
		"market":
			return "Mercato: apri un giorno di mercato (la tua prima vendita è gratis)"
		"travel":
			var m2: Dictionary = st.members[int(a["m"])]
			var from: String = "la fattoria" if m2["loc"] == "farm" else D.CITY[str(m2["loc"]).substr(5)]["name"]
			var fk := "G" if m2["loc"] == "farm" else str(m2["loc"]).substr(5)
			var cost2 := "gratis (Gabelliere)" if a.get("toll", false) else "%s, 1 carro, %s" % [tempi(2), cubes_text(D.road(fk, a["to"]))]
			var rw := ""
			if not (a["to"] in st.players[p]["cities"]):
				match str(D.CITY[a["to"]]["reward"]):
					"pp3": rw = " » 3 punti"
					"coin": rw = " » 1 moneta"
					"cubes2": rw = " » 2 cubi a scelta"
			return "Viaggio: familiare %d da %s a %s (%s)%s" % [m2["gen"], from, D.CITY[a["to"]]["name"], cost2, rw]
		"council":
			match str(a["how"]):
				"priv":
					return "Consiglio: usa solo un privilegio (fino al livello %d)" % st.max_council(p)
				"enter":
					return "Consiglio: porta il familiare %d al livello 1 (%s, %s)" % [st.members[int(a["m"])]["gen"], "1 pergamena" if a["pay"] == "scroll" else "2 verdi", tempi(1)]
				"up":
					var m3: Dictionary = st.members[int(a["m"])]
					var lv := int(str(m3["loc"]).substr(8)) + 1
					return "Consiglio: promuovi il familiare %d al livello %d (%s, %s)" % [m3["gen"], lv, "1 pergamena" if a["pay"] == "scroll" else "2 verdi", tempi(D.COUNCIL_TIME[lv - 1])]
		"church":
			return "Chiesa: il familiare %d nel sacchetto nero (%s)" % [st.members[int(a["m"])]["gen"], "1 marrone" if a["pay"] == "brown" else tempi(3)]
		"inn":
			var t := "Locanda: "
			if int(a["m"]) >= 0:
				t += "manda il familiare %d (%s), poi " % [st.members[int(a["m"])]["gen"], tempi(1)]
			var d: int = int(a["rot"])
			var top := "—"
			if st.decks[d].size() > 0:
				top = D.VILLAGERS[st.decks[d][-1]]["name"]
			return t + "%s e manda in fondo al mazzo %d %s" % [tempi(1), d + 1, top]
		"sail":
			return sail_text(st, p, a)
	return str(a)


static func sail_text(st: VLState, p: int, a: Dictionary) -> String:
	if a.get("ret", false):
		return "Porto: rientra e scarica la nave (%s)" % tempi(1)
	var parts := []
	var cap := int(a.get("cap", -1))
	if cap == 100:
		parts.append("con l'Ammiraglio")
	elif cap >= 0:
		parts.append("capitano da %d" % int(D.CAPTAINS[cap]["cost"]))
	if a.get("carto", "") != "":
		return "Mare: il Cartografo ti porta a %s%s" % [D.SEA[a["carto"]]["name"], (" (" + ", ".join(parts) + ")") if not parts.is_empty() else ""]
	var path: Array = a.get("path", [])
	if path.is_empty():
		return "Mare"
	var tt := 0
	for nd in path:
		if D.SEA[nd]["kind"] == "time":
			tt += 1
	var spec: Dictionary = (D.ADMIRAL if cap == 100 else D.CAPTAINS[cap]) if cap >= 0 else st.captain_spec(p)
	var cost := st.step_cost(spec, path.size(), bool(st.players[p]["ship"]["helm"]) or a.get("helm", false))
	var dest: String = path[-1]
	var where: String = D.SEA[dest].get("name", "acque del tempo")
	var t := "Mare: verso %s, %d %s" % [where, path.size(), "tratto" if path.size() == 1 else "tratti"]
	if tt > 0:
		t += ", " + tempi(tt)
	if not cost.is_empty():
		t += ", " + cubes_text(cost)
	if a.has("load") and not a["load"].is_empty():
		var ld := []
		for it in a["load"]:
			var kind := str(it).get_slice(":", 0)
			ld.append("familiare" if kind == "member" else ("grano" if kind == "grain" else D.good_name(kind)))
		t += " · carica " + ", ".join(ld)
	if not parts.is_empty():
		t += " (" + ", ".join(parts) + ")"
	return t


static func need_text(need: Dictionary) -> String:
	var parts := []
	for g in need:
		parts.append("%d %s" % [need[g], D.good_name(g, int(need[g]))])
	return ", ".join(parts)


static func goal_text(g: Array) -> String:
	var gd: Dictionary = (D.GOALS_SILVER if g[0] == "s" else D.GOALS_GOLD)[int(g[1])]
	if gd.has("text"):
		return "%s (%d punti): %s" % [gd["name"], D.SILVER_PP if g[0] == "s" else D.GOLD_PP, gd["text"]]
	var parts := []
	for k in gd["need"]:
		var n: int = int(gd["need"][k])
		match k:
			"coin": parts.append("%d monete" % n)
			"next": parts.append("il segnalino del prossimo primo giocatore")
			"grain": parts.append("%d grano" % n)
			"pk", "br", "gr", "or": parts.append("%d cubo %s" % [n, D.cube_name(k)])
			_: parts.append("%d %s" % [n, D.good_name(k, n)])
	return "%s (%d punti): possiedi %s." % [gd["name"], D.SILVER_PP, ", ".join(parts)]
