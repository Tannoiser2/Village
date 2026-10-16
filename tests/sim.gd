extends SceneTree
## Partite IA contro IA senza grafica, per provare le regole e tarare l'IA.
## godot --headless --path . -s res://tests/sim.gd -- <partite> <giocatori> [espansioni: inn,port,goals o -] [livelli es. 2,1,1,0,0] [log]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var games := int(args[0]) if args.size() > 0 else 10
	var np := int(args[1]) if args.size() > 1 else 4
	var o := {}
	if args.size() > 2 and args[2] != "-":
		for k in args[2].split(","):
			o[k] = true
	var levels := [1, 1, 1, 1, 1]
	if args.size() > 3:
		var parts: PackedStringArray = args[3].split(",")
		for i in parts.size():
			levels[i] = int(parts[i])
	var show_log := args.size() > 4 and args[4] == "log"
	var over := {}
	if args.size() > 5:
		over = JSON.parse_string(args[5])
	var wins := [0, 0, 0, 0, 0]
	var psum := [0, 0, 0, 0, 0]
	var rounds := 0
	var t0 := Time.get_ticks_msec()
	for g in games:
		var e := VLEngine.new()
		e.headless = true
		root.add_child(e)
		var seats := []
		for i in np:
			seats.append({"color": i, "ai": true, "name": "IA%d" % i, "level": levels[i]})
		e.setup({"seats": seats, "seed": int(OS.get_environment("VL_SEED")) + g if OS.get_environment("VL_SEED") != "" else 1000 + g, "opts": o})
		if not over.is_empty():
			# il posto 0 gioca con i pesi modificati (ruota il posto per non favorire nessuno)
			e.ais[g % np].W.merge(over, true)
			e.st.players[g % np]["name"] = "VAR"
		await e.run()
		var shift := (g % np) if not over.is_empty() else 0
		wins[(e.results[0]["seat"] - shift + np) % np] += 1
		for r in e.results:
			psum[(r["seat"] - shift + np) % np] += r["total"]
		rounds += e.st.round_no
		if g == 0 and show_log:
			for l in e.log_lines:
				print(l)
		var line := []
		for r in e.results:
			line.append("%s=%d(%s)" % [e.pname(r["seat"]), r["total"], ",".join(["track", "travel", "council", "church", "chron", "customers", "coins", "cards"].map(func(k): return str(r[k])))])
		if show_log or games <= 12:
			print("partita %d: round %d  %s" % [g, e.st.round_no, "  ".join(line)])
		e.queue_free()
	print("vittorie per posto: ", wins.slice(0, np), "  punti medi: ", psum.slice(0, np).map(func(x): return x / games))
	print("round medi: %.1f   tempo %d ms" % [float(rounds) / games, Time.get_ticks_msec() - t0])
	quit()
