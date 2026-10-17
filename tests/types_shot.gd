extends SceneTree
## Una foto per ogni tipo di decisione (la prima volta che compare). Serve xvfb-run.
## godot --path . -s res://tests/types_shot.gd -- <giocatori> <espansioni o -> <seme> <massimo foto>

var main
var done := {}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir() + "/shots")
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var np := int(args[0]) if args.size() > 0 else 3
	var o := {}
	if args.size() > 1 and args[1] != "-":
		for k in args[1].split(","):
			o[k] = true
	var seed := int(args[2]) if args.size() > 2 else 4
	var mx := int(args[3]) if args.size() > 3 else 8
	var seats := []
	for i in np:
		seats.append({"color": i, "ai": i != 0, "name": ["Stefano", "Giallo", "Blu", "Bianco", "Grigio"][i], "level": 1})
	main.start_game({"seats": seats, "seed": seed, "opts": o, "ai_delay": 0.0, "hints": true})
	for guard in 30000:
		await process_frame
		var g = main.current
		if g.engine.game_over or done.size() >= mx:
			break
		if not g.modal.get_children().is_empty():
			g._clear_modal()
			g.engine.provide_decision(null)
			continue
		if g.pending.is_empty():
			continue
		var t: String = g.pending["type"]
		if t != "turn" and not done.has(t):
			done[t] = true
			for i in 6:
				await process_frame
			var img := root.get_viewport().get_texture().get_image()
			img.crop(1920, 1080)
			img.get_region(Rect2i(490, 560, 1050, 520)).save_png(OS.get_user_data_dir() + "/shots/t_%s.png" % t)
			print("shot ", t)
		var r = g.engine.ais[int(g.pending["seat"])].decide(g.engine, int(g.pending["seat"]), g.pending)
		g._provide(r)
	quit()
