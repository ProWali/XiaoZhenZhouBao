## 游戏总控（自动加载，名字 Game）：持有世界，决定现在该进哪个界面，管存档、音频、字体和试玩记录。
## 模拟层不知道有画面；画面层只通过 world 的公开函数推进模拟，所有操作照常进存档的操作日志。
extends Node

const World = preload("res://scripts/sim/world.gd")
const Save = preload("res://scripts/sim/save.gd")
const P = preload("res://scripts/ui/palette.gd")
const Portrait = preload("res://scripts/ui/portrait.gd")

const SLICE_WEEKS := 4          # 垂直切片只开放前四周；第五周周一读完信就结束
const SAVE_PATH := "user://saves/slot1.json"
const VERSION := "M4 试玩版"

var world = null
## 画面层自己的进度，和模拟存档一起存。模拟状态都在 world 里，这里只记「玩家看过了没有」。
var ui := {}
var settings := {"master": 0.8, "music": 0.6, "sfx": 0.8, "fullscreen": false}
var fonts := {}
var theme: Theme

var _layer: CanvasLayer
var _root: Control
var _current: Control
var _fade: ColorRect
var _overlay: Control
var _sfx_players: Array = []
var _sfx_cache := {}
var _music: AudioStreamPlayer
var _ambience: AudioStreamPlayer
var _ambience_name := ""
var _log_path := ""
var _session_start := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## 由 main.tscn 调用。无头工具脚本不会走到这里。
func boot() -> void:
	_load_settings()
	_build_fonts()
	_build_theme()
	_build_audio()
	_layer = CanvasLayer.new()
	add_child(_layer)
	_root = Control.new()
	_root.size = Vector2(640, 360)
	_root.theme = theme
	_layer.add_child(_root)
	_fade = ColorRect.new()
	_fade.color = P.INK
	_fade.size = Vector2(640, 360)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.modulate.a = 0.0
	var top := CanvasLayer.new()
	top.layer = 10
	add_child(top)
	top.add_child(_fade)
	_apply_settings()
	goto("menu")


# ------------------------------------------------------------ 字体与主题
func _font(path: String, pixel: bool) -> FontFile:
	var f: FontFile = load(path)
	f = f.duplicate()
	if pixel:
		f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		f.hinting = TextServer.HINTING_NONE
		f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	else:
		f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		f.hinting = TextServer.HINTING_LIGHT
	return f


func _build_fonts() -> void:
	fonts.pixel = _font("res://assets/fonts/fusion-pixel-12px.ttf", true)
	fonts.serif = _font("res://assets/fonts/serif-sub.otf", false)
	fonts.serif_black = _font("res://assets/fonts/serif-black-sub.otf", false)
	fonts.hand = _font("res://assets/fonts/wenkai-sub.ttf", false)


func _box(bg: Color, border: Color, bw := 1, pad := Vector4(5, 2, 5, 2)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.content_margin_left = pad.x
	s.content_margin_top = pad.y
	s.content_margin_right = pad.z
	s.content_margin_bottom = pad.w
	s.anti_aliasing = false
	return s


func _build_theme() -> void:
	theme = Theme.new()
	theme.default_font = fonts.pixel
	theme.default_font_size = 12
	theme.set_stylebox("normal", "Button", _box(P.PAPER, P.INK))
	theme.set_stylebox("hover", "Button", _box(P.LAMP, P.INK))
	theme.set_stylebox("pressed", "Button", _box(P.OCHRE, P.INK))
	theme.set_stylebox("disabled", "Button", _box(P.STONE, P.WARM_GREY))
	theme.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), P.BRICK, 1))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		theme.set_color(k, "Button", P.INK)
	theme.set_color("font_disabled_color", "Button", P.WARM_GREY)
	theme.set_color("font_color", "Label", P.INK)
	theme.set_color("default_color", "RichTextLabel", P.INK)
	theme.set_stylebox("panel", "PanelContainer", _box(P.PAPER, P.INK, 1, Vector4(6, 6, 6, 6)))
	theme.set_stylebox("panel", "Panel", _box(P.PAPER, P.INK))
	theme.set_stylebox("normal", "LineEdit", _box(P.NEWSPRINT, P.INK))
	theme.set_stylebox("focus", "LineEdit", _box(P.NEWSPRINT, P.BRICK))
	theme.set_color("font_color", "LineEdit", P.INK)
	theme.set_color("caret_color", "LineEdit", P.INK)
	theme.set_color("selection_color", "LineEdit", P.LAMP)
	theme.set_stylebox("normal", "CheckBox", _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0))
	theme.set_stylebox("hover", "CheckBox", _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0))
	theme.set_stylebox("pressed", "CheckBox", _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0))
	theme.set_stylebox("hover_pressed", "CheckBox", _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0))
	theme.set_stylebox("focus", "CheckBox", _box(Color(0, 0, 0, 0), P.BRICK, 1))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		theme.set_color(k, "CheckBox", P.INK)
	var grab := _box(P.WARM_GREY, P.WARM_GREY, 0)
	theme.set_stylebox("grabber", "VScrollBar", grab)
	theme.set_stylebox("grabber_highlight", "VScrollBar", _box(P.UMBER, P.UMBER, 0))
	theme.set_stylebox("grabber_pressed", "VScrollBar", _box(P.INK, P.INK, 0))
	theme.set_stylebox("scroll", "VScrollBar", _box(Color(0, 0, 0, 0.08), Color(0, 0, 0, 0), 0, Vector4(3, 0, 3, 0)))
	theme.set_stylebox("slider", "HSlider", _box(P.STONE, P.INK, 1, Vector4(0, 2, 0, 2)))
	theme.set_stylebox("grabber_area", "HSlider", _box(P.OCHRE, P.INK, 1, Vector4(0, 2, 0, 2)))
	theme.set_stylebox("grabber_area_highlight", "HSlider", _box(P.LAMP, P.INK, 1, Vector4(0, 2, 0, 2)))
	theme.set_stylebox("panel", "TooltipPanel", _box(P.INK, P.PAPER, 1, Vector4(4, 2, 4, 2)))
	theme.set_color("font_color", "TooltipLabel", P.PAPER)


