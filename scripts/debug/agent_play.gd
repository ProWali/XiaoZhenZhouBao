## 文字版试玩：让子 Agent 用文字玩真界面。不改画面层，也不绕开它：读当前这一屏所有看得见的字，
## 把能点的东西编上号；点哪个号就照样触发那个按钮或热区。
## 每次调用都从新局开始，把会话里记下的点击重放一遍，再做这一步，然后把当前这一屏打出来。
## 用法（无头，--fixed-fps 让动画和计时器不用等真实时间）：
##   Godot_console.exe --headless --fixed-fps 60 --path . -- --agent --session <目录> --new <种子> [--paper 报名]
##   Godot_console.exe --headless --fixed-fps 60 --path . -- --agent --session <目录> --do <编号>[,<编号>...]
## --do 可以一次点好几下（逗号隔开），只打出最后一屏；中间每一屏照样记进 transcript.md。不带 --do 就只把当前这一屏再打一遍。会话目录里：session.json（种子和点击）、save.json（存档，replay_report 能读）、transcript.md（每一屏和每一次点击）。
extends Node

const Hotspot = preload("res://scripts/ui/hotspot.gd")
const P = preload("res://scripts/ui/palette.gd")

## 画面文件名 -> 玩家眼里这是哪儿
const SCREEN_NAMES := {
	"office": "编辑室", "town_map": "镇子地图", "location": "地点", "visitors": "周六夜·来访",
	"layout": "周日·排版台", "press": "印刷", "slice_end": "试玩结束", "letters": "读信",
	"notebook": "选题簿", "pick": "选人/选话头", "result": "结果", "confirm": "确认",
	"proof": "清样", "settings": "设置",
}

var _dir := ""
var _session := {}


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var todo: Array = []
	var new_seed := -1
	var paper := ""
	for i in args.size():
		if args[i] == "--session": _dir = args[i + 1]
		if args[i] == "--do":
			for x in args[i + 1].split(",", false):
				todo.append(int(x))
		if args[i] == "--new": new_seed = int(args[i + 1])
		if args[i] == "--paper": paper = args[i + 1]
	_run.call_deferred(todo, new_seed, paper)


func _run(todo: Array, new_seed: int, paper: String) -> void:
	DirAccess.make_dir_recursive_absolute(_dir)
	var sp := _dir.path_join("session.json")
	if new_seed >= 0:
		_session = {"seed": new_seed, "paper": paper if paper != "" else Game.t("common.default_paper"), "clicks": []}
		if FileAccess.file_exists(_dir.path_join("transcript.md")):
			DirAccess.remove_absolute(_dir.path_join("transcript.md"))
	else:
		var d = JSON.parse_string(FileAccess.get_file_as_string(sp))
		if not (d is Dictionary):
			_quit("会话不存在：%s。先用 --new <种子> 开局。" % _dir)
			return
		_session = d
	Game.new_game({"seed": int(_session.seed), "paper_name": str(_session.paper), "player_name": Game.t("common.default_editor")})
	Game.route(false)
	for c in _session.clicks:
		await _settle()
		var it := _find(_items(), str(c.label), int(c.nth))
		if it.is_empty():
			_quit("重放失败：第 %d 步找不到「%s」。会话和当前版本对不上。" % [_session.clicks.find(c) + 1, c.label])
			return
		_click(it)
	await _settle()
	var err := ""
	for k in todo.size():
		var do_n: int = todo[k]
		var items := _items()
		if do_n < 1 or do_n > items.size():
			err = "没有编号 %d，请从上面的编号里选。" % do_n
			break
		var it: Dictionary = items[do_n - 1]
		_session.clicks.append({"label": it.label, "nth": it.nth})
		_append("→ 点了 [%d] %s\n" % [do_n, it.label])
		_click(it)
		await _settle()
		if k < todo.size() - 1:
			_append("\n### 第 %d 步之后\n%s\n" % [_session.clicks.size(), _dump()])
	var f := FileAccess.open(sp, FileAccess.WRITE)
	f.store_string(JSON.stringify(_session, "\t"))
	f.close()
	var out := _dump()
	_append("\n### 第 %d 步之后\n%s\n" % [_session.clicks.size(), out])
	print(out)
	_quit(err)


func _quit(msg: String) -> void:
	if msg != "":
		print(msg)
	get_tree().quit(0 if msg == "" else 1)


## 等动画、渐变和计时器走完。印刷那一屏有十秒的计时器。
func _settle() -> void:
	var frames := 60
	var s := Game.current_screen()
	if s != null and s.get_script().resource_path.get_file().get_basename() == "press":
		frames = 60 * 12
	for i in frames:
		await get_tree().process_frame


