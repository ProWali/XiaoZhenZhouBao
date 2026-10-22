## 自动走查：在真窗口里把试玩版从主菜单走到第五周周一，每一屏截图，审界面用。
## 用法：Godot_v4.7.2-stable_win64.exe --path . -- --walkthrough --seed 7 --shots <目录>
## 导出包也能用：XiaoZhenZhouBao.exe -- --walkthrough --seed 7 --shots <目录>
## 它像一个规矩的玩家：白天找人聊、问选题簿里的事、查档案，每周熬一夜，周六见客，周日把最好的料排上版。
## 直接调各界面的内部函数，跳过鼠标；报错看控制台输出。
extends Node

const TE = preload("res://scripts/text/text_engine.gd")

var _dir := ""
var _seed := 7
var _n := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--seed": _seed = int(args[i + 1])
		if args[i] == "--shots": _dir = args[i + 1]
	if _dir == "":
		_dir = ProjectSettings.globalize_path("user://walkthrough")
	DirAccess.make_dir_recursive_absolute(_dir)
	_rng.seed = _seed
	Engine.time_scale = 4.0
	_run.call_deferred()


func _wait(sec := 0.5) -> void:
	await get_tree().create_timer(sec).timeout


func _shot(name: String) -> void:
	await _wait(0.6)
	await RenderingServer.frame_post_draw
	_n += 1
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%02d_%s.png" % [_dir, _n, name])
	print("[shot] %02d_%s" % [_n, name])


func _screen() -> Control:
	return Game.current_screen()


func _run() -> void:
	await _shot("menu")
	Game.open_overlay("settings")
	await _shot("settings")
	Game.close_overlay()
	Game.goto("new_game")
	await _shot("new_game")
	if Game.has_save():
		Game.delete_save()
	Game.new_game({"seed": _seed, "paper_name": "灰河周报", "player_name": "走查"})
	Game.route(false)
	var guard := 0
	while guard < 400:
		guard += 1
		await _wait(0.4)
		var s := _screen()
		var name: String = s.get_script().resource_path.get_file().get_basename()
		var w = Game.world
		if name == "slice_end":
			await _shot("slice_end")
			break
		match name:
			"office":
				if s.params.get("mode", "") == "morning":
					await _wait(1.0)
					await _shot("w%d_morning" % w.week)
					await _read_letters()
				else:
					await _day_step()
			"town_map":
				await _day_step()
			"location":
				await _day_step()
			"visitors":
				await _visitors()
			"layout":
				await _layout()
			"press":
				await _press()
	print("[walkthrough] done, %d shots in %s" % [_n, _dir])
	get_tree().quit()


func _read_letters() -> void:
	var w = Game.world
	var ov: Control = Game.open_overlay("letters", {"on_done": func():
		Game.ui.letters_week = w.week
		Game.route(false)})
	var pages: int = ov._pages.size()
	for i in pages:
		await _shot("w%d_letter%d" % [w.week, i + 1])
		ov._next()
	await _wait(0.5)