# ------------------------------------------------------------ 界面切换
func goto(screen: String, params := {}) -> void:
	close_overlay()
	var script: GDScript = load("res://scripts/ui/screens/%s.gd" % screen)
	var node: Control = script.new()
	node.size = Vector2(640, 360)
	if "params" in node:
		node.params = params
	if _current != null:
		_current.queue_free()
	_current = node
	_root.add_child(node)
	track("screen", {"screen": screen, "mode": str(params.get("mode", "")), "loc": str(params.get("loc", ""))})


func fade_to(screen: String, params := {}, dur := 0.35) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "modulate:a", 1.0, dur)
	tw.tween_callback(func(): goto(screen, params))
	tw.tween_property(_fade, "modulate:a", 0.0, dur)


## 叠在当前界面上的一层（选题簿、设置、读信）。同时只有一层。
func open_overlay(screen: String, params := {}) -> Control:
	close_overlay()
	var script: GDScript = load("res://scripts/ui/screens/%s.gd" % screen)
	var node: Control = script.new()
	node.size = Vector2(640, 360)
	if "params" in node:
		node.params = params
	_overlay = node
	_root.add_child(node)
	track("overlay", {"screen": screen})
	return node


func close_overlay() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null


func has_overlay() -> bool:
	return _overlay != null and is_instance_valid(_overlay)


func current_screen() -> Control:
	return _current


## 按模拟状态决定现在该去哪一屏。任何一步做完都可以调它。
func route(fade := true) -> void:
	var dest := ""
	var params := {}
	if world == null:
		dest = "menu"
	elif world.game_over != "":
		dest = "slice_end"
	elif int(ui.get("letters_week", 0)) < world.week:
		dest = "office"
		params = {"mode": "morning"}
	elif world.week > SLICE_WEEKS and not bool(ui.get("unlocked", false)):
		dest = "slice_end"
	elif int(ui.get("saturday_week", 0)) < world.week and world.day <= 6:
		dest = "office"
		params = {"mode": "day"}
	elif int(ui.get("visitors_done_week", 0)) < world.week:
		dest = "visitors"
	else:
		dest = "layout"
	autosave()
	if fade:
		fade_to(dest, params)
	else:
		goto(dest, params)


# ------------------------------------------------------------ 一天的推进
## 玩家要收工。白天还有行动点、或者是周六，先问一句。
func request_end_day() -> void:
	var left: int = world.actions_left if world.slot <= 1 else 0
	var text := ""
	if left > 0:
		text = "今天还有 %d 个行动点没用。现在收工，今晚也不出门了。" % left
	elif world.day == 6:
		text = "周六收工。晚上可能有人上门，明天周日排版付印。"
	if text == "":
		_end_day()
	else:
		open_overlay("confirm", {"text": text, "yes": "收工", "no": "再等等", "on_yes": _end_day})


func _end_day() -> void:
	track("end_day", {"actions_left": world.actions_left if world.slot <= 1 else 0})
	world.end_day()
	sfx("footsteps_wood")
	route()


## 一次行动做完：记录、存档、弹出结果。on_close 决定关掉之后去哪。
func show_result(title: String, res: Dictionary, who: String, on_close: Callable) -> void:
	track("action", {"title": title, "ok": res.ok, "gained": res.gained.size(), "who": who})
	autosave()
	open_overlay("result", {"title": title, "lines": res.lines, "who": who, "gained": res.gained, "on_close": on_close})


# ------------------------------------------------------------ 新局与存档
func new_game(cfg: Dictionary) -> void:
	Portrait.clear_cache()
	world = World.new(int(cfg.seed), {"total_weeks": 104, "ironman": bool(cfg.get("ironman", true)), "lang": "zh", "suicide": bool(cfg.get("suicide", false))})
	world.paper_name = str(cfg.get("paper_name", "灰河周报"))
	world.player_name = str(cfg.get("player_name", "主编"))
	ui = {"letters_week": 0, "saturday_week": 0, "visitors_done_week": 0, "visitors": [], "last_issue": {}, "cash_week_start": 30.0, "fronts": []}
	_start_log()
	track("new_game", {"seed": int(cfg.seed), "paper": world.paper_name})
	autosave()


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func autosave() -> void:
	if world == null:
		return
	DirAccess.make_dir_recursive_absolute("user://saves")
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"save": Save.to_dict(world), "ui": ui, "log": _log_path}))
	f.close()