func _append(s: String) -> void:
	var p := _dir.path_join("transcript.md")
	var f := FileAccess.open(p, FileAccess.READ_WRITE if FileAccess.file_exists(p) else FileAccess.WRITE)
	f.seek_end()
	f.store_string(s)
	f.close()


func _screen_root() -> Control:
	if Game.has_overlay():
		return Game._overlay
	return Game.current_screen()


func _name_of(c: Control) -> String:
	var base: String = c.get_script().resource_path.get_file().get_basename()
	return SCREEN_NAMES.get(base, base)


## 当前这一屏看得见的东西，按搭建的顺序。叠层盖在上面时只读叠层（底下的点不到）。
## 每项 {kind: text|click, text, label, node, nth}
func _items_all() -> Array:
	var out: Array = []
	var root := _screen_root()
	if root != null:
		_walk(root, out)
	# 报纸正文分两栏，每栏是同一段全文挪了位置再裁掉，读一遍就够
	var said := {}
	out = out.filter(func(it):
		if it.kind != "text" or it.text.length() < 20:
			return true
		if said.has(it.text):
			return false
		said[it.text] = true
		return true)
	var seen := {}
	for it in out:
		if it.kind == "click":
			it.nth = int(seen.get(it.label, 0))
			seen[it.label] = it.nth + 1
	return out


func _items() -> Array:
	return _items_all().filter(func(it): return it.kind == "click")


func _walk(n: Node, out: Array) -> void:
	if n is CanvasItem and not n.is_visible_in_tree():
		return
	if n.has_meta("stamps"):
		var st: Array = n.get_meta("stamps")
		out.append({"kind": "text", "text": "〔章%d/%d〕" % [st[0], st[1]]})
	if n is Hotspot:
		var s := str(n.tip)
		if str(n.plate) != "" and s == "":
			s += "（名牌：%s）" % n.plate
		if str(n.badge) != "":
			s += "（角标：%s）" % n.badge
		if n.enabled and n.cb.is_valid():
			out.append({"kind": "click", "label": s, "node": n})
		else:
			out.append({"kind": "text", "text": s + "（点不了）"})
	elif n is Button:
		var s := str(n.text).replace("\n", " / ")
		if s == "≡":
			return
		if n is CheckBox or n.toggle_mode:
			s = ("[✓] " if n.button_pressed else "[ ] ") + s
		elif _highlighted(n):
			s = "【选中】" + s
		if n.tooltip_text != "" and n.tooltip_text != "Tab":
			s += "（提示：%s）" % n.tooltip_text
		if n.disabled:
			out.append({"kind": "text", "text": s + "（点不了）"})
		else:
			out.append({"kind": "click", "label": s, "node": n})
	elif n is RichTextLabel:
		if n.get_parsed_text().strip_edges() != "":
			out.append({"kind": "text", "text": n.get_parsed_text().strip_edges()})
	elif n is Label:
		if n.text.strip_edges() != "":
			out.append({"kind": "text", "text": n.text.strip_edges()})
	elif n is LineEdit:
		out.append({"kind": "text", "text": "输入框：" + n.text})
	for c in n.get_children():
		_walk(c, out)


## 排版台、语气、署名这些「选中哪个」只靠底色表示：底色是灯黄或赭石就算选中
func _highlighted(b: Button) -> bool:
	if not b.has_theme_stylebox_override("normal"):
		return false
	var sb = b.get_theme_stylebox("normal")
	return sb is StyleBoxFlat and (sb.bg_color.is_equal_approx(P.LAMP) or sb.bg_color.is_equal_approx(P.OCHRE))


func _find(items: Array, label: String, nth: int) -> Dictionary:
	for it in items:
		if it.label == label and it.nth == nth:
			return it
	return {}


func _click(it: Dictionary) -> void:
	var n: Control = it.node
	if n is Hotspot:
		n.cb.call()
	elif n is Button:
		if n.toggle_mode:
			n.button_pressed = not n.button_pressed
		n.pressed.emit()


func _dump() -> String:
	var w = Game.world
	var root := _screen_root()
	var head := "=== %s" % (_name_of(root) if root != null else "?")
	if Game.has_overlay():
		head += "（盖在「%s」上面）" % _name_of(Game.current_screen())
	if w != null:
		head += " · 第 %d 周 %s %s" % [w.week, Game.day_name(w.day), Game.slot_name(w.slot) if w.day <= 6 else ""]
	head += " ===（会话 %s）" % _dir.get_file()
	var lines: Array = [head]
	var k := 0
	for it in _items_all():
		if it.kind == "text":
			lines.append(it.text)
		else:
			k += 1
			lines.append("[%d] %s" % [k, it.label])
	return "\n".join(lines)
