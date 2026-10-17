extends SceneTree
## Partita completa attraverso la vista di gioco (senza grafica): la persona al posto 0 è simulata
## dall'IA, ma ogni decisione costruisce davvero il suo pannello. Serve a scovare errori dell'interfaccia.
## godot --headless --path . -s res://tests/ui_play.gd -- <giocatori> <espansioni o -> <seme>

var main
var types := {}
var checks := 0

func _initialize() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var np := int(args[0]) if args.size() > 0 else 4
	var o := {}
	if args.size() > 1 and args[1] != "-":
		for k in args[1].split(","):
			o[k] = true
	var seed := int(args[2]) if args.size() > 2 else 5
	var seats := []
	for i in np:
		seats.append({"color": i, "ai": i != 0, "name": ["Stefano", "Giallo", "Blu", "Bianco", "Grigio"][i], "level": 1})
	main.start_game({"seats": seats, "seed": seed, "opts": o, "ai_delay": 0.0, "hints": true})
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 600000:
		await process_frame
		var g = main.current
		if g.engine.game_over:
			break
		if not g.modal.get_children().is_empty():
			g._clear_modal()
			g.engine.provide_decision(null)
			continue
		if not g.pending.is_empty():
			var req: Dictionary = g.pending
			types[req["type"]] = int(types.get(req["type"], 0)) + 1
			# ogni tanto prova anche il passo successivo della scelta del turno
			if req["type"] == "turn" and not req["moves"].is_empty():
				var m: Dictionary = req["moves"][0]
				# il cubo si prende cliccandolo sulla mappa
				if m["src"]["t"] == "space":
					var key := "cube:%s:%s" % [m["src"]["sp"], m["src"]["c"]]
					if not g.target_map.has(key) or not g.board.targets.has(key):
						print("UITEST ERRORE: manca il bersaglio ", key)
					else:
						g._on_target(key)
				else:
					g._pick_src(m["src"])
				if g.wiz.get("step", "") == "space":
					g.wiz["space"] = g._space_of(m["a"])
					g.wiz["step"] = "act"
					g._show_decision()
			# pannello Artigiani: ogni mossa di bottega deve essere raggiungibile con gli interruttori
			if req["type"] == "turn":
				for m in req["moves"]:
					var a0: Dictionary = m["a"]
					if a0.get("a", "") != "craft":
						continue
					var avail := {}
					for k in req["moves"].size():
						var mm: Dictionary = req["moves"][k]
						if mm["src"] == m["src"] and mm["a"].get("a", "") == "craft":
							if not avail.has(mm["a"]["b"]):
								avail[mm["a"]["b"]] = []
							avail[mm["a"]["b"]].append({"i": k, "a": mm["a"]})
					g._craft_pick(a0["b"], avail, a0)
					var got: Dictionary = g._craft_match(a0["b"], avail[a0["b"]])
					checks += 1
					if got.is_empty() or var_to_str(got["a"]) != var_to_str(a0):
						print("UITEST ERRORE artigiani: ", a0, " -> ", got)
				g.sel = {}
			var r = g.engine.ais[int(req["seat"])].decide(g.engine, int(req["seat"]), req)
			g._provide(r)
	var g2 = main.current
	print("UITEST controlli artigiani: ", checks)
	print("UITEST fine: ", g2.engine.game_over, " round ", g2.st.round_no, " decisioni ", types)
	for r in g2.engine.results:
		print("  ", g2.engine.pname(r["seat"]), " ", r["total"])
	quit()
