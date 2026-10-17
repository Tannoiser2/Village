extends SceneTree
## Screenshot del viaggio per mare passo per passo (serve xvfb-run).
## godot --path . -s res://tests/sail_shot.gd -- [seme]

var main
var n := 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir() + "/shots")
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func shot(name: String) -> void:
	for i in 4:
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	n += 1
	img.save_png(OS.get_user_data_dir() + "/shots/s%02d_%s.png" % [n, name])
	print("shot ", name)


func wait(f := 10) -> void:
	for i in range(f):
		await process_frame


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var seed := int(args[0]) if args.size() > 0 else 3
	var seats := []
	for i in 2:
		seats.append({"color": i, "ai": i != 0, "name": ["Stefano", "Giallo"][i], "level": 1})
	main.start_game({"seats": seats, "seed": seed, "opts": {"port": true}, "ai_delay": 0.0, "hints": true})
	await wait(20)
	var found := false
	for guard in 3000:
		await wait(2)
		var g = main.current
		if not g.modal.get_children().is_empty():
			g._clear_modal()
			g.engine.provide_decision(null)
			continue
		if g.pending.is_empty():
			continue
		if g.pending["type"] == "turn":
			for m in g.pending["moves"]:
				if m["src"]["t"] == "space" and m["src"]["sp"] == "travel":
					g._pick_src(m["src"])
					found = true
					break
		if found:
			break
		var r = g.engine.ais[int(g.pending["seat"])].decide(g.engine, int(g.pending["seat"]), g.pending)
		g._provide(r)
	if not found:
		print("nessun turno con il viaggio")
		quit()
		return
	var gv = main.current
	await wait(10)
	await shot("viaggio")
	gv.wiz["step"] = "sail"
	gv.sel = {}
	gv._show_decision()
	await wait(10)
	await shot("capitano")
	var caps: Array = gv.st.hireable(int(gv.pending["seat"]))
	if not caps.is_empty():
		gv.sel["cap"] = caps[0]
		gv._show_decision()
		await wait(10)
		await shot("carico")
		gv.sel["loaded"] = true
		gv._show_decision()
		await wait(10)
		await shot("rotta")
		var keys: Array = gv.board.targets.keys()
		if not keys.is_empty():
			gv._on_target(keys[0])
			await wait(10)
			await shot("rotta2")
			var keys2: Array = gv.board.targets.keys()
			if not keys2.is_empty():
				gv._on_target(keys2[0])
				await wait(10)
				await shot("rotta3")
	quit()
