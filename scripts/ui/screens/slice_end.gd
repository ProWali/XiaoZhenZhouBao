## 试玩版到此为止：四期头条排成一张小回顾，请玩家把试玩记录发回来。
## 局提前结束（破产、停刊、报社被毁）也走这里。
extends Control

const K = preload("res://scripts/ui/kit.gd")
const P = preload("res://scripts/ui/palette.gd")

var params := {}


func _ready() -> void:
	var w = Game.world
	Game.track("slice_end", {"game_over": w.game_over if w != null else "", "cash": w.stats.cash if w != null else 0, "cred": w.stats.credibility if w != null else 0})
	Game.copy_save_to_log()
	Game.ambience("night_ambience")
	Game.music("piano_1")
	add_child(K.image("res://assets/sprites/bg/menu_town.png"))
	add_child(K.rect(Color(P.INK, 0.55), Vector2.ZERO, Vector2(640, 360)))
	var sheet := K.paper(Vector2(70, 16), Vector2(500, 328), P.NEWSPRINT)
	add_child(sheet)
	var head := K.label(Game.t("slice_end.title", {"paper": Game.paper_title() if w != null else ""}), "serif_black", 18, P.PRINT_INK)
	head.size = Vector2(500, 24)
	head.position = Vector2(0, 10)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sheet.add_child(head)
	sheet.add_child(K.rect(P.PRINT_INK, Vector2(16, 38), Vector2(468, 1)))
	sheet.add_child(K.rect(P.PRINT_INK, Vector2(16, 40), Vector2(468, 1)))
	var y := 48
	var reason := ""
	if w != null and w.game_over != "":
		# game_over 是模拟层的结局代号（中文），这里只当键用
		var code: String = {"破产": "bankrupt", "停刊": "shut_down", "报社被毁": "destroyed", "登上火车": "train", "任期结束": "term_end"}.get(w.game_over, "")
		reason = Game.t("slice_end.end_" + code) if code != "" else w.game_over
		var r := K.label(reason, "serif_black", 12, P.STAMP_RED)
		r.position = Vector2(20, y)
		sheet.add_child(r)
		y += 22
	for f in Game.ui.get("fronts", []):
		var l := K.para(Game.t("slice_end.issue", {"n": int(f.week), "headline": str(f.headline)}), 460, "serif", 10, P.PRINT_INK, 0)
		l.position = Vector2(20, y)
		sheet.add_child(l)
		y += int(l.get_minimum_size().y) + 6
	if Game.ui.get("fronts", []).is_empty():
		var l := K.label(Game.t("slice_end.no_fronts"), "serif", 10, P.PRINT_INK)
		l.position = Vector2(20, y)
		sheet.add_child(l)
		y += 20
	sheet.add_child(K.rect(Color(P.PRINT_INK, 0.5), Vector2(16, 196), Vector2(468, 1)))
	var thanks := Game.t("slice_end.thanks", {"path": ProjectSettings.globalize_path("user://playtest")})
	var t := K.para(thanks, 460, "hand", 10, P.PENCIL, 2)
	t.position = Vector2(20, 202)
	sheet.add_child(t)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	bar.position = Vector2(20, 296)
	sheet.add_child(bar)
	bar.add_child(K.button(Game.t("slice_end.open_folder"), func(): OS.shell_open(ProjectSettings.globalize_path("user://playtest")), 0))
	if w != null and w.game_over == "":
		var more := K.button(Game.t("slice_end.keep_playing"), func():
			Game.ui.unlocked = true
			Game.track("continue_past_slice")
			Game.route(), 0)
		bar.add_child(more)
	bar.add_child(K.button(Game.t("slice_end.menu"), func(): Game.autosave(); Game.world = null; Game.fade_to("menu"), 0))
