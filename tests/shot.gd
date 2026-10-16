extends SceneTree
## Screenshot automatici dell'interfaccia (serve un display: xvfb-run).
## godot --path . -s res://tests/shot.gd -- <modo: menu|rules|game> [giocatori] [espansioni inn,port,goals o -] [decisioni prima della foto]

var main
var n := 0

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir() + "/shots")
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func shot(name: String) -> void:
	await process_frame
	await process_frame
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	n += 1
	img.save_png(OS.get_user_data_dir() + "/shots/%02d_%s.png" % [n, name])
	print("shot ", name)


func wait(f := 10) -> void:
	for i in range(f):
		await process_frame


func gv():
	return main.current


## Risponde a una decisione con l'IA (come farebbe un giocatore).
func auto_answer() -> void:
	var g = gv()
	var req: Dictionary = g.pending
	if req.is_empty():
		return
	var r = g.engine.ais[int(req["seat"])].decide(g.engine, int(req["seat"]), req)
	g._provide(r)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var mode: String = args[0] if args.size() > 0 else "game"
	await wait(5)
	await shot("menu")
	if mode == "menu":
		quit()
		return
	if mode == "rules":
		main.show_rules()
		await wait(5)
		await shot("rules")
		for i in 3:
			main.current.tabs[i + 1].emit_signal("pressed")
			await wait(3)
			await shot("rules%d" % (i + 1))
		quit()
		return
	var np := int(args[1]) if args.size() > 1 else 4
	var o := {}
	if args.size() > 2 and args[2] != "-":
		for k in args[2].split(","):
			o[k] = true
	var decisions := int(args[3]) if args.size() > 3 else 12
	var seats := []
	for i in np:
		seats.append({"color": i, "ai": i != 0, "name": ["Stefano", "Giallo", "Blu", "Bianco", "Grigio"][i], "level": 1})
	main.start_game({"seats": seats, "seed": 77, "opts": o, "ai_delay": 0.0, "hints": true})
	await wait(30)
	await shot("start")
	var done := 0
	var guard := 0
	while done < decisions and guard < 4000:
		guard += 1
		await wait(2)
		var g = gv()
		if not g.modal.get_children().is_empty():
			# pausa (fine messa): avanti
			g._clear_modal()
			g.engine.provide_decision(null)
			continue
		if not g.pending.is_empty():
			if done == decisions - 1:
				break
			auto_answer()
			done += 1
	await wait(20)
	await shot("decision")
	var gg = gv()
	if gg.pending.get("type", "") == "turn":
		for m in gg.pending["moves"]:
			if m["src"]["t"] == "space" and m["src"]["sp"] == "crafts":
				gg._pick_src(m["src"])
				break
		await wait(10)
		await shot("actions")
		gg.wiz = {}
		gg._show_decision()
	var g2 = gv()
	g2._toggle_flat()
	await wait(30)
	await shot("flat")
	g2._toggle_flat()
	g2.board.farm_view(0)
	await wait(40)
	await shot("farm")
	quit()