func continue_game() -> bool:
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not (data is Dictionary) or not data.has("save"):
		return false
	Portrait.clear_cache()
	world = Save.from_dict(data.save)
	ui = data.get("ui", {})
	for k in ["letters_week", "saturday_week", "visitors_done_week"]:
		ui[k] = int(ui.get(k, 0))
	_log_path = str(data.get("log", ""))
	if _log_path == "":
		_start_log()
	_session_start = Time.get_ticks_msec()
	track("continue", {"week": world.week, "day": world.day, "replay_error": world.replay_error})
	return true


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


# ------------------------------------------------------------ 试玩记录
## 每次试玩写一份 JSON Lines：看了哪一屏、做了什么、花了多久。试玩结束时请玩家把这个文件发回来。
func _start_log() -> void:
	DirAccess.make_dir_recursive_absolute("user://playtest")
	var t := Time.get_datetime_dict_from_system()
	_log_path = "user://playtest/session-%04d%02d%02d-%02d%02d%02d.jsonl" % [t.year, t.month, t.day, t.hour, t.minute, t.second]
	_session_start = Time.get_ticks_msec()


func track(kind: String, data := {}) -> void:
	if _log_path == "":
		return
	var rec := {"t": int((Time.get_ticks_msec() - _session_start) / 1000), "kind": kind}
	if world != null:
		rec["week"] = world.week
		rec["day"] = world.day
		rec["slot"] = world.slot
	for k in data:
		rec[k] = data[k]
	var f := FileAccess.open(_log_path, FileAccess.READ_WRITE if FileAccess.file_exists(_log_path) else FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(JSON.stringify(rec))
	f.close()


func log_path_global() -> String:
	return ProjectSettings.globalize_path(_log_path)


# ------------------------------------------------------------ 音频
func _build_audio() -> void:
	for bus in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	for i in 6:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_sfx_players.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	_ambience = AudioStreamPlayer.new()
	_ambience.bus = "SFX"
	_ambience.volume_db = -4.0
	add_child(_ambience)
	_ambience.finished.connect(func(): _ambience.play())


func sfx(name: String, vol_db := 0.0) -> void:
	if _sfx_players.is_empty():
		return
	if not _sfx_cache.has(name):
		var path := "res://assets/audio/sfx/%s.wav" % name
		_sfx_cache[name] = load(path) if ResourceLoader.exists(path) else null
	var stream = _sfx_cache[name]
	if stream == null:
		return
	for p in _sfx_players:
		if not p.playing:
			p.stream = stream
			p.volume_db = vol_db
			p.play()
			return
	_sfx_players[0].stream = stream
	_sfx_players[0].volume_db = vol_db
	_sfx_players[0].play()


func ambience(name: String) -> void:
	if _ambience == null or _ambience_name == name:
		return
	_ambience_name = name
	if name == "":
		_ambience.stop()
		return
	var path := "res://assets/audio/sfx/%s.wav" % name
	if ResourceLoader.exists(path):
		_ambience.stream = load(path)
		_ambience.play()


## 配乐不循环，弹完就安静（策划案六版）。
func music(name: String) -> void:
	if _music == null:
		return
	var path := "res://assets/audio/music/%s.mp3" % name
	if not ResourceLoader.exists(path):
		return
	if _music.playing and _music.stream != null and _music.stream.resource_path == path:
		return
	_music.stream = load(path)
	_music.play()


func stop_music() -> void:
	if _music != null:
		var tw := create_tween()
		tw.tween_property(_music, "volume_db", -40.0, 1.5)
		tw.tween_callback(func(): _music.stop(); _music.volume_db = 0.0)


# ------------------------------------------------------------ 设置
func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK:
		for k in settings:
			settings[k] = cfg.get_value("settings", k, settings[k])


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for k in settings:
		cfg.set_value("settings", k, settings[k])
	cfg.save("user://settings.cfg")
	_apply_settings()


func _apply_settings() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.001, float(settings.master))))
	var mi := AudioServer.get_bus_index("Music")
	if mi >= 0:
		AudioServer.set_bus_volume_db(mi, linear_to_db(maxf(0.001, float(settings.music))))
	var si := AudioServer.get_bus_index("SFX")
	if si >= 0:
		AudioServer.set_bus_volume_db(si, linear_to_db(maxf(0.001, float(settings.sfx))))
	if not DisplayServer.get_name().begins_with("headless"):
		var want := DisplayServer.WINDOW_MODE_FULLSCREEN if settings.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != want:
			DisplayServer.window_set_mode(want)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F11 or (event.keycode == KEY_ENTER and event.alt_pressed):
			settings.fullscreen = not settings.fullscreen
			save_settings()