## 白天的一步：有行动点就去人多的地方找人谈；每周三晚上熬一夜；没事可做就收工
func _day_step() -> void:
	var w = Game.world
	if w.day > 6:
		Game.route(false)
		return
	if w.slot >= 2:
		if w.day == 3 and w.can_act_night():
			Game.goto("town_map")
			await _shot("w%d_night_map" % w.week)
			var spots := ["tavern", "river", "bridge", "woods", "mill"]
			var loc: String = spots[_rng.randi() % spots.size()]
			var res: Dictionary = w.act_eavesdrop() if loc == "tavern" else w.act_stakeout(loc)
			Game.show_result("夜里", res, "", func(): Game.route(false))
			await _shot("w%d_night_result" % w.week)
			Game.close_overlay()
			Game.route(false)
		else:
			w.end_day()
			Game.route(false)
		return
	if not w.can_act_day():
		w.end_day()
		Game.route(false)
		return
	var first_today: bool = w.slot == 0 and w.actions_left == 2
	if w.week == 1 and w.day == 1 and first_today:
		Game.goto("office", {"mode": "day"})
		await _shot("w1_office_day")
		Game.open_overlay("notebook")
		await _shot("w1_notebook_empty")
		Game.close_overlay()
	# 查档案：选题簿里有提示指向某处档案时去查
	for g in w.notebook():
		for h in g.hints:
			for loc in ["post", "hall", "clinic", "store"]:
				if h.find(w.loc_name(loc)) >= 0 and h.find("档案") >= 0 and _rng.randf() < 0.5:
					Game.goto("location", {"loc": loc})
					await _shot("w%d_d%d_%s" % [w.week, w.day, loc])
					var res: Dictionary = w.act_archive(loc)
					Game.show_result("档案", res, "", func(): pass)
					await _shot("w%d_d%d_archive" % [w.week, w.day])
					Game.close_overlay()
					return
	# 有线头就顺着线头去
	for l in w.leads:
		var lloc: String = w.where_is(l.who)
		if lloc != "" and not lloc.begins_with("home:") and lloc != "office":
			Game.goto("location", {"loc": lloc})
			await _shot("w%d_d%d_lead_%s" % [w.week, w.day, lloc])
			var lres: Dictionary = w.act_interview(l.who, "")
			Game.show_result("和%s谈" % w.residents[l.who].name, lres, l.who, func(): pass)
			await _shot("w%d_d%d_lead_talk" % [w.week, w.day])
			Game.close_overlay()
			return
	# 找人谈
	var best := ""
	var best_n := 0
	for loc in w.public_locations():
		var n: int = w.people_at(loc).size()
		if n > best_n or (n == best_n and _rng.randf() < 0.3):
			best_n = n
			best = loc
	if best == "":
		w.end_day()
		Game.route(false)
		return
	if first_today and (w.day == 1 or w.day == 4):
		Game.goto("town_map")
		await _shot("w%d_d%d_map" % [w.week, w.day])
	Game.goto("location", {"loc": best})
	if first_today:
		await _shot("w%d_d%d_%s" % [w.week, w.day, best])
	var people: Array = w.people_at(best)
	var rid: String = people[_rng.randi() % people.size()]
	var topic := ""
	var groups: Array = w.notebook()
	if not groups.is_empty() and _rng.randf() < 0.6:
		var g: Dictionary = groups[_rng.randi() % groups.size()]
		topic = g.facts[_rng.randi() % g.facts.size()]
	if w.day == 2 and first_today:
		_screen()._talk(rid)
		await _shot("w%d_topics" % w.week)
		Game.close_overlay()
	var res: Dictionary = w.act_interview(rid, topic)
	Game.show_result("和%s谈" % w.residents[rid].name, res, rid, func(): pass)
	if first_today:
		await _shot("w%d_d%d_talk" % [w.week, w.day])
	Game.close_overlay()
	if w.day == 5 and first_today and not w.notebook().is_empty():
		var nb: Control = Game.open_overlay("notebook")
		await _shot("w%d_notebook" % w.week)
		nb._tab = "people"
		nb._sel = ""
		nb._build()
		await _shot("w%d_notebook_people" % w.week)
		nb._tab = "leads"
		nb._build()
		await _shot("w%d_notebook_leads" % w.week)
		Game.close_overlay()


func _visitors() -> void:
	var s := _screen()
	await _wait(0.5)
	var vs: Array = Game.ui.get("visitors", [])
	await _shot("w%d_visitors" % Game.world.week)
	for i in vs.size():
		if vs[s._i].kind == "deal" and _rng.randf() < 0.5:
			Game.world.accept_deal(vs[s._i])
			Game.ui.deals[str(s._i)] = true
		if i > 0:
			await _shot("w%d_visitor%d" % [Game.world.week, i + 1])
		s._next()
		await _wait(0.2)
	if vs.is_empty():
		s._done()


func _layout() -> void:
	var s := _screen()
	var w = Game.world
	await _shot("w%d_layout" % w.week)
	var groups: Array = s._groups()
	groups.sort_custom(func(a, b): return a.facts.size() > b.facts.size())
	var slots := ["head", "second", "third", "small"]
	for i in mini(groups.size(), 4):
		s._sel_story = groups[i].event.id
		s._place(groups[i].event.id, slots[i])
		if i == 0:
			var a: Dictionary = s._arts["head"]
			a.tone = ["calm", "neutral", "hot"][_rng.randi() % 3]
			a.naming = ["named", "alias", "anon"][_rng.randi() % 3] if not groups[i].event.soft else "named"
		s._refresh()
		if i == 0:
			await _shot("w%d_layout_edit" % w.week)
			s._proof("head")
			await _shot("w%d_proof" % w.week)
			Game.close_overlay()
	s._edit = ""
	s._refresh()
	await _shot("w%d_layout_full" % w.week)
	var arts: Array = []
	for a in s._ordered():
		arts.append(a.duplicate(true))
	Game.goto("press", {"articles": arts, "choice": s._choice.duplicate()})


func _press() -> void:
	var s := _screen()
	await _shot("w%d_press" % Game.world.week)
	s._pull()
	await _wait(2.0)
	await _shot("w%d_press_run" % (Game.world.week - 1))
	await _wait(12.0)
